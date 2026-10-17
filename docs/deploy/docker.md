# Docker and Podman deployment

For installation commands, use [Installing with Docker or Podman](../install-docker.md). Run Compose from the repository root. The Compose files in `deploy/` support the built-in Mumble server with Caddy (`compose.yml`), an external Murmur with Caddy (`compose.murmur.yml`), or an existing reverse proxy (`compose.behind-proxy.yml`). Only run one variant per installation.

## Traffic and data

- Caddy serves HTTPS on TCP 443 and redirects TCP 80. The app listens only inside the Compose network on 8080; Caddy forwards ordinary requests and WebSockets. The existing-proxy variant must attach to the proxy network and configure that proxy to reach `kallisti:8080` and set `X-Forwarded-For`.
- The built-in Mumble server exposes TCP and UDP 64738 directly. External Murmur handles its own Mumble port; no Mumble port is published by that Compose variant.
- Kallisti runs without root access and writes its SQLite database, uploads, daily database backups and self-signed fallback certificate in `/data`. `cert-sync` runs as root because Caddy's private key is private and the app's data belongs to another user. It reads Caddy storage only and writes the app's data volume; neither the app nor Caddy gets the Docker socket.
- The base and Murmur variants retain the `deploy_` project volumes; the existing-proxy variant retains `kallisti_kallisti-data`. Keep `deploy/.env` in place and preserve any custom Compose project name. Never delete the data volume during an update.

## Certificates and access

Caddy requests and renews the web certificate for `DOMAIN`. For the built-in server with bundled Caddy, `cert-sync` checks every 60 seconds. It copies a certificate only when the name, remaining validity (at least 48 hours) and private key match. It switches the pair together; Kallisti reads the renewed files on each new Mumble TLS connection. Before the first issuance it uses its persistent self-signed certificate. Check `docker compose -f deploy/compose.yml logs cert-sync` if native Mumble clients still see a certificate warning after the website has HTTPS. The existing-proxy variant cannot read an external proxy's certificates: either accept the self-signed Mumble certificate or provide a protected certificate and key under `/data` using `MUMBLE_CERT_FILE` and `MUMBLE_KEY_FILE`.

The external Murmur variant keeps its previous default of accepting self-signed certificates. Set `MUMBLE_INSECURE_TLS=0` in `deploy/.env` when Murmur has a trusted certificate and you want upstream identity checks. Protect `.env`: the SuperUser password is passed as an environment variable and is visible to administrators with Docker access. Docker access also gives access to both data volumes and the certificate key.

Caddy adds HSTS, framing and content-type protections, compresses responses, and limits request bodies to 11 MB for the default 10 MB upload limit. Raise both limits together if uploads need to grow. It does not write access logs because file URLs contain bearer keys. Web traffic must use a public DNS name that resolves to the host and reaches ports 80 and 443; for native clients, also open both protocols on port 64738. Do not publish Kallisti's internal port 8080.

## Operations

Check the rendered configuration before starting a variant (replace `compose.yml` with the selected variant):

```sh
docker compose -f deploy/compose.yml config --quiet
docker compose -f deploy/compose.yml up -d --build
docker compose -f deploy/compose.yml ps
docker compose -f deploy/compose.yml logs --tail=100 kallisti caddy cert-sync
```

Run `sh tests/deploy/cert-sync.sh` from the repository root to check certificate validation, renewal and interruption with synthetic certificates; it needs Docker and OpenSSL.

The Murmur variant has no `cert-sync`; the existing-proxy variant has neither `caddy` nor `cert-sync`. The app health check makes Caddy wait for the HTTP server to start, but it does not prove that native clients can connect or that certificate issuance succeeded. Confirm HTTPS in a browser and test a native Mumble connection separately. For backups and restoring the SQLite file and uploads, follow [Backups](../backups.md); copy them off-host, including the persistent Mumble identity certificate. Also keep the Caddy data volume if you need to preserve its ACME account and certificates.

For updates and one-way database migrations, follow [Updating](../updating.md). Before rolling back a binary, restore a database backup from before that version's migration; reverting Compose files alone cannot undo a database migration. If the certificate copier fails, Kallisti keeps its last valid Mumble certificate while it runs. Check its logs and the key's ownership before restarting it. No server or cluster is changed by the files alone.
