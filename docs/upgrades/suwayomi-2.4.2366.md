# Suwayomi upgrade plan: v2.1.1867 to v2.4.2366

## Current state

- Running server: `v2.1.1867`
- Database: H2, version 50
- Current data directory: `/var/lib/suwayomi/suwayomi-files`
- Downloads directory: `/mnt/containers-data/manga-downloads`
- Target: `v2.4.2366`, the latest release listed on October 6, 2026

The Compose service is pinned to a versioned image tag. Keep using explicit tags instead of `stable` or `latest`.

## Before upgrading

1. Confirm Suwayomi is healthy and the library, a chapter, and a downloaded title work.
2. Record the extension repository URL: `https://raw.githubusercontent.com/keiyoushi/extensions/repo/index.min.json`.
3. Run `just backup suwayomi`.
4. Confirm the backup archive was created under `/mnt/containers-data/backups/suwayomi` before changing the image. Keep the backup until the upgrade is verified.

The configured backup covers the full server data directory, including the H2 database, settings, and installed extensions. The downloads directory is mounted separately and is not included in that backup.

## Staged upgrade

For each step, update `image` in `containers/suwayomi/docker-compose.yml`, commit the version change, and run `just deploy-remote suwayomi`. Check the startup logs before moving to the next version:

```bash
ssh ubuntu@192.168.1.131
cd /home/ubuntu/compose/suwayomi
docker compose logs --tail=200 suwayomi
```

Look for the `Listening on http://0.0.0.0:4567/` startup message and check for database migration errors or other `ERROR` entries. To follow the logs while the server starts, use `docker compose logs -f suwayomi`; press `Ctrl+C` to stop following without stopping the container.

1. `ghcr.io/suwayomi/suwayomi-server:v2.2.2100`
2. `ghcr.io/suwayomi/suwayomi-server:v2.3.2243`
3. `ghcr.io/suwayomi/suwayomi-server:v2.4.2366`

After each deployment, confirm the container is running, the library is present, and a chapter opens. After the final step, also verify chapter images and downloads.

The v2.3 release introduces the Mihon Extension Store system and warns that extension repositories may be lost during migration. Check that the Keiyoushi source is still configured after that step and re-add the recorded URL if needed. The v2.4 release notes include a fix for migrating `extensionRepos` to `extensionStores`.

The release notes do not state that intermediate versions are required. Staging the upgrades makes it easier to identify which release introduced a problem.

## Rollback

If a step fails, stop further upgrades and inspect the container logs. Since a release may migrate the database, rolling back the image alone may not work. Restore `/var/lib/suwayomi/suwayomi-files` from the pre-upgrade backup as well as pinning the image to the previous version. Leave `/mnt/containers-data/manga-downloads` in place.

## Release references

- [v2.2.2100 release notes](https://github.com/Suwayomi/Suwayomi-Server/releases/tag/v2.2.2100)
- [v2.3.2243 release notes](https://github.com/Suwayomi/Suwayomi-Server/releases/tag/v2.3.2243)
- [v2.4.2366 release notes](https://github.com/Suwayomi/Suwayomi-Server/releases/tag/v2.4.2366)
