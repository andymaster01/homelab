deploy-local container:
    ./scripts/local-deployment.sh {{container}}

deploy-remote container:
    ./scripts/remote-deployment.sh {{container}}

pre-commit: check-compose-vars

check-compose-vars:
    @if rg -n '\$\{[A-Za-z_][A-Za-z0-9_]*:\?' containers -g '*.yml' -g '*.yaml'; then \
        echo 'Use ${VAR} instead of ${VAR:?message} in Compose files' >&2; \
        exit 1; \
    fi

scrap:
    ./scripts/scrap.sh

prepare:
    ./scripts/prepare.sh 192.168.1.151
    ./scripts/prepare.sh 192.168.1.131
    ./scripts/prepare.sh 192.168.1.130

prepare-ubuntu-26:
    ./scripts/prepare-ubuntu-26.sh 192.168.1.140

setup-komodo:
    ./scripts/setup-komodo.sh

enable-komodo:
    ./scripts/enable-komodo.sh

backup container:
    ./scripts/backup.sh {{container}}

vm-validate definition:
    node scripts/proxmox-vm.mjs validate {{definition}}

vm-create definition:
    node scripts/proxmox-vm.mjs create {{definition}}

create-inventory-source:
    @printf '\033[1;36mRepository inventory\033[0m\n\n'
    @codex exec --model gpt-6-luna -c 'model_reasoning_effort="medium"' "$(cat prompts/repository-inventory.md)"

create-inventory-website:
    @codex exec --model gpt-6-luna -c 'model_reasoning_effort="medium"' "$(cat prompts/generate-inventory-website.md) Inventory file: summary/inventory.md"

open-inventory-website:
    open summary/inventory/index.html

commit:
    codex exec --model gpt-6-luna -c 'model_reasoning_effort="medium"' "Review all pending changes in this repository and commit them. Create a focused Conventional Commit message that accurately describes the changes. Do not modify files beyond what is necessary to make the commit."
