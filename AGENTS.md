# Repository Guidelines

## Project Structure & Module Organization
This repository manages home infrastructure with container configuration. Ansible and Terraform are legacy systems kept in the repository for historical reference only; they are no longer used.

### Legacy directories: `ansible/` and `terraform/`

- `ansible/` and `terraform/` contain legacy configuration retained for historical reference. During repository analysis or ordinary work, do not inspect, search, analyze, edit, or run commands against either directory. Only do so when the user explicitly asks for Ansible or Terraform.
- `docs/` holds implementation notes and runbooks. `.env.example` documents expected environment variables; encrypted secrets live in `fnox.toml`.

## Build, Test, and Development Commands
- `just deploy-remote jellyfin` deploys Jellyfin to ubuntu-01 through the container scripts.
- `just backup jellyfin` creates a retention-managed backup of the Jellyfin config volume.

## Coding Style & Naming Conventions
Use the existing style in each active toolchain.

- Do not apply Ansible or Terraform conventions unless the user explicitly asks to work with those legacy systems.
- Docker image references must use explicit version tags; never use mutable tags such as `latest`.

## Testing Guidelines
There is no dedicated automated test suite in this repo today. Validate active configuration changes with their tool-native checks before opening a PR.

- When editing Docker Compose assets, verify the matching service workflow still succeeds.

## Commit & Pull Request Guidelines
After every change, create a focused Git commit. Commit messages must use a Conventional Commits type prefix, such as `feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, or `test:`; for example, `feat: add ansible setup` or `fix: repair suwayomi deployment`. Keep commits focused and descriptive.

PRs for active configuration should include:

- a short summary of the service change,
- affected active paths or hosts,
- screenshots when UI files are modified.

## Security & Configuration Tips
Do not commit plaintext secrets. Add new variables to `.env.example` when needed, but store real values through `fnox.toml` and the existing `fnox` setup.
