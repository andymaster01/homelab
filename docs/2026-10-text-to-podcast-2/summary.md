# URL and Document to MP3 Workflow

## Objective

Create a self-hosted workflow where I can submit a web URL or an ebook/document and get an MP3 in a designated output folder. The intake should accept:

- Web page URLs
- EPUB
- MOBI
- PDF
- Plain text (`.txt` and, if straightforward, Markdown)

The workflow runs in the Proxmox home lab. For the first stage, use Defuddle to extract and clean website text. Keep generated files on the audiobook VM for now; Audiobookshelf delivery is out of scope until the basic workflow works.

## Existing environment

- Proxmox VE 9.1.1, node `bahamut`.
- GPU VM `gpuloads-01` (VM 211), Ubuntu 26.04.1, GTX 1060 6 GB passed through.
- Docker, NVIDIA Container Toolkit, and persistent `/srv/audiobook-factory` data disk are configured on the VM.
- Abogen v1.3.1 is deployed at port 8808 and has generated a short English Kokoro MP3 on the GPU.
- Abogen's documented web interface has job-status JSON endpoints, but no documented job-submission API. Treat direct use of its undocumented form routes as fragile.
- Existing deployment conventions are in `containers/abogen/` and `scripts/remote-deployment.sh`.

See the original deployment notes at [../2026-10-text-to-podcast/summary.md](../2026-10-text-to-podcast/summary.md).

## Initial direction: Defuddle for URLs

Defuddle provides a Node.js CLI and library, not an official standalone HTTP service. Its CLI accepts a URL and emits cleaned Markdown or JSON. Start with a small, pinned Defuddle container or intake adapter that:

1. Accepts one URL per submitted job.
2. Runs Defuddle locally to fetch and extract the article.
3. Saves the Markdown and extracted title/author/source metadata into the job workspace.
4. Marks extraction failures clearly (for example, empty content, access denied, or fetch failure).
5. Hands the resulting text to the conversion stage.

Use the official Defuddle CLI/library; do not depend on Defuddle's hosted API. The extractor is intended for article-style pages. JavaScript-rendered, login-gated, paywalled, and bot-protected pages may need another path or may fail.

References:

- [Defuddle repository and CLI](https://github.com/kepano/defuddle)
- [Defuddle CLI documentation](https://defuddle.md/docs)

## Target workflow

```text
User submits URL / EPUB / MOBI / PDF / TXT
                  |
                  v
            Intake and job queue
                  |
       +----------+-----------+
       |                      |
     URL                  Local file
       |                      |
  Defuddle -> Markdown    Format-specific extraction
       +----------+-----------+
                  |
         Clean text + metadata
                  |
          Local TTS converter
                  |
         MP3 in output folder
```

Keep the first implementation single-user and sequential, with one active TTS job at a time to fit the GTX 1060's 6 GB VRAM. Make the input, temporary, failed, and output paths configurable and persistent.

## Functional requirements

### Intake

- Provide one convenient submission path for URLs and files (web form preferred; a watched folder can be a fallback for large files).
- Accept `.epub`, `.mobi`, `.pdf`, `.txt`, and URLs.
- Wait for uploads to finish before processing; reject unsupported or empty input with a visible reason.
- Avoid processing the same submitted item twice, while allowing an explicit retry.

### Extraction and normalization

- For URLs, use Defuddle to produce clean Markdown and retain title, author, source URL, and detected language when available.
- For EPUB/MOBI/PDF, extract readable text and preserve chapter order where practical. Scanned PDFs/OCR support is a later decision.
- For plain text/Markdown, preserve the supplied content and useful headings.
- Keep the extracted source and logs with each job for troubleshooting and retry.

### Audio generation

- Generate MP3 output into a configurable persistent folder on `gpuloads-01`.
- Use a local TTS engine; no mandatory cloud service.
- Support English, Spanish, and French as the initial languages, with explicit language/voice overrides if automatic detection is uncertain.
- Run one conversion at a time initially.
- Name output folders/files from the extracted title or uploaded filename and keep basic source metadata.
- Preserve failure state and incomplete work rather than silently dropping jobs.

## Converter decision

Not yet selected. Abogen is already deployed and GPU-verified but lacks a documented submission API. Libratory has a documented JSON/MCP interface and ebook processing, but its published Docker image uses CPU-only PyTorch; GPU use would need separate validation or a custom image. Compare them against the required input types, unattended job submission, MP3 output, language support, GPU behavior, and maintenance burden before implementing the conversion stage.

Do not assume an undocumented endpoint or current upstream feature. Verify the exact pinned release before integrating it.

## Phased plan

### Phase 1 — Defuddle URL intake proof of concept

1. Confirm the CLI's exact invocation/output and pin a Defuddle package/image version.
2. Create a minimal containerized URL intake adapter that accepts a URL and writes Markdown plus metadata to a persistent job directory.
3. Exercise representative static article URLs and record limitations for JavaScript-heavy or restricted sites.
4. Define the handoff contract for the conversion service (source text/Markdown, metadata, job ID, status, and failure details).

**Exit condition:** a submitted URL reliably produces a cleaned Markdown job artifact locally, with useful metadata and an inspectable failure when extraction fails.

### Phase 2 — Select and prove the conversion engine

1. Verify Abogen's pinned build behavior for programmatic job creation, or test Libratory's documented API/MCP with a local file.
2. Compare PDF, EPUB, MOBI, and text input handling; MP3 output; English/Spanish/French voices; long-job behavior; GPU vs CPU time; and restart/retry behavior.
3. Choose the simplest engine that supports a stable unattended handoff. If a CLI/API is missing, prefer a small supported adapter or evaluate another converter over relying on brittle UI internals.
4. Complete short sample conversions for each supported language and each practical input type.

**Exit condition:** a job can be submitted without interactive UI steps and produces a valid MP3 in the configured output folder.

### Phase 3 — Unified intake and job management

1. Add file upload and/or watched-folder intake for EPUB, MOBI, PDF, and TXT.
2. Connect URL extraction and file extraction to the same sequential conversion queue.
3. Implement duplicate detection, persistent job states, logs, failure/retry handling, and cleanup of temporary files.
4. Document the user workflow, configuration, backup needs, and deployment/recovery steps.

**Exit condition:** each requested input type can be submitted unattended and ends in either a completed MP3 or an actionable failed job.

### Later scope

- Audiobookshelf integration and automatic library scanning.
- Scanned PDF OCR and complex layout cleanup.
- Authentication/access control beyond the trusted LAN.
- More advanced metadata, cover art, chapter MP3s, or M4B packaging.
- Static DHCP reservation for the GPU VM if integrations depend on its address.

## Current status

- Planning stage. No implementation changes made yet.
- Defuddle is the starting point for URL extraction; the TTS converter and intake UI remain open decisions.

## Working rules

- Keep all processing local unless a specific optional service is explicitly chosen.
- Pin image/package versions; avoid mutable `latest` Docker tags in committed deployment configuration.
- Use active repository conventions and leave legacy `ansible/` and `terraform/` untouched.
- Before deployment, verify the relevant Proxmox/GPU compatibility for the actual pinned software stack.
