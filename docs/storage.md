# Storage

## Architecture

```mermaid
flowchart TD
    subgraph bahamut["bahamut (192.168.1.101)"]
        subgraph zfs["ZFS pool: zfs-data"]
            media["zfs-data/media\n/mnt/media"]
            pv["zfs-data/photos-videos\n/mnt/photos-videos"]
            pvt["zfs-data/photos-videos-test\n/mnt/photos-videos-test"]
            cd["zfs-data/containers-data\n/mnt/containers-data"]
        end
        nfs["NFS server"]
        samba["Samba"]
        media & pv & pvt & cd --> nfs
        media & pv & pvt & cd --> samba
    end

    subgraph ubuntu01["ubuntu-01 (192.168.1.130)"]
        mnt_media["/mnt/media"]
        mnt_pvt["/mnt/photos-videos-test"]

        subgraph containers["Docker containers"]
            jellyfin["jellyfin\n:8096"]
            filebrowser["filebrowser-quantum\n:8010"]
            resticprofile["resticprofile"]
            homepage["homepage"]
        end

        mnt_media -->|"ro /media"| jellyfin
        mnt_media -->|"rw /media"| filebrowser
        mnt_pvt -->|"rw /photos-videos-test"| filebrowser
        mnt_pvt -->|"ro /mnt/source/pv"| resticprofile
    end

    nfs -->|NFS /mnt/media| mnt_media
    nfs -->|NFS /mnt/photos-videos-test| mnt_pvt
```



## ZFS Datasets (bahamut)

Pool: `zfs-data`

| Dataset | Mount point | Purpose |
|---|---|---|
| `zfs-data/media` | `/mnt/media` | Jellyfin media library (movies, TV shows, music) |
| `zfs-data/photos-videos` | `/mnt/photos-videos` | Primary photos and videos collection |
| `zfs-data/photos-videos-test` | `/mnt/photos-videos-test` | Test dataset for backup validation |
| `zfs-data/containers-data` | `/mnt/containers-data` | Persistent data for Docker containers |

All datasets are owned by uid/gid `1000` (ubuntu user).

Managed by: `ansible/roles/fileserver_zfs` with vars in `ansible/host_vars/bahamut.yml`.

---

## Sharing

### NFS (bahamut → LAN)

All datasets are exported via NFS to the whole LAN (`192.168.1.0/24`) with `rw,sync,all_squash` (mapped to uid/gid 1000).

| Export path | Accessible by |
|---|---|
| `/mnt/media` | any host on 192.168.1.0/24 |
| `/mnt/photos-videos` | any host on 192.168.1.0/24 |
| `/mnt/photos-videos-test` | any host on 192.168.1.0/24 |
| `/mnt/containers-data` | any host on 192.168.1.0/24 |

Managed by: `ansible/roles/fileserver_nfs`.

### Samba (bahamut → LAN)

All datasets are shared via Samba under the same names, authenticated by a single Samba user (`FILESERVER_SMB_USER`).

| Share name | Path |
|---|---|
| `media` | `/mnt/media` |
| `photos-videos` | `/mnt/photos-videos` |
| `photos-videos-test` | `/mnt/photos-videos-test` |
| `containers-data` | `/mnt/containers-data` |

Managed by: `ansible/roles/fileserver_samba`.

---

## Mounts on ubuntu-01 (192.168.1.130)

| Source (bahamut) | Mount point | Automated |
|---|---|---|
| `192.168.1.101:/mnt/photos-videos-test` | `/mnt/photos-videos-test` | `ansible/roles/nfs_client` |
| `192.168.1.101:/mnt/media` | `/mnt/media` | `ansible/roles/nfs_client` |

### Consumers on ubuntu-01

| Container | Dataset used | Mount in container | Mode |
|---|---|---|---|
| `resticprofile` | `photos-videos-test` | `/mnt/source/pv` | read-only |
| `jellyfin` | `media` | `/media` | read-only |
| `filebrowser-quantum` | `media` | `/media` | read-write |
| `filebrowser-quantum` | `photos-videos-test` | `/photos-videos-test` | read-write |
