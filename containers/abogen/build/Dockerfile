FROM nvidia/cuda:12.6.3-cudnn-runtime-ubuntu22.04@sha256:5f0d2d827f6436b3cb7468fd8acbdc8c1d41261614e579ae49afe6141da51133

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    VIRTUAL_ENV=/opt/venv \
    PATH=/opt/venv/bin:$PATH

ARG TORCH_INDEX_URL=https://download.pytorch.org/whl/cu126

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        python3 \
        python3-venv \
        python3-pip \
        ffmpeg \
        libsndfile1 \
        libgl1 \
        libglib2.0-0 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv "$VIRTUAL_ENV"

WORKDIR /app

COPY --from=abogen-source /pyproject.toml /README.md ./
COPY --from=abogen-source /abogen ./abogen

RUN pip install --upgrade pip \
    && pip install --no-cache-dir \
        torch==2.12.0+cu126 \
        torchvision==0.27.0+cu126 \
        --index-url "$TORCH_INDEX_URL" \
    && pip install --no-cache-dir . \
        https://github.com/explosion/spacy-models/releases/download/en_core_web_sm-3.8.0/en_core_web_sm-3.8.0-py3-none-any.whl

ENV ABOGEN_HOST=0.0.0.0 \
    ABOGEN_PORT=8808 \
    ABOGEN_UPLOAD_ROOT=/data/uploads \
    ABOGEN_OUTPUT_DIR=/data/outputs \
    ABOGEN_OUTPUT_ROOT=/data/outputs \
    ABOGEN_TEMP_DIR=/data/cache \
    ABOGEN_VOICE_CACHE_DIR=/models/voices \
    HF_HOME=/models/huggingface \
    HUGGINGFACE_HUB_CACHE=/models/huggingface/hub

EXPOSE 8808

RUN useradd -m -u 1000 abogen \
    && mkdir -p /data/uploads /data/outputs /data/cache /config /models \
    && chown -R abogen:abogen /data /config /models /app

USER abogen

CMD ["abogen-web"]
