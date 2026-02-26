# Backup

## What Happens If You Lose a Repo?

If **one remote** goes down:
- Your other remote still has a complete, independent repo
- Restore from that one

If **both remotes** go down simultaneously:
- You have no backup — this is why two remotes matter
- The source files on your server are still intact (original data)

If you lose **the source AND one remote** but still have the other:
- You can fully restore from the surviving repo

---

## Restore From Scratch (Worst Case)

Scenario: container gone, cache gone, but Hetzner repo is intact.

```bash
# On any machine with borg installed:
borg list ssh://user@your.hetzner.host/./photos
# → lists all snapshots by name/date

borg extract ssh://user@your.hetzner.host/./photos::2025-01-15 /restore/here
# → restores that snapshot, fully decrypted
```

That's it. No container, no config, no cache needed. Just borg + address + passphrase.

---

## Safe Checking Routine

Borgmatic has a built-in `check` system with configurable frequency per check type. Here's a sound tiered routine:

```yaml
checks:
  - name: repository     # verifies repo index + chunk integrity
    frequency: 1 week

  - name: archives       # verifies every archive's manifest
    frequency: 2 weeks

  - name: extract        # actually extracts a recent archive to /dev/null
    frequency: 1 month   # this is the real "can I restore?" test

  - name: data           # reads and verifies EVERY chunk in the repo
    frequency: 3 months  # slow but thorough — catches silent corruption
```

### What each check does

| Check | What it verifies | Speed | Catches |
|---|---|---|---|
| `repository` | index consistency, pack file checksums | fast (seconds) | index corruption, truncated files |
| `archives` | every archive manifest is valid | medium (minutes) | corrupted snapshots |
| `extract` | extracts a real archive to /dev/null | slow (depends on size) | **end-to-end restore works** |
| `data` | reads and decrypts every chunk | very slow | silent bitrot, storage errors |

The `extract` check is the most important one for peace of mind — it proves an actual restore would succeed, not just that the metadata looks healthy.

### Full suggested schedule

```
daily     → borgmatic create + prune     (new backup, trim old ones)
weekly    → repository check             (fast integrity scan)
monthly   → archives + extract check     (real restore test)
quarterly → data check                   (full bitrot scan)
```

### One more thing: export and back up your key

```bash
borg key export ssh://user@hetzner/./photos ~/borg-photos.key
```

Store this file + the passphrase in your password manager or print it. If you ever need to access the repo from a brand new machine and the `repokey` somehow got damaged, this is your last resort.

---

## The Full Safety Picture

```
Source files (server)
    │
    ├──► Hetzner repo (SSH)  ──► weekly check ──► monthly extract test
    │                                                    │
    └──► OneDrive repo (rclone) ─────────────────────────
                                                         │
                                              Grafana: last backup time,
                                              repo size, dedup ratio,
                                              check pass/fail
```

You have:
- **2 independent encrypted repos** on different services
- **Incremental runs** that only upload new data
- **Automated integrity checks** that verify restorability, not just existence
- **Zero dependency on the container** for disaster recovery — any machine + borg + passphrase = full restore
