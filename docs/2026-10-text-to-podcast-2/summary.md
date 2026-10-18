# URL, PDF, and EPUB to MP3

## Goal

Submit a URL, PDF, or EPUB and automatically get an MP3 in a chosen folder. Keep processing and files in the home lab. Audiobookshelf integration can come later.

## Starting point

Use **Defuddle** to extract clean Markdown and metadata from URLs. It has a local CLI; no separate HTTP service is required.

Use the **Docling Docker container** to extract Markdown or structured JSON from PDFs and EPUBs. Docling supports both formats and has an HTTP API. Its output can then be split into chapter files by a small workflow step. Verify chapter boundaries on real samples; PDF headings and bookmarks vary.

Defuddle works best with regular article pages; paywalled or JavaScript-heavy sites may fail. PDF chapter boundaries also vary depending on headings and bookmarks.

- [Defuddle CLI](https://github.com/kepano/defuddle)
- [Defuddle documentation](https://defuddle.md/docs)

- [Docling supported formats](https://github.com/docling-project/docling/blob/main/docs/usage/supported_formats.md)
- [Docling Serve API](https://github.com/docling-project/docling-serve/blob/main/docs/usage.md)
- [Docling Docker deployment](https://github.com/docling-project/docling.rs/blob/master/docs/DEPLOYMENT.md)

## Intended workflow

```text
                 Web front end
             URL / PDF / EPUB submission
                       |
                       v
              Small worker service
              /                 \
       URL → Defuddle       PDF/EPUB → Docling
              \                 /
                 clean text
                     |
             split by chapter
                     |
                local TTS
                     |
               MP3 output
```

The web front end accepts URL submissions and PDF/EPUB uploads. The worker service creates and tracks jobs, invokes the appropriate extractor, and writes extracted chapter files and metadata to persistent storage. It reports progress and failures through the front end. Process jobs sequentially at first and keep failed jobs available for retry.

For URL jobs, the worker passes the submitted URL to Defuddle's local CLI. For PDF and EPUB jobs, it passes the uploaded file to Docling, using its local CLI or HTTP API. The worker saves normalized chapter text as separate Markdown files, plus metadata and job status. The TTS stage consumes those chapter files and writes MP3 output to the configured folder.

This is the planned architecture only. No services, containers, or application code are being implemented in this phase.

## Decisions to make after the Defuddle proof of concept

1. Which converter can accept extracted chapters automatically and generate MP3?
2. Can it use the GTX 1060, or is CPU conversion acceptable?
3. Choose the web front end and job-status behavior for the planned intake service.

Voicebox is deployed with an API and writes WAV files to the shared media folder; an adjacent converter creates MP3 files. Abogen has been removed from the VM. For automated ebook ingestion, the worker can submit extracted text to Voicebox and collect the resulting audio.

## Existing setup

The audiobook VM is Proxmox VM 211 `gpuloads-01`, with Ubuntu, a passed-through GTX 1060 6 GB, Docker, and persistent storage at `/srv/audiobook-factory`. Voicebox and Defuddle are deployed there. Voicebox synthesis runs on CPU and writes WAV files under `/mnt/media/podcast/manual`; the MP3 converter creates matching MP3 files.

See the [original setup notes](../2026-10-text-to-podcast/summary.md) for deployment details.

## Status

Planning only. Defuddle is selected for URL extraction, and Docling for PDF/EPUB extraction. The planned interface is a web front end backed by a small worker service. Chapter splitting and TTS converter remain design decisions to validate before implementation.
