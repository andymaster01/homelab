# Text to audio

This stack runs Voicebox, its WAV to MP3 converter, Docling Serve, a
Defuddle URL extractor, and an upload-to-audiobook worker on `gpuloads-01`.
Prepare the pinned Voicebox source once with
`bash ./containers/text-to-audio/prepare-source.sh`, then deploy with
`just deploy-remote text-to-audio`.

## Voicebox

The Voicebox API and web UI are at `http://192.168.1.32:17600`; OpenAPI docs
are at `/docs`. Voicebox writes WAV audio to `/mnt/media/podcast/manual` on the
shared media server (bahamut, `192.168.1.101`). The VM mounts the NFS export at
`/mnt/media`, then bind-mounts that output folder into the container at
`/app/data/generations`. The MP3 converter watches the same folder and creates
a matching `.mp3` file for each completed `.wav`.

Profiles, history, and model data remain under
`/srv/audiobook-factory/voicebox/data` on the VM. The converter runs as a
separate Compose service using the Voicebox image's bundled FFmpeg. The image
is built from pinned upstream commit
`8af7efe62fab8d33e2a5dfbedabaa45f68a5184f`.

## Extract PDF and EPUB files

Docling Serve runs on CPU at `http://192.168.1.32:17602`. Its API docs are at
`/docs`, and its conversion playground is at `/ui`. The pinned CPU image includes
the default extraction models and is several gigabytes in size.

Convert an EPUB to Markdown with:

```sh
curl -fsS -X POST http://192.168.1.32:17602/v1/convert/file \
  -H 'accept: application/json' \
  -F 'files=@book.epub;type=application/epub+zip' \
  -F 'from_formats=epub' \
  -F 'to_formats=md'
```

For a PDF, use the same endpoint with `from_formats=pdf` and a PDF filename.
The response contains extracted Markdown; chapter splitting and saving named
chapter files are not automated yet. The API has no authentication configured
and is available on the VM's LAN address only.

## Extract clean Markdown from a URL

Defuddle extracts the main article content and metadata into a Markdown file;
it does not use an LLM. The HTTP API listens on port `17601` and saves each
result in `/mnt/media/podcast/manual` on the shared media folder.

Check service health:

```sh
curl -fsS http://192.168.1.32:17601/health
```

Submit a URL:

```sh
curl -fsS -X POST http://192.168.1.32:17601/extract \
  -H 'Content-Type: application/json' \
  -d '{"url":"https://example.com/article"}'
```

The response includes `file_path`, `filename`, and a `download_url`. The
Markdown file contains Defuddle's title and source metadata followed by the
cleaned article. Download it through the API if needed:

```sh
curl -fLO http://192.168.1.32:17601/files/FILENAME.md
```

The API accepts HTTP and HTTPS URLs on standard ports, checks that the
submitted hostname resolves to public addresses, and limits each extraction to
90 seconds. Defuddle follows website redirects while fetching, so keep this
unauthenticated API on the trusted LAN and don't expose it publicly.

## Upload and create an audiobook

The workflow page is at `http://192.168.1.32:17603`. It accepts one PDF, EPUB,
or TXT file, a web page URL, or pasted text. Choose a Voicebox profile and
narration language, then submit the job. Jobs run sequentially so they do not
compete for Voicebox's CPU and memory. The page shows progress and failures.

PDF and EPUB files are converted to Markdown by Docling. URLs are cleaned by
Defuddle, which resolves and fetches URLs over IPv4. The worker splits Markdown at chapter headings, asks Voicebox for
each track, then waits for the WAV to MP3 sidecar to finish. Numbered MP3 tracks
and a small `metadata.json` are written to
`/mnt/media/podcast/podcasts/<book title>/` on the shared media mount.
Audiobookshelf mounts that directory read-only at `/podcasts`, so the output
becomes available in its podcast library after its next scan.

The worker API is also available at `/api/jobs` (multipart form fields:
`profile_id`, `language`, and exactly one of `file`, `url`, or `text`; optional
`title`). `GET /api/jobs` lists recent jobs and `GET /api/jobs/{id}` returns one
job. Voice profiles are proxied from Voicebox at `GET /api/profiles`.
`POST /api/jobs/{id}/cancel` cancels queued jobs immediately and requests
cancellation of an active Voicebox generation. During PDF or URL extraction,
the worker stops at the next boundary after the extractor responds.
`DELETE /api/jobs/{id}` removes a completed, failed, or cancelled job, its
podcast output folder, and generated WAV, MP3, and Defuddle files.
Each job card shows its ID and links to its saved event log. Logs are kept under
the persistent workflow state and remain available at `/api/jobs/{id}/logs`
after generated files or the job record are deleted.

## Shared media mount

The `mnt-media.mount` systemd unit keeps the NFS mount available across VM
restarts. Install it on the VM with:

```sh
sudo install -D -m 644 containers/text-to-audio/mnt-media.mount /etc/systemd/system/mnt-media.mount
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-media.mount
```
