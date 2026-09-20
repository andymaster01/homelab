deploy-local container:
    ./scripts/local-deployment.sh {{container}}

deploy-remote container:
    ./scripts/remote-deployment.sh {{container}}

prepare:
    ./scripts/prepare.sh 192.168.1.151
    ./scripts/prepare.sh 192.168.1.130

backup container:
    ./scripts/backup.sh {{container}}

commit:
    codex exec --model gpt-5.6-luna -c 'model_reasoning_effort="medium"' "Review all pending changes in this repository and commit them. Create a focused Conventional Commit message that accurately describes the changes. Do not modify files beyond what is necessary to make the commit."
