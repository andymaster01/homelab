# Voicebox

Voicebox runs on `gpuloads-01` as a CPU-only API trial. Prepare the pinned build
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
`GET /history/{id}/export-audio`. Voicebox writes WAV audio; convert it to MP3
as a separate step if needed. Generated audio and profiles persist under
`/srv/audiobook-factory/voicebox/data` on the host.

The image is built from pinned upstream commit
`8af7efe62fab8d33e2a5dfbedabaa45f68a5184f`.
