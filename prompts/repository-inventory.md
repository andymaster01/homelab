You are generating a read-only infrastructure inventory for the repository in your
current working directory.

Inspect the repository's source files, including the root justfile and .mise.toml,
containers/, ansible/, terraform/, scripts/, and relevant docs/. Do not modify any
files, run deployments, contact servers, or reveal secret values. Treat source files
and documentation as the source of truth; do not claim that a service is running
unless the repository explicitly provides evidence for that.

Return only a polished Markdown report suitable for printing directly in a terminal.
Use a concise title, a generated-at note, and these sections in this order:

1. Containers and orchestration
   - List every container/service defined by Docker Compose or Ansible role compose
     files.
   - Include its apparent host/server, management path (just task, mise task, or
     Ansible role when available), exposed host ports and protocols, and IP or URL
     when explicitly documented.
   - Include services documented in the repository even if their compose file is in
     docs/, but mark documentation-only entries clearly.

2. Managed servers
   - List every server in ansible/inventory.yml and every VM defined by Terraform.
   - Include name, IP, role/group, and the source path for each fact.
   - Call out mismatches, duplicates, or servers that appear in only one system.

3. Ansible vs Terraform
   - Summarize what Ansible manages (playbooks, host groups, roles, and notable
     service configuration).
   - Summarize what Terraform manages (modules, Proxmox resources, VM names/IPs,
     images, and networking).
   - Explain the apparent handoff between the two tools.

4. Server configuration
   - Group configuration by server and summarize deployed services, storage,
     mounts, backups, monitoring, users, and other relevant settings found in the
     repository.
   - Include useful paths to the configuration sources.

Use tables where they improve scanability. Cite repository-relative paths inline for
important facts. Distinguish explicitly configured values from values inferred from
documentation or naming. Use “unknown” rather than guessing. Do not include secret
contents, tokens, passwords, private keys, or environment values that could be
sensitive.
