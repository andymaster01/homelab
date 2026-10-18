# URL and Document to MP3

## Goal

Submit a URL or a PDF, EPUB, MOBI, or text file and automatically get an MP3 in a chosen folder. Keep processing and files in the home lab. Audiobookshelf integration can come later.

## Starting point

Start with **Defuddle** for URLs. It has a CLI that accepts a URL and returns cleaned Markdown. Run it locally in a small container; do not use the hosted API. Defuddle works best with regular article pages, and may not extract content from paywalled or JavaScript-heavy sites.

- [Defuddle CLI](https://github.com/kepano/defuddle)
- [Defuddle documentation](https://defuddle.md/docs)

The first milestone is simple: submit a URL and save the extracted Markdown and page title in a persistent job folder.

## Intended workflow

```text
URL or file → extract text → local TTS → MP3 in output folder
```

The eventual intake should accept URLs, PDF, EPUB, MOBI, and TXT. Process one conversion at a time and keep failed jobs visible for retry.

## Decisions to make after the Defuddle proof of concept

1. Which converter can accept jobs automatically, handle the required file types, and generate MP3?
2. Can it use the GTX 1060, or is CPU conversion acceptable?
3. What is the simplest way to submit items: a small web form, watched folder, or both?

Abogen is already deployed and GPU-verified, but has no documented job-submission API. Libratory has a documented API and Docker deployment, but its published image uses CPU-only PyTorch. Verify current pinned versions before choosing either.

## Existing setup

The audiobook VM is Proxmox VM 211 `gpuloads-01`, with Ubuntu, a passed-through GTX 1060 6 GB, Docker, and persistent storage at `/srv/audiobook-factory`. Abogen v1.3.1 is deployed there and has generated a test MP3.

See the [original setup notes](../2026-10-text-to-podcast/summary.md) for deployment details.

## Status

Planning. Defuddle URL extraction is the first step; converter and intake interface are undecided.
