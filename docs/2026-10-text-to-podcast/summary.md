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

GPU container access has been verified at two levels. `nvidia/cuda:13.0.1-base-ubuntu24.04` can see the GTX 1060 and its 6144 MiB VRAM. A CUDA tensor computation also succeeded in `pytorch/pytorch:2.12.0-cuda12.6-cudnn9-runtime` (`2.12.0+cu126`, CUDA available, device `GeForce GTX 1060 6GB`). The Proxmox guest agent is active and reports the VM network interfaces.

The 40 GiB system disk is reserved for Ubuntu and container runtime files. A separate 100 GiB virtual disk on Proxmox `zfs-data` is attached, formatted ext4 with label `audiobook-data`, and mounted at `/srv/audiobook-factory`. The last guest check showed about 93 GiB available there. It contains `models`, `incoming`, `work`, and `output` directories owned by `ubuntu`. The guest and Proxmox host were unreachable from this workstation at the latest check, so current power/network status and free space should be rechecked when connectivity returns.

The GTX 1060 is passed through from Proxmox to the VM and exposed to Docker containers through NVIDIA Container Toolkit.

Only one VM will own the GPU through standard PCIe passthrough, but multiple Docker containers within that VM can share it.

## 3. Converter assessment and initial choice

The first implementation should evaluate **Abogen Web UI v1.3.1** as the conversion engine. The release documentation covers text, EPUB, and PDF inputs; a sequential background job queue; MP3 and M4B output; and Audiobookshelf integration. Its web interface is actively developed, so run a short end-to-end conversion and confirm persistence and ABS behavior before treating it as the production workflow. The pinned release Compose file builds from source and defaults to the PyTorch CUDA 12.6 package index, which matches the GTX 1060 compatibility test. Override its mutable `abogen:latest` image name with a project-specific explicit version tag in our deployment registration.

| Candidate | Fit for this project | Decision |
|---|---|---|
| Abogen Web UI | Text/EPUB/PDF input; sequential jobs; MP3/M4B; Kokoro voices; Audiobookshelf integration. Its upstream v1.3.1 Compose builds locally with CUDA 12.6 by default. | **Preferred first deployment candidate.** Pin source to v1.3.1 and use an explicit local image tag. Validate a real short synthesis on the GTX 1060, then verify output and ABS integration. |
| Ebook2Audiobook | Headless Docker conversion; text/EPUB/PDF input; multilingual engines; MP3 output; GPU option. It does not provide a watched-folder queue or podcast feed by itself. The current published GPU image uses CUDA 13, which is unsuitable for the Pascal GTX 1060. | Keep as an alternative only if a pinned custom build using a Pascal-compatible PyTorch/CUDA stack proves viable. |
| Libratory | Strong PDF/EPUB library, API/MCP and chapter workflow; local Kokoro supports English, French, and Spanish. Its published headless Docker image uses CPU-only PyTorch, and its normal audiobook output is M4B, so GPU use in this VM would need further integration. | Keep as an option if PDF cleanup, OCR, or book-library management becomes the main need. |
| EPUB to Audiobook | Closest built-in article-to-podcast workflow: queue, article RSS, MP3 chapters, and Audiobookshelf sync. Its documented default narration path is local CPU; GPU-specific engines are opt-in, and the documented voice coverage does not establish the required English, Spanish, and French local GPU workflow. | Revisit if article URL ingestion and a podcast RSS feed become top priorities. |

### GTX 1060 software compatibility

The GTX 1060 is Pascal compute capability 6.1. The CUDA 13 container test proves device visibility only. The PyTorch 2.12 CUDA 12.6 test successfully executed a CUDA tensor computation on the card, establishing that this compatible framework build can run GPU kernels. Abogen v1.3.1's GPU Compose defaults to the CUDA 12.6 PyTorch wheel index. Pin the PyTorch version instead of accepting the upstream empty/default value, and pin the source checkout and built image tag. Do not use CUDA 12.8 or CUDA 13 builds for this card without a specific compatibility test.

### Persistent storage plan

Keep the 40 GiB boot disk for Ubuntu and container runtime files. The separate **100 GiB virtual data disk on Proxmox `zfs-data`** is created and mounted at `/srv/audiobook-factory`; last verified free space was about 93 GiB. The mount has `models`, `incoming`, `work`, and `output` directories. At the Proxmox storage inspection, `zfs-data` had about 1.2 TiB free and `local-lvm` had about 250 GiB free. Bind the distinct data directories into the Compose stack, and add persistent settings/cache paths as needed by the application.

The VM is intended to be managed as a Docker Compose stack through the existing home-infrastructure workflow. Abogen's upstream Compose builds its image from the checked-out source and labels the result `abogen:latest`; the deployment should pin the source release and override that label with an explicit local version tag. Keep model, voice, upload, settings, temporary, and output data on the separate data disk.

## 4. Target Architecture

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

## 5. Candidate Projects

### Primary candidate: Abogen Web UI

Repository and pinned release: https://github.com/denizsafak/abogen/tree/v1.3.1

Reasons:

- Accepts text, EPUB, and PDF inputs, with queue mode and sequential background jobs.
- Produces MP3 and M4B (with chapters), among other formats.
- The Web UI documents Audiobookshelf integration.
- Release v1.3.1 includes a GPU-enabled Compose stack whose base is CUDA 12.6.
- Kokoro offers voices across English, Spanish, and French; verify the chosen voices during an end-to-end sample.

Deployment detail to resolve: the upstream Dockerfile's `TORCH_VERSION` build argument applies one version string to `torch`, `torchvision`, and `torchaudio`, although those packages use different version numbers. Build a small project-owned Dockerfile/override that pins a compatible CUDA 12.6 package set individually (starting from the tested PyTorch 2.12.0+cu126, torchvision 0.27.0+cu126, and torchaudio 2.12.0+cu126) and gives the image an explicit tag. Check Abogen's dependency compatibility during the first build and synthesis; do not rely on upstream's blank argument, which installs whichever packages are current at build time.

### Alternative: Ebook2Audiobook

Repository: https://github.com/DrewThomasson/ebook2audiobook

It offers headless Docker conversion, multilingual engines, and MP3 output. Recent upstream GPU images use CUDA 13, which does not support the GTX 1060's Pascal architecture. Reconsider only if an explicitly pinned CUDA 12.6 build is straightforward to maintain.

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

**Important:** Do not assume any project's current features, image tags, GPU support, or APIs. Verify them against its pinned release documentation before implementing.

## 6. Functional Requirements

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

## 7. Proposed Directory Structure

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

## 8. Infrastructure Implementation

### Phase 1: Proxmox GPU passthrough

1. Use `bahamut` as the target Proxmox node; confirm the motherboard/firmware VT-d setting is enabled.
2. Enable or verify Intel VT-d/IOMMU in firmware and Proxmox, then reboot the host during a maintenance window if required.
3. Confirm the GPU and HDMI audio function are in a suitable IOMMU group and bind them for VFIO passthrough.
4. Create the Linux VM with Q35 and OVMF/UEFI, then assign both GPU functions over PCIe.
5. Verify the GPU from inside the guest before installing Docker and NVIDIA Container Toolkit.

Host inspection on 2026-10-16 found an EVGA NVIDIA GTX 1060 6 GB, not the previously assumed GTX 1070 8 GB. The user enabled Intel VT-d in firmware; IOMMU is active on Proxmox, and the GPU/audio pair is assigned to the VM through VFIO. The passthrough guest driver and GPU compute in a CUDA 12.6 container have been verified.
