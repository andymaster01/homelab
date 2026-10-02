# Karakeep

Docker setup based on the [official installation instructions](https://docs.karakeep.app/installation/docker/), with Karakeep 0.33.2, Chrome 151.0.7922.47-r1, and Meilisearch v1.41.0 pinned to explicit versions.

## Deploy remotely

```bash
just deploy-remote karakeep
```

The deployment targets ubuntu-02 (`192.168.1.131`). Open http://192.168.1.131:3000 and create your account. Only the app's port is published; Chrome and Meilisearch are accessible within the Compose network.

`config.json` declares the two required secrets, which the deployment script loads from `fnox.toml` and passes over SSH without saving them in the remote environment file. The encrypted secrets are generated when this service is added. To replace either secret, generate an independent random value for each:

```bash
openssl rand -base64 36 | fnox set KARAKEEP_NEXTAUTH_SECRET --provider age
openssl rand -base64 36 | fnox set KARAKEEP_MEILI_MASTER_KEY --provider age
```

Changing the authentication secret invalidates existing login sessions. If you change the host or port, update both `config.json` and `KARAKEEP_PUBLIC_URL` in `.env.remote` so the public URL matches the address used in your browser.

## Run locally

```bash
fnox exec -- docker compose --env-file containers/karakeep/.env.local -f containers/karakeep/docker-compose.yml up -d
```

Open http://localhost:3000. Set `PORT` and update `.env.local` together if you need a different port.

## Data and updates

The `karakeep_data` Docker volume stores the database and saved assets. The `karakeep_meilisearch` volume stores the search index. These volumes survive container replacement; `docker compose down -v` deletes them. Back up both volumes with the stack stopped for a consistent snapshot.

Update the pinned image versions and deploy again to upgrade. Follow Karakeep's [Meilisearch migration guidance](https://docs.karakeep.app/administration/troubleshooting/) before upgrading Meilisearch.

AI tagging is optional and requires an inference provider; this setup uses the standard bookmarking, search, and page capture features without configuring one.
