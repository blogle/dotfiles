# Personal knowledge base

The `knowledge` namespace runs Ignis and markdown-vault-mcp against one shared,
human-owned Markdown root. Ignis is available at
`https://obsidian.thejeffer.net` through Traefik, cert-manager, and the existing
Tinyauth middleware. The MCP server is also available at
`https://markdown-vault-mcp.thejeffer.net/mcp` through the private
Traefik/MetalLB path for tailnet clients. The same pod's OpenAI tunnel-client
continues to reach
`http://127.0.0.1:8000/mcp` for ChatGPT.

The namespace also contains two external GHCR collectors. Their production
manifest digests are centralized in `kustomization.yaml`; release tags are not
used for deployment.

## Collectors

`telegram-collector` is a one-replica `Recreate` Deployment. It watches the
configured Telegram streams and writes to the live vault at
`The Chadlands/70 Sources/Telegram`, while its SQLite database, Telegram
session, archive, and work directories live in `telegram-collector-state`.
The config uses the verified Mud Room (`-5184613712`) and Player
(`-1003944547386`) streams, both with a `2026-07-01` backfill. The DM stream is
intentionally omitted until its verified Telegram ID is resolved; do not infer
or invent an ID.

The Telegram auth Job is intentionally suspended. Create the credentials
Secret as `telegram-credentials`, then authenticate against the shared state
claim with:

```sh
kubectl -n knowledge scale deployment/telegram-collector --replicas=0
kubectl -n knowledge patch job telegram-collector-auth -p '{"spec":{"suspend":false}}'
kubectl -n knowledge wait --for=condition=Ready pod -l app=telegram-collector-auth --timeout=60s
kubectl -n knowledge attach -it "$(kubectl -n knowledge get pod -l app=telegram-collector-auth -o jsonpath='{.items[0].metadata.name}')"
kubectl -n knowledge scale deployment/telegram-collector --replicas=1
```

After authentication, the Deployment reuses `/state/telegram.session`. To
populate Telegram channel access hashes in a fresh session, run the same image
once with `--config /etc/telegram-collector/config.yaml chats --json` before
starting the watcher. The API ID/hash identify the application; the resulting
user session is long-lived and normally survives pod restarts and upgrades on
the state PVC. A new login code is needed only after session revocation,
security invalidation, or state loss. To resolve the omitted DM before adding
it, inspect the same `chats --json` output. Do not add a stream until its chat
ID is confirmed.

`chatgpt-collector` is configured for 03:30 in `America/Los_Angeles` with
`concurrencyPolicy: Forbid`, but remains suspended until renewable
authentication is proven. It maps the `The Chadlands` project to the root
of `The Chadlands/70 Sources/Strategy Sessions/Raw Export`; raw incremental
state and manifests stay in `chatgpt-collector-state`. Every run performs an
authentication preflight. Intervention-required authentication failures exit
with code 3, preserve the last valid publication, record a safe classification,
and are not retried with the same credential.

Pinned `chatgpt-exporter` 1.1.0 supports only a bearer access token; it has no
refresh token, cookie jar, browser session, OAuth, or login command. The current
integration is therefore an alerted manual-renewal fallback, not production-
ready renewable authentication. After obtaining a fresh `accessToken` from
`https://chatgpt.com/api/auth/session` in an already authenticated browser,
replace only the `CHATGPT_TOKEN` value in `chatgpt-credentials`. A newly created
manual Job reads the updated Secret and reuses the existing state PVC; the
CronJob itself does not need to be recreated. Never store a password, 2FA code,
browser profile, cookie jar, or token in this repository.

No plaintext credentials are committed here. Namespace-bound SealedSecret
ciphertext may be committed. Create it from local plaintext files using the
repository helper, for example:

```sh
./scripts/seal-secret.sh --name telegram-credentials -n knowledge \
  --file TELEGRAM_API_ID=/secure/telegram-api-id \
  --file TELEGRAM_API_HASH=/secure/telegram-api-hash \
  --file TELEGRAM_PHONE=/secure/telegram-phone \
  --output-dir hosts/nandstorm/k8s/apps/knowledge --scope strict
./scripts/seal-secret.sh --name chatgpt-credentials -n knowledge \
  --file CHATGPT_TOKEN=/secure/chatgpt-token \
  --output-dir hosts/nandstorm/k8s/apps/knowledge --scope strict
```

Keep generated sealed manifests in this directory and add them to the
Kustomization only once they contain real ciphertext. The workloads reference
the documented Secret names, so `kubectl kustomize` does not require those
secrets to render.

The login code and optional 2FA password are entered through the interactive
auth Job and are not retained in the Secret. Delete and recreate the completed
Job before repeating authentication because Kubernetes Job pod templates are
immutable.

The MCP pod disables Kubernetes service-link environment injection. Otherwise
the identically named Service injects `MARKDOWN_VAULT_MCP_PORT=tcp://...`, which
conflicts with the application's integer `MARKDOWN_VAULT_MCP_PORT` setting.

## Storage

`/persist/knowledge/vaults` is the durable source of truth. It is mounted in
full at `/vaults` in Ignis and `/data/vaults` in markdown-vault-mcp. No vault,
folder, or domain taxonomy is created by this deployment. Every top-level
directory users create under `/vaults` is an independent Ignis vault, while
markdown-vault-mcp recursively indexes their Markdown as one corpus.

Each collector mounts only its disjoint owned source subtree at `/output`:
Telegram mounts `The Chadlands/70 Sources/Telegram`, and ChatGPT mounts
`The Chadlands/70 Sources/Strategy Sessions/Raw Export`. These directories must
exist in the live vault before rollout. They are paths within the same durable
vault hostPath, not second vault copies or Git checkouts.

Application-owned state uses dynamically provisioned `local-path` claims:

- `markdown-vault-mcp-state` at `/data/state` contains the rebuildable SQLite
  index, vector data, MCP/session state, key-value data, and FastEmbed cache.
- `ignis-data` at `/app/data` contains Ignis application data.
- `ignis-obsidian-app` at `/app/obsidian-app` caches Obsidian 1.12.7 assets.
- `telegram-collector-state` at `/state` contains the SQLite cursor database,
  Telegram session, archive, and work files.
- `chatgpt-collector-state` at `/state` contains incremental exporter data and
  run manifests.

The claims contain no human-authored Markdown. MCP state is disposable and can
be rebuilt from the vault, though retaining it avoids reindexing and repeated
model downloads.

Application packages and OCI images are independently validated and published
by their owning repositories. This host flake deliberately does not use sibling
workspace path inputs or redefine their packages. Kubernetes consumes
digest-pinned OCI artifacts directly; a local path input must never appear in a
production lock file.

This repository validates only integration concerns:

```sh
bash scripts/check-knowledge-boundaries.sh
bash scripts/test-knowledge-isolated.sh
kubectl kustomize hosts/nandstorm/k8s >/dev/null
kubectl apply --dry-run=client -k hosts/nandstorm/k8s
nix flake check --no-build
```

The GHCR digests in `kustomization.yaml` are resolved from published, locally
pulled release images. Confirm and smoke-test each replacement digest before
rollout; rendering itself does not pull images.

For an upgrade, publish collector images from tested source revisions, resolve
their registry digests, replace the image references with those immutable
digests, inspect
`kubectl diff -k hosts/nandstorm/k8s`, then apply. Roll back by restoring the
previous known-good tags and applying again. Collector state PVCs and published
Markdown are retained across either operation.

Ignis remains on the upstream image. The child-process-compatible source keeps
Git out of its default image and exposes an explicit `IGNIS_INCLUDE_GIT=true`
build option. Deploying that feature requires a separately published,
digest-pinned downstream image and an explicit decision to enable
`IGNIS_CHILD_PROCESS`; neither is selected by these manifests yet.

Filesystem watching handles edits inside existing vaults. Adding a completely
new top-level vault may require `kubectl -n knowledge rollout restart
deployment/markdown-vault-mcp` or an explicit reindex so the watcher registers
the new directory.

## Tunnel credentials

`tunnel-credentials.sealed.yaml` is a namespace-scoped SealedSecret generated
from the proven POC's `CONTROL_PLANE_TUNNEL_ID` and
`CONTROL_PLANE_API_KEY`. Never commit an unsealed Secret. To rotate the values,
use `scripts/seal-secret.sh` with `--scope strict`, replace the sealed manifest,
and restart `deployment/markdown-vault-mcp`.

The sidecar runs tunnel-client 0.0.10 from the host's
`/run/current-system/sw/bin/tunnel-client`, mounted read-only into a pinned
Alpine runtime containing CA certificates. It does not mount `/nix/store`.

## Operations

```sh
kubectl -n knowledge get deployments,pods,pvc,service,ingress
kubectl -n knowledge get cronjob,job
kubectl -n knowledge describe ingress markdown-vault-mcp
kubectl -n knowledge logs deployment/markdown-vault-mcp -c markdown-vault-mcp
kubectl -n knowledge logs deployment/markdown-vault-mcp -c tunnel-client
kubectl -n knowledge logs deployment/telegram-collector
kubectl -n knowledge logs job/telegram-collector-auth
kubectl -n knowledge create job --from=cronjob/chatgpt-collector "chatgpt-collector-manual-$(date +%s)"
kubectl -n knowledge rollout restart deployment/markdown-vault-mcp
kubectl -n knowledge rollout restart deployment/ignis
```
