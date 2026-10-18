# PDF and EPUB to MP3

## Goal

Submit a PDF or EPUB and automatically get an MP3 in a chosen folder. Keep processing and files in the home lab. Audiobookshelf integration can come later. URL intake is a later addition.

## Starting point

Use the **Docling Docker container** to extract Markdown or structured JSON from PDFs and EPUBs. Docling supports both formats and has an HTTP API. Its output can then be split into chapter files by a small workflow step. Verify chapter boundaries on real samples; PDF headings and bookmarks vary.

- [Docling supported formats](https://github.com/docling-project/docling/blob/main/docs/usage/supported_formats.md)
- [Docling Serve API](https://github.com/docling-project/docling-serve/blob/main/docs/usage.md)
- [Docling Docker deployment](https://github.com/docling-project/docling.rs/blob/master/docs/DEPLOYMENT.md)

## Intended workflow

```text
PDF / EPUB → Docling extraction → split into chapters → local TTS → MP3 in output folder
```

The initial intake accepts PDFs and EPUBs. Process one conversion at a time and keep failed jobs visible for retry. Add URLs through Defuddle after this path works.

## Decisions to make after the Defuddle proof of concept

1. Which converter can accept extracted chapters automatically and generate MP3?
2. Can it use the GTX 1060, or is CPU conversion acceptable?
3. What is the simplest way to submit PDFs and EPUBs: a small web form, watched folder, or both?

Abogen is already deployed and GPU-verified, but has no documented job-submission API. Libratory has a documented API and Docker deployment, but its published image uses CPU-only PyTorch. Verify current pinned versions before choosing either.

## Existing setup

The audiobook VM is Proxmox VM 211 `gpuloads-01`, with Ubuntu, a passed-through GTX 1060 6 GB, Docker, and persistent storage at `/srv/audiobook-factory`. Abogen v1.3.1 is deployed there and has generated a test MP3.

See the [original setup notes](../2026-10-text-to-podcast/summary.md) for deployment details.

## Status

Planning. Docling is the starting point for PDF/EPUB extraction. Chapter splitting, TTS converter, and intake interface still need to be proven or selected. URL intake with Defuddle is deferred until later.
