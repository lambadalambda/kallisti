# Updating

There are no releases yet: an update means the newest `main` from git.

## What happens at an update

At its start, a new version brings the database up to date by itself
(migrations). It needs no manual steps, but the changes are one-way: an
older version may not work with the database afterwards. So:

- Set `BACKUP_DIR` (the compose files do). Kallisti then copies the
  database before it opens it. If that copy fails (for example, a full
  disk), the server does not start.
- Right after the update, copy the newest file in `BACKUP_DIR` to another
  place: each start takes one of the `BACKUP_KEEP` places, so a few
  restarts (or a crash loop) remove the copy from before the update.
- Read the [upgrade notes](#upgrade-notes) below for changes you should
  know about.
- After the start, look at the log: "database backup before the start"
  (the copy) and "server running".

Uploads and the server certificate do not change at updates.

## Docker or Podman

The Compose files stay at `deploy/compose*.yml` and read `deploy/.env`.
Keep the same project name (`deploy` by default, or `kallisti` for
`compose.behind-proxy.yml`) and never remove the data volume. If you
previously used `-p` or `COMPOSE_PROJECT_NAME`, keep using that name.
The Murmur variant still accepts self-signed certificates by default.

```sh
git pull
docker compose -f deploy/compose.yml build --pull
docker compose -f deploy/compose.yml up -d --pull always --remove-orphans
docker compose -f deploy/compose.yml logs -f kallisti
```

(With your compose file: `compose.behind-proxy.yml` or
`compose.murmur.yml`.) `build --pull` builds Kallisti on fresh base images,
`--pull always` updates Caddy, and `--remove-orphans` stops containers the
compose file no longer has (see the upgrade notes). The data stays in the
volume.

## Without containers

Build as in [installing](install-binary.md#build), then on the server, from
the repository root:

```sh
systemctl stop kallisti
cp kallisti /opt/kallisti/kallisti
rm -rf /opt/kallisti/web && cp -r apps/web/dist /opt/kallisti/web
systemctl start kallisti
journalctl -u kallisti -f
```

Stop first: a running program cannot be replaced on every system. Replace
the web app folder as a whole: the new `index.html` must come with the new
program. When the service or certificate timer changes, copy the changed files from
`deploy/kallisti.service` and any changed units in `deploy/systemd/` to
`/etc/systemd/system/`, and the shared copier from
`deploy/docker/sync-certificate.sh` to `/opt/kallisti/sync-certificate`
(mode 0755, owned by root); then run `systemctl daemon-reload`. Compare
`deploy/systemd/Caddyfile` with your installed Caddyfile before merging
changes: do not overwrite your real domain with the example hostname.
Validate it with `caddy validate --config /etc/caddy/Caddyfile --adapter
caddyfile` before `systemctl reload caddy`.

## Going back

1. Stop Kallisti.
2. Restore the database copy from before the update ([backups](backups.md#restore)).
3. Start the old version (`git checkout <old commit>`, then build and
   install it as above).

Messages and other changes made with the new version are lost with the old
database.

## Upgrade notes

Newest first. Each migration runs once, at the first start of a version
that has it.

### 2026-10-15

- **User ids** (built-in server): message ownership, read marks and
  reactions now use the Mumble user id, not the name. The migration finds
  the ids by name. Verified messages whose author no longer has a
  registration lose the verified mark (nobody can edit them any more;
  moderators and admins can still delete them). In front of a Murmur, read marks start again from the
  beginning once (there are no ids to find); old messages keep their owner
  by name.
- **Guest accounts** (built-in server): "Join as guest" creates a temporary
  account, removed after a day without a visit. Registration ids are never
  given twice from now on.
- **Reactions**, **link previews** (the server fetches pages: see
  `LINK_PREVIEWS`), **typing indicator**, **Markdown**.
- **Noise suppression** in the web app (RNNoise, DeepFilterNet3). The
  Content Security Policy allows WebAssembly (`wasm-unsafe-eval`). The
  server now gzips the web app's files.
- **Backups** are now made before the start, then daily (before: at the
  start, after the migrations).
- **Backups** are on in the compose files (`/data/backups`): they use disk
  space (7 copies of the database).
- With the built-in server, `TEXT_CHANNELS` is read only at the first start;
  later changes do nothing. Admins manage text channels in the app.
- `MUMBLE_CERT_FILE` and `MUMBLE_KEY_FILE` (a real certificate for the
  Mumble port) and `compose.behind-proxy.yml` are new.
- Earlier the same day: message search (a full-text index, built once
  from all messages; this can take a moment on a large database), replies,
  topics, read state, editing and deleting messages, moderators, text
  channel mirrors for Mumble clients, the lobby, avatars.

### 2026-10-14

- `deploy/compose.yml` now runs the built-in Mumble server, not Murmur.
  Murmur's data is not taken over: to keep Murmur, use
  `compose.murmur.yml`. Update with `--remove-orphans`, or the old Murmur
  container keeps port 64738 and Kallisti cannot start.
