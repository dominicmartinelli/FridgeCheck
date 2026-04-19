# FridgeCheck Server

Go backend for the FridgeCheck iOS app. Proxies Claude API calls, handles Sign in with Apple, and enforces per-user daily quotas. Designed to run behind Caddy (TLS via ACME) on any Linux VM.

## Stack

- `chi` router + standard middleware stack (mirrors `~/dev/shows/server`)
- `modernc.org/sqlite` for users + usage tracking
- `golang-jwt/jwt/v5` for both Apple ID token verification and session tokens
- `BurntSushi/toml` for config
- Systemd service, cross-compiled via `make deploy`

## Layout

```
main.go              router + TLS/graceful shutdown
config/              TOML config
auth/apple.go        Apple identity token verification (fetches + caches JWKS)
auth/session.go      Session JWT mint/validate
middleware/          Auth bearer, CORS, security headers, rate limit, body limit
db/                  SQLite open + users + usage_events
anthropic/           Thin Claude API client (analyze + recipes)
handlers/            /v1/auth/apple, /v1/me, /v1/scan, /v1/recipes
fridgecheck.service  systemd unit
Makefile             run / build / deploy
```

## Endpoints

| Method | Path | Auth | Purpose |
|---|---|---|---|
| `POST` | `/v1/auth/apple` | — | Exchange Apple identity token for a session JWT |
| `GET` | `/v1/me` | Bearer | Current user info + today's usage |
| `POST` | `/v1/scan` | Bearer | Analyze up to 5 base64 JPEG images |
| `POST` | `/v1/recipes` | Bearer | Generate 5 recipes from ingredients |
| `GET` | `/health` | — | `{"status":"ok"}` |

## Local dev

```bash
cd server
cp config.toml.example config.toml
# fill in jwt_secret and anthropic_api_key
make run
```

```bash
curl http://localhost:8082/health
```

## One-time VM setup (same VM as shows)

Before running any of the commands in this section or `make deploy`, create a
gitignored `server/.env.mk` with your real host/user values. The `Makefile`
auto-includes it and falls back to non-functional placeholders if absent:

```makefile
# server/.env.mk (gitignored)
GCP_IP   = 10.0.0.42
GCP_USER = alice
BASTION  = 10.0.0.1
```

The examples below use `user@bastion` and `user@app-server` as stand-ins for
`$(GCP_USER)@$(BASTION)` and `$(GCP_USER)@$(GCP_IP)`.

SSH into the app server via the bastion and run:

```bash
ssh -J user@bastion user@app-server
sudo bash
useradd --system --no-create-home --shell /usr/sbin/nologin fridgecheck || true
install -d -o fridgecheck -g fridgecheck -m 755 /opt/fridgecheck
install -d -o fridgecheck -g fridgecheck -m 755 /var/lib/fridgecheck
install -d -o root -g root -m 755 /etc/fridgecheck
```

Install the systemd unit (one-time; the binary deploys via `make deploy`):

```bash
sudo scp -J user@bastion fridgecheck.service \
  user@app-server:/tmp/
sudo mv /tmp/fridgecheck.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable fridgecheck
```

Copy your config:

```bash
# On your Mac: create config.toml (fill in secrets), then:
scp -J user@bastion config.toml user@app-server:/tmp/fridgecheck.toml
ssh -J user@bastion user@app-server \
  'sudo install -m 600 -o fridgecheck -g fridgecheck /tmp/fridgecheck.toml /etc/fridgecheck/config.toml && rm /tmp/fridgecheck.toml'
```

The Caddy site block lives in `server/fridge.caddy` and is installed to
`/etc/caddy/sites.d/fridge.caddy` on the VM by `make deploy` — no manual
Caddyfile editing required. The VM's base `/etc/caddy/Caddyfile` should
use `import /etc/caddy/sites.d/*.caddy` so each service on the host owns
its own site file and reboots don't clobber it.

Point DNS at your provider: `<your-domain> A <app server external IP>`.

## Deploy

From your Mac:

```bash
cd ~/dev/fridgecheck/server
make deploy
```

Watch logs:

```bash
ssh -J user@bastion user@app-server 'sudo journalctl -u fridgecheck -f'
```

## Quick smoke test

```bash
curl https://<your-domain>/health
# {"status":"ok"}

# Apple exchange — requires a real identity token from the iOS app; no easy curl.
```
