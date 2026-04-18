# Override these via environment or a local .env.mk (gitignored).
-include .env.mk
GCP_IP     ?= 10.128.0.3
GCP_USER   ?= dmartinelli
BASTION    ?= 10.0.93.2
DEPLOY_DIR ?= /opt/fridgecheck
SSH_KEY    ?= $(HOME)/.ssh/id_ed25519
JUMP       := $(if $(BASTION),-J $(GCP_USER)@$(BASTION),)
SSH        := ssh -i $(SSH_KEY) $(JUMP)
SCP        := scp -i $(SSH_KEY) $(JUMP)

.PHONY: run build build-linux deploy test

run:
	go run . --config=config.toml

build:
	go build -o fridgecheck-server .

build-linux:
	GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o fridgecheck-server-linux .

deploy: build-linux
	$(SSH) $(GCP_USER)@$(GCP_IP) "sudo systemctl stop fridgecheck || true"
	$(SCP) fridgecheck-server-linux $(GCP_USER)@$(GCP_IP):/tmp/fridgecheck-server
	$(SSH) $(GCP_USER)@$(GCP_IP) "sudo mv /tmp/fridgecheck-server $(DEPLOY_DIR)/fridgecheck-server && sudo chmod +x $(DEPLOY_DIR)/fridgecheck-server && sudo systemctl start fridgecheck"
	@echo "Deployed to $(GCP_IP)"

test:
	go test ./... -count=1 -v
