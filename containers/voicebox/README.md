# Voicebox

Voicebox runs on `gpuloads-01` as a CPU-only service. Prepare the pinned build
source once with `bash ./containers/voicebox/prepare-source.sh`, then deploy with
`just deploy-remote voicebox`. Its API and web UI are available at
`http://192.168.1.32:17600`; OpenAPI docs are at `/docs`.

The service has no authentication configured. The port is bound to the server's
LAN address, so use it only on a trusted network and do not expose it through a
router or public reverse proxy.

## API smoke check

```sh
curl http://192.168.1.32:17600/health
curl http://192.168.1.32:17600/openapi.json
```

Create a preset Kokoro voice profile and generate speech through the API:

```sh
PROFILE_ID=$(curl -fsS -X POST http://192.168.1.32:17600/profiles \
  -H 'Content-Type: application/json' \
  -d '{"name":"API voice","language":"en","voice_type":"preset","preset_engine":"kokoro","preset_voice_id":"af_heart","default_engine":"kokoro"}' \
  | jq -r .id)

curl -fsS -X POST http://192.168.1.32:17600/generate \
  -H 'Content-Type: application/json' \
  -d "{\"profile_id\":\"$PROFILE_ID\",\"text\":\"Hello from Voicebox.\",\"language\":\"en\",\"engine\":\"kokoro\"}"
```

The `POST /generate` response includes a generation ID. Follow progress with
`GET /generate/{id}/status` and retrieve the result from
`GET /history/{id}/export-audio`. Voicebox writes WAV audio to
`/mnt/media/podcast/manual` on the shared media server (bahamut,
`192.168.1.101`). The VM mounts the NFS export at `/mnt/media`, then
bind-mounts that output folder into the container at `/app/data/generations`.
Profiles, history, and model data remain under
`/srv/audiobook-factory/voicebox/data` on the VM. Convert WAV audio to MP3 as a
separate step if needed.

The `mnt-media.mount` systemd unit in this directory keeps the NFS mount
available across VM restarts. Install it on the VM with:

```sh
sudo install -D -m 644 containers/voicebox/mnt-media.mount /etc/systemd/system/mnt-media.mount
sudo systemctl daemon-reload
sudo systemctl enable --now mnt-media.mount
```

The image is built from pinned upstream commit
`8af7efe62fab8d33e2a5dfbedabaa45f68a5184f`.
