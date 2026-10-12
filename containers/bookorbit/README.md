# BookOrbit

BookOrbit is deployed on ubuntu-01 (`192.168.1.130`) with its bundled PostgreSQL database. Its library is mounted read-write from `/mnt/media/books` at `/books`; application and database files live on the VM at `/var/lib/bookorbit`. Backups are stored on shared storage at `/mnt/containers-data/backups/bookorbit`.

## Deploy remotely

```bash
just deploy-remote bookorbit
```

Open [http://192.168.1.130:3000](http://192.168.1.130:3000) and create the administrator account using the setup bootstrap token. Create the first library with the container path `/books`.

The deployment loads its database password, JWT secret, and setup token from `fnox.toml` and passes them over SSH without saving them in `.env.remote`. To generate or replace the independent secrets:

```bash
openssl rand -hex 24 | fnox set POSTGRES_PASSWORD --provider age
openssl rand -hex 32 | fnox set JWT_SECRET --provider age
openssl rand -hex 16 | fnox set SETUP_BOOTSTRAP_TOKEN --provider age
```

Back up the persistent files with:

```bash
just backup bookorbit
```

To update BookOrbit, change the pinned image tag in `docker-compose.yml` to the desired release and deploy again.
