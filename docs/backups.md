# Backups

## What to keep

- The database (`DB_PATH`): accounts, text channels, messages, reactions,
  read state and, with the built-in server, its registrations, channels and
  rights.
- The uploads (`UPLOAD_DIR`): files people sent. They are not in the
  database: back that folder up yourself. The folder and its files belong to
  the `kallisti` user and only it can read them (mode 0700 and 0600), so run
  the backup as root or `kallisti`, and give restored files back to
  `kallisti`. For example:

  ```sh
  tar czf kallisti-uploads.tar.gz -C /var/lib/kallisti uploads              # without containers
  docker run --rm -v deploy_kallisti-data:/data alpine tar czf - -C /data uploads > kallisti-uploads.tar.gz
  ```
- With the built-in server, its certificate (`cert.pem` and `key.pem` in
  `CERT_DIR`). Without it Mumble clients see a new server and warn.
- Your settings (the compose `.env`, or `/etc/kallisti.env`; the systemd
  certificate timer also uses `/etc/kallisti-cert.env`). When using Caddy,
  retain its data volume or directory if you need its ACME account and web
  certificate; the copied Mumble certificate can be restored from Caddy.

## Database backups

With `BACKUP_DIR` set, Kallisti copies the database:

- at each start, before it opens the database (an update may change it,
  see [updating](updating.md)); if this copy fails, the server does not
  start;
- then every 24 hours while it runs.

The copies are consistent snapshots (SQLite `VACUUM INTO`) named after the
time in UTC (`kallisti-20261015-171302.db`). The newest `BACKUP_KEEP` (7)
stay: each start uses one place, so after a few restarts the copy from
before an update is gone (see [updating](updating.md)).
Copy them to another machine as well: a backup on the same disk does not
help when the disk fails.

## Restore

1. Stop Kallisti.
2. Copy the backup over `DB_PATH` as the `kallisti` user, and remove
   `DB_PATH-wal` and `DB_PATH-shm` if they are there.
3. Start the version of Kallisti that last ran on that database. For the
   copy from before an update, that is the old version (see
   [updating](updating.md#going-back)).

Without containers:

```sh
systemctl stop kallisti
install -o kallisti -g kallisti -m 600 /var/lib/kallisti/backups/kallisti-20261015-171302.db /var/lib/kallisti/kallisti.db
rm -f /var/lib/kallisti/kallisti.db-wal /var/lib/kallisti/kallisti.db-shm
systemctl start kallisti
```

With Docker, in Kallisti's own image (so the files keep the `kallisti`
user):

```sh
docker compose -f deploy/compose.yml stop kallisti
docker compose -f deploy/compose.yml run --rm --no-deps --entrypoint sh kallisti -c \
  'cp /data/backups/kallisti-20261015-171302.db /data/kallisti.db && rm -f /data/kallisti.db-wal /data/kallisti.db-shm'
docker compose -f deploy/compose.yml start kallisti
```

Upload files from after the backup stay on the disk; nothing removes them,
because the cleanup works from the database.
