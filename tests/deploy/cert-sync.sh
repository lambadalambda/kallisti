#!/bin/sh
# Local regression check for certificate validation, renewal and atomic publication.
set -eu

root=$(CDPATH='' cd -- "$(dirname "$0")/../.." && pwd)
container_tool=${CONTAINER_TOOL:-docker}
image="kallisti-cert-sync-test-$$"
work=$(mktemp -d)
trap 'rm -rf "$work"; "$container_tool" image rm "$image" >/dev/null 2>&1 || :' EXIT

"$container_tool" build -q -f "$root/deploy/docker/Dockerfile.cert-sync" -t "$image" "$root" >/dev/null
source_dir="$work/caddy/caddy/certificates/issuer/chat.example.org"
mkdir -p "$source_dir" "$work/app" "$work/bin"
"$container_tool" run --rm --entrypoint sh -v "$work:/fixture" "$image" -c 'chown -R 1000:1000 /fixture'

issue_certificate() {
  openssl req -x509 -newkey rsa:2048 -nodes -days 7 -subj '/CN=chat.example.org' \
    -addext 'subjectAltName=DNS:chat.example.org' \
    -keyout "$source_dir/chat.example.org.key" -out "$source_dir/chat.example.org.crt" >/dev/null 2>&1
}

sync_once() {
  "$container_tool" run --rm --read-only --user 1000:1000 --cap-drop ALL \
    --security-opt no-new-privileges -e DOMAIN=chat.example.org -e SYNC_ONCE=1 \
    -v "$work/caddy:/caddy-data:ro" -v "$work/app:/app-data" "$image"
}

if sync_once >/dev/null 2>&1; then
  echo 'Missing certificate was accepted' >&2
  exit 1
fi
issue_certificate
sync_once >/dev/null
first=$(sha256sum "$work/app/mumble-tls/current/mumble.crt" | cut -d ' ' -f 1)
[ "$(stat -c '%u:%a' "$work/app/mumble-tls/current/mumble.key")" = 1000:600 ]
issue_certificate
sync_once >/dev/null
second=$(sha256sum "$work/app/mumble-tls/current/mumble.crt" | cut -d ' ' -f 1)
[ "$first" != "$second" ]
openssl genrsa -out "$source_dir/chat.example.org.key" 2048 2>/dev/null
if sync_once >/dev/null 2>&1; then
  echo 'Mismatched key was accepted' >&2
  exit 1
fi
[ "$(sha256sum "$work/app/mumble-tls/current/mumble.crt" | cut -d ' ' -f 1)" = "$second" ]

# Interrupt after rename, before the script clears its staging path.
issue_certificate
cat > "$work/bin/mv" <<'SH'
#!/bin/sh
/bin/mv "$@" || exit
kill -TERM "$PPID"
SH
chmod 0755 "$work/bin/mv"
set +e
"$container_tool" run --rm --read-only --user 1000:1000 --cap-drop ALL \
  --security-opt no-new-privileges -e DOMAIN=chat.example.org -e SYNC_ONCE=1 \
  -e PATH=/probe:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
  -v "$work/bin:/probe:ro" -v "$work/caddy:/caddy-data:ro" \
  -v "$work/app:/app-data" "$image" >/dev/null 2>&1
status=$?
set -e
[ "$status" -eq 143 ]
[ -s "$work/app/mumble-tls/current/mumble.crt" ]
[ -s "$work/app/mumble-tls/current/mumble.key" ]
echo 'Certificate sync checks passed'
