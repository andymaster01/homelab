deploy-local container:
    ./scripts/local-deployment.sh {{container}}

deploy-remote container:
    ./scripts/remote-deployment.sh {{container}}

prepare:
    ./scripts/prepare.sh 192.168.1.151
