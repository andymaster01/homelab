import json
import os
import re
import shutil
import sqlite3
import threading
import time
import unicodedata
import uuid
from datetime import datetime, timezone
from pathlib import Path
from urllib.parse import urlparse

import requests
from fastapi import FastAPI, File, Form, HTTPException, UploadFile
from fastapi.responses import FileResponse


STATE_DIR = Path(os.getenv("STATE_DIR", "/state"))
JOB_DIR = STATE_DIR / "jobs"
DB_PATH = STATE_DIR / "jobs.sqlite3"
OUTPUT_DIR = Path(os.getenv("OUTPUT_DIR", "/mnt/media/audiobooks"))
GENERATIONS_DIR = Path(os.getenv("GENERATIONS_DIR", "/mnt/media/podcast/manual"))
VOICEBOX_URL = os.getenv("VOICEBOX_URL", "http://voicebox:17493").rstrip("/")
DEFUDDLE_URL = os.getenv("DEFUDDLE_URL", "http://defuddle:8080").rstrip("/")
DOCLING_URL = os.getenv("DOCLING_URL", "http://docling:5001").rstrip("/")
MP3_WAIT_SECONDS = int(os.getenv("MP3_WAIT_SECONDS", "43200"))
MAX_UPLOAD_BYTES = 200 * 1024 * 1024
TERMINAL = {"completed", "failed"}

STATE_DIR.mkdir(parents=True, exist_ok=True)
JOB_DIR.mkdir(parents=True, exist_ok=True)


def connect_db():
    connection = sqlite3.connect(DB_PATH, timeout=30)
    connection.row_factory = sqlite3.Row
    return connection


def initialize_db():
    with connect_db() as db:
        db.execute("""CREATE TABLE IF NOT EXISTS jobs (
            id TEXT PRIMARY KEY, title TEXT NOT NULL, source TEXT NOT NULL,
            status TEXT NOT NULL, step TEXT NOT NULL, progress INTEGER NOT NULL,
            message TEXT NOT NULL, profile_id TEXT NOT NULL, language TEXT NOT NULL,
            input_path TEXT, result_path TEXT, error TEXT, created_at TEXT NOT NULL,
            updated_at TEXT NOT NULL
        )""")
        db.execute("UPDATE jobs SET status='queued', step='queued', message='Requeued after worker restart', updated_at=? WHERE status='processing'",
                   (now(),))


def now():
    return datetime.now(timezone.utc).isoformat()


def update_job(job_id, **values):
    values["updated_at"] = now()
    fields = ", ".join(f"{key}=?" for key in values)
    with connect_db() as db:
        db.execute(f"UPDATE jobs SET {fields} WHERE id=?", (*values.values(), job_id))


def read_job(row):
    data = dict(row)
    data.pop("input_path", None)
    return data


def safe_name(value, fallback="Audiobook"):
    value = unicodedata.normalize("NFKD", value or "")
    value = "".join(ch for ch in value if not unicodedata.combining(ch))
    value = re.sub(r"[^A-Za-z0-9._ -]+", "", value)
    value = re.sub(r"[ ._-]+", " ", value).strip(" .")
    return (value[:100] or fallback)


def split_chapters(markdown):
    lines = markdown.replace("\r\n", "\n").splitlines()
    headings = [i for i, line in enumerate(lines) if re.match(r"^#{1,2}\s+\S", line)]
    sections = []
    if headings:
        if any(line.strip() for line in lines[:headings[0]]):
            sections.append(("Introduction", "\n".join(lines[:headings[0]]).strip()))
        for n, start in enumerate(headings):
            end = headings[n + 1] if n + 1 < len(headings) else len(lines)
            title = re.sub(r"^#{1,2}\s+", "", lines[start]).strip()
            text = "\n".join(lines[start + 1:end]).strip()
            if text:
                sections.append((title or f"Chapter {n + 1}", text))
    if not sections:
        text = markdown.strip()
        if text:
            sections = [("Part 1", text)]

    # Voicebox accepts at most 50,000 characters per request. Split oversized
    # sections on paragraph boundaries and keep the chapter heading on part one.
    result = []
    for title, text in sections:
        paragraphs = re.split(r"\n\s*\n", text)
        chunk, count, part = [], 0, 1
        for paragraph in paragraphs:
            paragraph = paragraph.strip()
            if not paragraph:
                continue
            pieces = []
            while len(paragraph) > 45000:
                boundary = paragraph.rfind(" ", 0, 45000)
                if boundary <= 0:
                    boundary = 45000
                pieces.append(paragraph[:boundary])
                paragraph = paragraph[boundary:].strip()
            if paragraph:
                pieces.append(paragraph)
            for piece in pieces:
                if chunk and count + len(piece) + 2 > 45000:
                    result.append((title if part == 1 else f"{title} (continued {part})", "\n\n".join(chunk)))
                    chunk, count, part = [], 0, part + 1
                chunk.append(piece)
                count += len(piece) + 2
        if chunk:
            result.append((title if part == 1 else f"{title} (continued {part})", "\n\n".join(chunk)))
    return result


def docling_extract(path):
    suffix = path.suffix.lower()
    fmt = "epub" if suffix == ".epub" else "pdf"
    with path.open("rb") as stream:
        response = requests.post(
            f"{DOCLING_URL}/v1/convert/file",
            files={"files": (path.name, stream, "application/pdf" if fmt == "pdf" else "application/epub+zip")},
            data={"from_formats": fmt, "to_formats": "md"}, timeout=(15, 1800))
    response.raise_for_status()
    payload = response.json()
    document = payload.get("document", {})
    markdown = document.get("md_content") or payload.get("md_content")
    if not markdown:
        raise RuntimeError("Docling returned no Markdown content")
    return markdown


def defuddle_extract(url, job_folder):
    parsed = urlparse(url)
    if parsed.scheme not in {"http", "https"} or not parsed.netloc:
        raise RuntimeError("Enter a valid http or https URL")
    response = requests.post(f"{DEFUDDLE_URL}/extract", json={"url": url}, timeout=(15, 180))
    response.raise_for_status()
    result = response.json()
    filename = result.get("filename")
    source_path = GENERATIONS_DIR / filename if filename else None
    if source_path and source_path.is_file():
        markdown = source_path.read_text(encoding="utf-8", errors="replace")
    elif result.get("download_url"):
        download = requests.get(result["download_url"], timeout=(15, 120))
        download.raise_for_status()
        markdown = download.text
    else:
        raise RuntimeError("Defuddle returned no readable Markdown")
    (job_folder / "source.md").write_text(markdown, encoding="utf-8")
    return markdown


def wait_generation(generation_id):
    with requests.get(f"{VOICEBOX_URL}/generate/{generation_id}/status", stream=True,
                      headers={"Accept": "text/event-stream"}, timeout=(15, 1800)) as response:
        response.raise_for_status()
        for line in response.iter_lines(decode_unicode=True):
            if not line or not line.startswith("data:"):
                continue
            status = json.loads(line[5:].strip())
            state = status.get("status")
            if state == "completed":
                return
            if state in {"failed", "not_found"}:
                raise RuntimeError(status.get("error") or f"Voicebox generation {state}")
    raise RuntimeError("Voicebox status stream ended before completion")


def generate_chapter(text, profile_id, language, timeout_at):
    response = requests.post(f"{VOICEBOX_URL}/generate", json={
        "profile_id": profile_id, "text": text, "language": language,
        "max_chunk_chars": 3000,
    }, timeout=(15, 120))
    response.raise_for_status()
    generation_id = response.json().get("id")
    if not generation_id:
        raise RuntimeError("Voicebox did not return a generation ID")
    wait_generation(generation_id)
    wav = GENERATIONS_DIR / f"{generation_id}.wav"
    mp3 = GENERATIONS_DIR / f"{generation_id}.mp3"
    while time.monotonic() < timeout_at:
        if mp3.is_file() and mp3.stat().st_size > 0:
            return mp3
        time.sleep(3)
    if not wav.exists():
        raise RuntimeError(f"Voicebox completed but its WAV is missing: {wav.name}")
    raise RuntimeError(f"MP3 conversion timed out for {wav.name}")


def unique_destination(title):
    target = OUTPUT_DIR / safe_name(title)
    if not target.exists():
        return target
    return OUTPUT_DIR / f"{safe_name(title)} ({datetime.now().strftime('%Y-%m-%d %H%M')})"


def process_job(job):
    job_id = job["id"]
    folder = JOB_DIR / job_id
    update_job(job_id, status="processing", step="extracting", progress=5, message="Extracting clean text")
    source = job["source"]
    input_path = Path(job["input_path"]) if job["input_path"] else None
    if source == "url":
        markdown = defuddle_extract(job["source_value"], folder)
        default_title = urlparse(job["source_value"]).path.rstrip("/").split("/")[-1] or urlparse(job["source_value"]).hostname
        if default_title:
            default_title = re.sub(r"[-_]+", " ", default_title)
    elif source == "file" and input_path:
        if input_path.suffix.lower() == ".txt":
            markdown = input_path.read_text(encoding="utf-8", errors="replace")
        elif input_path.suffix.lower() in {".pdf", ".epub"}:
            markdown = docling_extract(input_path)
        else:
            raise RuntimeError("Supported files are PDF, EPUB, MOBI, and TXT")
        default_title = input_path.stem
    else:
        markdown = job["source_value"]
        default_title = "Pasted text"

    chapters = split_chapters(markdown)
    if not chapters:
        raise RuntimeError("No readable text was extracted")
    title = safe_name(job["title"] or default_title)
    update_job(job_id, title=title, step="synthesizing", progress=10,
               message=f"Extracted {len(chapters)} audio track(s)")

    work_output = JOB_DIR / job_id / "audiobook"
    work_output.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + MP3_WAIT_SECONDS
    for index, (chapter_title, chapter_text) in enumerate(chapters, start=1):
        update_job(job_id, step="synthesizing", progress=10 + int((index - 1) / len(chapters) * 80),
                   message=f"Generating track {index} of {len(chapters)}: {chapter_title}")
        mp3 = generate_chapter(chapter_text, job["profile_id"], job["language"], deadline)
        chapter_name = safe_name(chapter_title, f"Track {index}")
        shutil.copy2(mp3, work_output / f"{index:03d} - {chapter_name}.mp3")

    (work_output / "metadata.json").write_text(json.dumps({
        "title": title, "source": source, "language": job["language"],
        "tracks": [{"number": index, "title": chapter[0]} for index, chapter in enumerate(chapters, 1)],
    }, ensure_ascii=False, indent=2), encoding="utf-8")
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    target = unique_destination(title)
    work_output.rename(target)
    update_job(job_id, status="completed", step="completed", progress=100,
               message=f"Audiobook saved to {target}", result_path=str(target))


def worker_loop():
    while True:
        with connect_db() as db:
            row = db.execute("SELECT * FROM jobs WHERE status='queued' ORDER BY created_at LIMIT 1").fetchone()
            if row:
                job = dict(row)
            else:
                job = None
        if not job:
            time.sleep(2)
            continue
        request_file = JOB_DIR / job["id"] / "request.json"
        if request_file.exists():
            job["source_value"] = json.loads(request_file.read_text(encoding="utf-8")).get("source_value", "")
        update_job(job["id"], status="processing", step="starting", message="Starting job")
        try:
            process_job(job)
        except Exception as error:
            update_job(job["id"], status="failed", step="failed", error=str(error), message="Job failed")


initialize_db()
app = FastAPI(title="Text to Audio Workflow", version="1.0.0")


@app.on_event("startup")
def start_worker():
    threading.Thread(target=worker_loop, daemon=True, name="audio-worker").start()


@app.get("/health")
def health():
    return {"status": "ok"}


@app.get("/", response_class=FileResponse)
def upload_page():
    return FileResponse("/app/index.html", media_type="text/html")


@app.get("/api/profiles")
def profiles():
    response = requests.get(f"{VOICEBOX_URL}/profiles", timeout=15)
    response.raise_for_status()
    return response.json()


@app.post("/api/jobs", status_code=202)
async def create_job(
    profile_id: str = Form(...), language: str = Form("en"), title: str = Form(""),
    url: str = Form(""), text: str = Form(""), file: UploadFile | None = File(None),
):
    inputs = int(bool(url.strip())) + int(bool(text.strip())) + int(file is not None)
    if inputs != 1:
        raise HTTPException(400, "Provide exactly one of a URL, text, or file")
    job_id = str(uuid.uuid4())
    job_folder = JOB_DIR / job_id
    job_folder.mkdir(parents=True)
    source, source_value, input_path = "", "", None
    if file is not None:
        suffix = Path(file.filename or "").suffix.lower()
        if suffix not in {".pdf", ".epub", ".txt"}:
            raise HTTPException(400, "Supported files are PDF, EPUB, and TXT")
        content = await file.read(MAX_UPLOAD_BYTES + 1)
        if len(content) > MAX_UPLOAD_BYTES:
            raise HTTPException(413, "Maximum upload size is 200 MB")
        input_path = job_folder / f"source{suffix}"
        input_path.write_bytes(content)
        source = "file"
    elif url.strip():
        source, source_value = "url", url.strip()
        if urlparse(source_value).scheme not in {"http", "https"}:
            raise HTTPException(400, "URL must start with http:// or https://")
    else:
        source, source_value = "text", text.strip()
        if len(source_value) > 5_000_000:
            raise HTTPException(413, "Pasted text is too large")

    timestamp = now()
    # Persist URL or pasted source before making the job visible to the worker.
    (job_folder / "request.json").write_text(json.dumps({"source_value": source_value}), encoding="utf-8")
    with connect_db() as db:
        db.execute("INSERT INTO jobs (id,title,source,status,step,progress,message,profile_id,language,input_path,created_at,updated_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                   (job_id, safe_name(title) if title.strip() else "", source, "queued", "queued", 0,
                    "Waiting for the worker", profile_id.strip(), language, str(input_path) if input_path else None,
                    timestamp, timestamp))
    return {"id": job_id, "status": "queued"}


@app.get("/api/jobs")
def list_jobs():
    with connect_db() as db:
        rows = db.execute("SELECT * FROM jobs ORDER BY created_at DESC LIMIT 50").fetchall()
    return [read_job(row) for row in rows]


@app.get("/api/jobs/{job_id}")
def get_job(job_id: str):
    with connect_db() as db:
        row = db.execute("SELECT * FROM jobs WHERE id=?", (job_id,)).fetchone()
    if not row:
        raise HTTPException(404, "Job not found")
    data = read_job(row)
    request_file = JOB_DIR / job_id / "request.json"
    if request_file.exists():
        data["source_value"] = json.loads(request_file.read_text(encoding="utf-8")).get("source_value", "")
    return data
