deploy-local container:
    ./scripts/local-deployment.sh {{container}}

deploy-remote container:
    ./scripts/remote-deployment.sh {{container}}

scrap:
    ./scripts/scrap.sh

prepare:
    ./scripts/prepare.sh 192.168.1.151
    ./scripts/prepare.sh 192.168.1.130

backup container:
    ./scripts/backup.sh {{container}}

create-inventory-source:
    @printf '\033[1;36mRepository inventory\033[0m\n\n'
    @codex exec --model gpt-6-luna -c 'model_reasoning_effort="medium"' "$(cat prompts/repository-inventory.md)"

create-inventory-website inventory_file:
    @codex exec --model gpt-6-luna -c 'model_reasoning_effort="medium"' "$(cat prompts/generate-inventory-website.md) Inventory file: "{{quote(inventory_file)}}

commit:
    codex exec --model gpt-6-luna -c 'model_reasoning_effort="medium"' "Review all pending changes in this repository and commit them. Create a focused Conventional Commit message that accurately describes the changes. Do not modify files beyond what is necessary to make the commit."
