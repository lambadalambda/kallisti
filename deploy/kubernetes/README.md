# Kubernetes template

`chart/` is a Helm chart for one public Kallisti installation on Kubernetes 1.26 or newer. It is not installable with its default values: there is no published application image, known storage capacity or backup destination in this repository. Do not apply the test fixture in `chart/ci/values.yaml`: it uses invalid image addresses, a nonexistent Secret and a fake backup acknowledgment.

## Cluster requirements

- A LoadBalancer implementation that supports TCP 80/443 and TCP plus UDP 64738 on the **same Service and external IP**. Verify this with the chosen provider before installing. Point one public DNS name at that IP; both web and native Mumble clients use it. Public ports 80 and 443 must reach Caddy for ACME issuance and renewal; native clients use 64738 directly. No ingress controller, host networking, privileged container or host path is required.
- A default StorageClass, or a specific class in `storage.className`, with two ReadWriteOnce claims on the same node: app data (SQLite, uploads, local backups and fallback Mumble identity) and Caddy's ACME account and certificates. The deployment has exactly one replica and a Recreate update strategy to avoid two SQLite writers. The storage driver must honor pod `fsGroup: 1000` or provision both volumes writable by UID/GID 1000. Test attach/detach and a restore before relying on the deployment.
- A registry containing **both** images: the root `Dockerfile` for Kallisti and `deploy/docker/Dockerfile.cert-sync` for the certificate copier. Set `images.app` and `images.certSync` to immutable published references, preferably digests. Caddy is pinned to `caddy:2.11.3-alpine` by default. Supply image-pull credentials through the cluster's normal mechanism if the registry is private; the chart does not create secrets.
- An existing namespace-local Secret named by `superuserSecretName`, with key `password`. Create it through your normal secret manager, not a plaintext file committed to Git. The password is still exposed to authorized cluster administrators and to the app process as an environment variable.
- An **off-cluster** backup of the app claim (or a consistent database snapshot plus uploads and identity files), Caddy state, and the Secret/configuration, with a tested restore. Kallisti's own daily SQLite snapshots are on the app claim and do not protect against storage loss. Set `backup.confirmed=true` only after this exists. Size both claims and each container's CPU/memory requests and limits for measured load; the chart will refuse missing values.

All three containers run as UID 1000 with read-only root filesystems. Caddy alone adds `NET_BIND_SERVICE` to bind 80/443; the copier reads Caddy's private store from a read-only mount and writes the app claim. The app never mounts the Caddy claim. Caddy sets security headers, compresses traffic, limits uploads to 11 MB and keeps access logs off because file URLs contain bearer keys. The copier validates the name, remaining validity and matching key every minute, then switches both files together. Kallisti uses its saved self-signed certificate until Caddy issues a valid one.

## Prepare and check

Create a private values file outside this repository based on `chart/values.yaml` and fill every required field. The chart does not install a backup controller, registry or load balancer. Confirm the DNS name, image digests, storage class and actual capacity, backup destination and measured CPU/memory needs before setting `backup.confirmed=true`.

```sh
helm lint deploy/kubernetes/chart -f /secure/path/kallisti-values.yaml --strict
helm template kallisti deploy/kubernetes/chart -n <namespace> -f /secure/path/kallisti-values.yaml
# Only after reviewing the rendered manifests and meeting the requirements:
helm upgrade --install kallisti deploy/kubernetes/chart -n <namespace> --create-namespace -f /secure/path/kallisti-values.yaml
```

Helm uninstallation retains both PVCs to avoid accidental data loss. It does not roll back database migrations or remove stored data. Read [the deployment guide](../../docs/deploy/kubernetes.md) for checks, updates and recovery. No cluster changes were made when writing this template.
