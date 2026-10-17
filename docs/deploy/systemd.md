# systemd deployment

Follow [Installing without containers](../install-binary.md) for the build and host installation. The original Kallisti service stays at `deploy/kallisti.service`; `deploy/systemd/` has the host Caddyfile and new certificate-copy service and timer. The copier reuses `deploy/docker/sync-certificate.sh`; there is one validation and copy path for both deployment modes. The units target systemd 249 or newer.

## Boundaries and storage

Kallisti runs as the dedicated `kallisti` user. systemd creates `/var/lib/kallisti` with mode 0700 for the SQLite database, uploads, daily database backups and its fallback certificate. The service has a read-only system filesystem, no capabilities and no privilege escalation; it may write only to its state directory. Keep `/etc/kallisti.env` root-readable only because it holds the SuperUser password. The process binds port 8080 on all interfaces: block external access to 8080 with a host firewall. Only Caddy should reach it on `127.0.0.1:8080`.

Caddy listens on TCP 80 and 443. The host Caddyfile adds HTTPS headers and a request-body limit, forwards HTTP and WebSocket traffic, and leaves access logs off because file URLs contain bearer keys. The built-in Mumble server listens directly on TCP and UDP 64738; open both to native clients. External Murmur keeps its own Mumble port. The proxy must forward the real client address; do not place another proxy in front without reviewing `TRUST_FORWARDED_FOR`.

## Certificate renewal

The timer runs every five minutes. Its root-only service reads Caddy's certificate store and writes only to Kallisti's state directory. It checks the DNS name, that the certificate has at least 48 hours left and that the private key matches. It then switches the pair together. The app reads the current pair on new Mumble TLS connections; existing connections continue. If Caddy has not issued a certificate, the service fails, logs the reason and retries at the next timer run; the app keeps using its saved self-signed certificate.

```sh
systemctl status kallisti caddy kallisti-certificate.timer
systemctl list-timers kallisti-certificate.timer
journalctl -u kallisti -u kallisti-certificate.service -n 100
caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile
```

The default Caddy storage path in the unit is `/var/lib/caddy/.local/share/caddy`. Override `CADDY_DATA_DIR` in `/etc/kallisti-cert.env` if the Caddy package uses another path; do not make its private key readable by the `kallisti` user. The timer needs the `kallisti` data directory to exist, so start the main service first. Only root should edit the root-owned script or units.

## Updates and recovery

Use [Updating without containers](../updating.md#without-containers) for the app binary and web files. When service or timer files change, install them again and run `systemctl daemon-reload`; validate Caddyfile changes before `systemctl reload caddy`. Back up the database, uploads, fallback certificate and settings off-host using [Backups](../backups.md). An older binary may not understand a database migrated by a newer one: restore the pre-update database snapshot before rolling back the program. A failed certificate-copy service does not stop Kallisti; check its logs and Caddy's certificate first, rather than weakening file permissions or disabling TLS verification.
