# Project: Self-Hosted AI Audiobook Factory

## 1. Objective

Build a fully self-hosted, automated audiobook generation system running in my Proxmox home lab.

The system must convert existing ebooks (EPUB and PDF) into high-quality audiobooks using locally hosted AI text-to-speech models.

The primary languages are:

- English
- Spanish
- French

The entire process should run unattended. I want to drop an ebook into a directory and have the system automatically generate an audiobook and make it available in my existing Audiobookshelf installation.

**Primary goal:** Minimize custom development by integrating existing open-source projects and using official, prebuilt Docker images wherever possible.

## 2. Existing Infrastructure

### Proxmox host

- Proxmox VE 9.1.1 node `bahamut` (Lenovo ThinkStation P510, Intel Xeon E5-1650 v4).
- EVGA NVIDIA GeForce GTX 1060 (GP106, device ID `10de:1c03`) with 6 GB VRAM, installed in Proxmox node `bahamut` at PCI address `0000:01:00.0`.
- The GPU's HDMI audio function is at `0000:01:00.1` (device ID `10de:10f1`). Both functions are assigned to `gpuloads-01` and bound to `vfio-pci` on the host.
- Intel VT-d is enabled in firmware. IOMMU is active on Proxmox; the GPU and its audio function share IOMMU group 42.
- Applications run in Docker containers inside Linux virtual machines.
- Docker is not running directly on the Proxmox host.
- Komodo is available for Docker deployment and monitoring.
- Audiobookshelf is already deployed and operational.

### GPU VM: `gpuloads-01`

The dedicated VM has been created on `bahamut` (Proxmox VM ID 211) and is running Ubuntu 26.04.1 LTS. PCIe passthrough of both GPU functions is configured.

| Resource | Current allocation |
|---|---|
| CPU | 4 vCPU |
| RAM | 16 GiB |
| GPU | EVGA NVIDIA GTX 1060 6 GB (`01:00.0`) |
| GPU audio | NVIDIA GP106 audio (`01:00.1`) |
| System disk | 40 GiB on `local-lvm` |
| Guest IP | `192.168.1.32` (DHCP) |
| Container engine | Docker Engine 29.1.3 (`docker.io` Ubuntu package) |
| GPU container runtime | NVIDIA Container Toolkit 1.20.1 |

The guest NVIDIA driver is 580.178.04. Driver 595 was tested first, but its kernel module reported that the GTX 1060 is supported through the 580.xx legacy branch and ignored the card; it was replaced with 580.

GPU container access is verified with `nvidia/cuda:13.0.1-base-ubuntu24.04` running `nvidia-smi`, which reported the GTX 1060 and 6144 MiB VRAM. The Proxmox guest agent is active and reports the VM network interfaces.

The VM currently has about 33 GiB free on its 38 GiB root filesystem. Plan persistent model, incoming ebook, and completed audiobook storage before choosing a production converter image; model downloads can exceed the available system disk.

The GTX 1060 is passed through from Proxmox to the VM and exposed to Docker containers through NVIDIA Container Toolkit.

Only one VM will own the GPU through standard PCIe passthrough, but multiple Docker containers within that VM can share it.

## 3. Target Architecture

```text
                  PROXMOX HOST
              NVIDIA GTX 1060 (6GB)
                        |
                  PCIe Passthrough
                        |
                        v
                LINUX DOCKER VM
+--------------------------------------------------+
|                                                  |
|  /audiobook-factory/incoming                      |
|             |                                    |
|             v                                    |
|      File Watcher / Scheduler                    |
|             |                                    |
|             v                                    |
|       Conversion Job Queue                       |
|             |                                    |
|             v                                    |
|        Ebook Processing                          |
|       - EPUB/PDF extraction                      |
|       - OCR when necessary                       |
|       - Text cleanup                             |
|       - Chapter detection                        |
|       - Language detection                       |
|             |                                    |
|             v                                    |
|        Local AI TTS Engine                       |
|       - NVIDIA CUDA acceleration                 |
|       - English / Spanish / French               |
|       - XTTSv2 or other compatible model         |
|             |                                    |
|             v                                    |
|        Audiobook Packaging                       |
|       - Chapter organization                     |
|       - Audio normalization                      |
|       - Metadata and cover                       |
|       - M4B preferred / MP3 optional             |
|             |                                    |
|             v                                    |
|       Completed Audiobook Folder                 |
|                                                  |
+--------------------------------------------------+
                        |
                        v
                 AUDIOBOOKSHELF
             Existing self-hosted app
```

All processing must happen locally. No mandatory cloud APIs, subscriptions, or external TTS services.

## 4. Candidate Projects

Evaluate the following open-source projects before deciding on the implementation.

### Primary candidate: Ebook2Audiobook

Repository: https://github.com/pegakmop/ebook2audiobookXTTS

Reasons:

- Ebook-to-audiobook conversion.
- Headless execution.
- Docker deployment.
- GPU acceleration.
- Multilingual text-to-speech.
- Chaptered audiobook output.
- Support for XTTSv2 and other engines.

This is the preferred starting point for automating well-formatted EPUB conversion.

Verify which official/prebuilt GPU-enabled image tags support the NVIDIA GTX 1060.

### Alternative: Libratory

Repository: https://github.com/subev/libratory

Reasons:

- PDF and EPUB ingestion.
- OCR capabilities.
- Text cleanup.
- Chapter detection.
- API integration.
- Docker Compose deployment.

Potentially better for older books containing scanned pages, footnotes, and complex PDF formatting.

### Alternative: EPUB to Audiobook

Repository: https://github.com/davedavedavenm/epub-to-audiobook

Reasons:

- Conversion queues.
- Local TTS support.
- Audiobookshelf integration.
- Docker deployment.

Evaluate whether it provides a simpler, more complete unattended workflow.

### Additional candidates

- https://voicebox.sh/
- https://github.com/vatavale/folivox

These are secondary options because prebuilt official Docker images or fully unattended deployment have not been confirmed.

**Important:** Do not assume any project's current features, image tags, GPU support, or APIs. Verify them against its latest documentation before implementing.

## 5. Functional Requirements

### FR-01: Automatic file discovery

Monitor a configurable input directory.

Accept:

- `.epub`
- `.pdf`

When a new file appears:

1. Wait until copying has completed.
2. Validate the file.
3. Avoid duplicate processing.
4. Create a conversion job.
5. Move or mark the file as processing.

Use a small existing file-watcher utility, a scheduled job, or a converter's native queue where available.

Avoid developing a custom service unless necessary.

### FR-02: Ebook processing

Extract text and preserve the logical structure of the book.

Requirements:

- Chapter identification.
- Remove unnecessary headers, footers, and page numbers.
- Handle table-of-contents entries.
- Handle special characters and accents.
- OCR scanned PDFs when necessary.
- Preserve appropriate chapter ordering.

Prioritize EPUB extraction initially, then implement robust PDF support.

### FR-03: Multilingual TTS

Support:

- English
- Spanish
- French

Language should be automatically detected if reliable, with an option to explicitly specify a language.

Evaluate XTTSv2 first, with Kokoro or another compatible model as an alternative.

Prioritize:

1. Natural-sounding narration.
2. Accurate multilingual pronunciation.
3. Stability during long conversions.
4. GPU compatibility.
5. Reasonable generation speed.

Voice cloning is optional, not mandatory.

### FR-04: Audiobook output

Preferred format: M4B.

Requirements:

- One audiobook file per book when supported.
- Embedded chapter markers.
- Book title and author metadata where available.
- Cover artwork where available.
- Correct playback order.
- Compatible with Audiobookshelf.

MP3 chapter files are an acceptable alternative and should be configurable if the converter supports them.

### FR-05: Automated Audiobookshelf delivery

Completed audiobooks must be placed in a directory accessible to the existing Audiobookshelf instance.

Audiobookshelf should discover the new audiobook using its normal library scanning mechanism.

No custom Audiobookshelf integration should be developed unless necessary.

### FR-06: Error handling

Failed conversions must not silently disappear.

Requirements:

- Persistent logs.
- Failure state.
- Failed-file directory.
- Ability to retry.
- No duplicate finished audiobooks.
- Cleanup of incomplete outputs.

### FR-07: Resource management

The initial configuration should run one conversion job at a time.

Avoid concurrent GPU-heavy jobs that could exceed the GTX 1060's 6 GB VRAM.

Persist downloaded AI models to avoid repeatedly downloading them.

Ensure conversion jobs can recover safely from container restarts, either through native checkpointing or by retrying.

## 6. Proposed Directory Structure

```text
/audiobook-factory/
├── incoming/
│   ├── book1.epub
│   └── book2.pdf
│
├── processing/
├── completed/
├── failed/
├── logs/
├── models/
├── config/
└── temp/

/media/audiobooks/
├── Author Name/
│   └── Book Title/
│       └── Book Title.m4b
└── Another Author/
    └── Another Book/
        └── Another Book.m4b
```

Use configurable paths and persistent Docker volumes or bind mounts.

Avoid hardcoding machine-specific paths in application logic.

## 7. Infrastructure Implementation

### Phase 1: Proxmox GPU passthrough

1. Use `bahamut` as the target Proxmox node; confirm the motherboard/firmware VT-d setting is enabled.
2. Enable or verify Intel VT-d/IOMMU in firmware and Proxmox, then reboot the host during a maintenance window if required.
3. Confirm the GPU and HDMI audio function are in a suitable IOMMU group and bind them for VFIO passthrough.
4. Create the Linux VM with Q35 and OVMF/UEFI, then assign both GPU functions over PCIe.
5. Verify the GPU from inside the guest before installing Docker and NVIDIA Container Toolkit.

Host inspection on 2026-10-16 found an EVGA NVIDIA GTX 1060 6 GB, not the previously assumed GTX 1070 8 GB. VT-d is not currently active: the running kernel exposes no DMAR table or IOMMU groups, and its boot log contains no VT-d initialization message. The firmware setting has not yet been inspected directly.
