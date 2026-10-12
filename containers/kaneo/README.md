# Kaneo

Kaneo is deployed on app-01 (`192.168.1.140`) with its bundled PostgreSQL 16 database. PostgreSQL data is kept on the VM's local disk at `/var/lib/kaneo/postgres`; backups are stored on shared storage at `/mnt/containers-data/backups/kaneo`.

## Deploy remotely

```bash
just deploy-remote kaneo
```

Open [http://192.168.1.140:5173](http://192.168.1.140:5173) to create the first account.

The deployment loads its database password and authentication secret from `fnox.toml`, passing them over SSH without saving them in `.env.remote`. Generate independent secrets with:

```bash
openssl rand -hex 24 | fnox set KANEO_POSTGRES_PASSWORD --provider age
openssl rand -hex 32 | fnox set KANEO_AUTH_SECRET --provider age
```

Back up the database with:

```bash
just backup kaneo
```

To update Kaneo, change the pinned image tag in `docker-compose.yml` to the desired release and deploy again.
