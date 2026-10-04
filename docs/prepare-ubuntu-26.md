# Prepare Ubuntu 26.04 for Docker

Run the dedicated setup recipe for `app-01`:

```bash
just prepare-ubuntu-26
```

The script installs `jq`, `zip`, and the prerequisites for Docker's official
Ubuntu APT repository. It installs Docker's signing key, configures the
repository using the Ubuntu 26.04 `resolute` suite and the host architecture,
then installs Docker Engine, the CLI, containerd, Buildx, and the Compose plugin.
It enables and starts Docker, adds `ubuntu` to the `docker` group, and verifies
the installed versions and daemon access.

The recipe targets `192.168.1.140`. The script takes an IP argument if it needs
to be run against another Ubuntu 26.04 host. Group membership changes apply to
new SSH sessions; reconnect after the script reports that `ubuntu` was added to
the group.

The installation follows Docker's [official Ubuntu instructions](https://docs.docker.com/engine/install/ubuntu/)
and [Linux post-install steps](https://docs.docker.com/engine/install/linux-postinstall/).
