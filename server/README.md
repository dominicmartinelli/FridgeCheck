# FridgeCheck Server

Go backend for the FridgeCheck iOS app. Proxies Claude API calls, handles Sign in with Apple, and enforces per-user daily quotas. Deployed on the same GCP VM as `shows-server`, fronted by the existing Caddy.

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

SSH into the watchlist VM via the bastion and run:

```bash
ssh -J dmartinelli@10.0.93.2 dmartinelli@10.128.0.3
sudo bash
useradd --system --no-create-home --shell /usr/sbin/nologin fridgecheck || true
install -d -o fridgecheck -g fridgecheck -m 755 /opt/fridgecheck
install -d -o fridgecheck -g fridgecheck -m 755 /var/lib/fridgecheck
install -d -o root -g root -m 755 /etc/fridgecheck
```

Install the systemd unit (one-time; the binary deploys via `make deploy`):

```bash
sudo scp -J dmartinelli@10.0.93.2 fridgecheck.service \
  dmartinelli@10.128.0.3:/tmp/
sudo mv /tmp/fridgecheck.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable fridgecheck
```

Copy your config:

```bash
# On your Mac: create config.toml (fill in secrets), then:
scp -J dmartinelli@10.0.93.2 config.toml dmartinelli@10.128.0.3:/tmp/fridgecheck.toml
ssh -J dmartinelli@10.0.93.2 dmartinelli@10.128.0.3 \
  'sudo install -m 600 -o fridgecheck -g fridgecheck /tmp/fridgecheck.toml /etc/fridgecheck/config.toml && rm /tmp/fridgecheck.toml'
```

Add a Caddy block for `fridge.dkm.net`. On the VM, edit `/etc/caddy/Caddyfile`:

```caddyfile
fridge.dkm.net {
    encode gzip zstd
    reverse_proxy 127.0.0.1:8082
    tls {
        issuer acme {
            disable_http_challenge
        }
    }
}
```

Reload Caddy:

```bash
sudo systemctl reload caddy
```

Point DNS at IONOS: `fridge.dkm.net A <watchlist VM external IP>`.

## Deploy

From your Mac:

```bash
cd ~/dev/fridgecheck/server
make deploy
```

Watch logs:

```bash
ssh -J dmartinelli@10.0.93.2 dmartinelli@10.128.0.3 'sudo journalctl -u fridgecheck -f'
```

## Quick smoke test

```bash
curl https://fridge.dkm.net/health
# {"status":"ok"}

# Apple exchange — requires a real identity token from the iOS app; no easy curl.
```
