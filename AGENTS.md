# Repository Guidelines

## Project Structure & Module Organization
This repository manages home infrastructure with Ansible, Terraform, and `mise`.

- `ansible/` contains inventory, host vars, playbooks, and reusable roles.
- `ansible/playbooks/*.yml` targets specific hosts such as `ubuntu-01.yml`, `ubuntu-02.yml`, `db-pg-01.yml`, and `bahamut.yml`.
- `ansible/roles/<role>/` follows the standard Ansible layout: `tasks/`, `defaults/`, `templates/`, optional `docker/`, plus a role-local `mise-tasks.toml`.
- `terraform/proxmox/images` and `terraform/proxmox/vms` manage Proxmox images and VM provisioning.
- `docs/` holds implementation notes and runbooks. `.env.example` documents expected environment variables; encrypted secrets live in `fnox.toml`.

## Build, Test, and Development Commands
Prefer `mise` task wrappers over ad hoc commands.

- `mise tasks` lists the supported workflows.
- `mise run tf:images:init` and `mise run tf:vms:init` initialize Terraform modules.
- `mise run tf:images:plan` or `mise run tf:vms:plan` previews infrastructure changes.
- `mise run jellyfin:up` or `mise run deploy:fileserver` applies Ansible-managed services.
- `cd ansible && ansible-playbook playbooks/ubuntu-01.yml --tags jellyfin --check` performs a dry run for role changes.

## Coding Style & Naming Conventions
Use the existing style in each toolchain.

- YAML uses 2-space indentation and lowercase snake_case keys.
- Ansible role names, tags, variables, and task files use snake_case, for example `filebrowser_quantum` and `jellyfin_dir`.
- Terraform files stay split by concern (`main.tf`, `variables.tf`, `outputs.tf`) and should be formatted with `terraform fmt`.
- Keep host-specific logic in playbooks or `host_vars`, not inside shared role defaults.

## Testing Guidelines
There is no dedicated automated test suite in this repo today. Validate changes with tool-native checks before opening a PR.

- Run `terraform fmt` and `terraform validate` in the affected module.
- Use `terraform plan -var-file=../terraform.tfvars` to confirm intended changes.
- For Ansible, run the relevant playbook with `--check` and narrow scope with `--tags <role>`.
- When editing Docker compose assets under a role, verify the matching `mise run <role>:up` task still succeeds.

## Commit & Pull Request Guidelines
Recent commits use short, imperative, lowercase summaries such as `add ansible setup` or `suwayomi working`. Keep commits focused and descriptive.

PRs should include:

- a short summary of the infrastructure or service change,
- affected paths or hosts, for example `ansible/roles/manga` or `terraform/proxmox/vms`,
- plan or dry-run evidence for Terraform/Ansible changes,
- screenshots only when UI files such as `ansible/roles/homepage/docker/config/` are modified.

## Security & Configuration Tips
Do not commit plaintext secrets. Add new variables to `.env.example` when needed, but store real values through `fnox.toml` and the existing `mise`/`fnox` setup.
