# Override these via environment or a local .env.mk (gitignored).
# Put your real host/user values in server/.env.mk — it is auto-included below
# and never committed. The placeholders here are intentionally non-functional.
-include .env.mk
GCP_IP     ?= your.app.server.ip
GCP_USER   ?= your-ssh-user
BASTION    ?= your.bastion.ip
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
	$(SCP) fridge.caddy $(GCP_USER)@$(GCP_IP):/tmp/fridge.caddy
	$(SSH) $(GCP_USER)@$(GCP_IP) "sudo mkdir -p /etc/caddy/sites.d && sudo install -o root -g root -m 644 /tmp/fridge.caddy /etc/caddy/sites.d/fridge.caddy && rm /tmp/fridge.caddy && sudo systemctl reload caddy"
	@echo "Deployed to $(GCP_IP)"

test:
	go test ./... -count=1 -v
