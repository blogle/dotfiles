# OpenHands

OpenHands Agent Canvas deployment with optional isolated per-conversation
sandboxes.

## Architecture

```text
Local backend
  Canvas → bundled local Agent Server

OpenHands Kubernetes backend
  Canvas → sandbox-server → runtime adapter → Agent Sandbox
    → SandboxClaim → Sandbox + PVC + Agent Server
```

## Components

| Component | Directory | Namespace | URL |
|-----------|-----------|-----------|-----|
| Agent Canvas | `.` (root) | `openhands` | https://openhands.thejeffer.net |
| sandbox-server | `sandbox-server/` | `openhands` | internal service on port 3000 |
| runtime adapter | `../openhands-agent-sandbox/` | `openhands-sandboxes` | https://openhands-runtime.thejeffer.net |
| agent-sandbox controller | `../agent-sandbox/` | `agent-sandbox-system` | (internal) |

## Agent Canvas

OpenHands Agent Canvas 1.16.0, using the official upstream `helm/agent-canvas`
chart, runs as a single StatefulSet. It is single-tenant.

### URL

https://openhands.thejeffer.net/canvas

### LLM

- Ollama: `http://ollama.ai.svc.cluster.local:11434/v1`
- Primary: `qwen3.8:27b`
- Context: `32768`

### Persistent paths

`/home/openhands/.openhands` and `/home/openhands/workspace` are backed by
`openhands-state-zfs` using StorageClass `openebs-zfspv-retain`.

### Regeneration

```bash
./render.sh
```

## sandbox-server

See [sandbox-server/README.md](sandbox-server/README.md).

## Agent Canvas → Cloud backend configuration

After sandbox-server is healthy, configure Agent Canvas:

1. Open https://openhands.thejeffer.net
2. Go to **Manage Backends** → **Add Backend** → **Manual connection**
3. Fill in:
   - **Name**: `OpenHands Kubernetes`
   - **Host**: `http://openhands-sandbox-server.openhands.svc.cluster.local:3000`
   - **Type**: `Cloud`
   - **API Key**: `local-legacy`
4. Select the `OpenHands Kubernetes` backend
5. Start a conversation without choosing a repository.

The Canvas and sandbox-server are intentionally single-user. OIDC and
multi-user application semantics remain deferred. The selected Cloud routes
are intentional: `/api/v1`, `/api/keys/current`, and `/api/organizations` are
sent to sandbox-server while ordinary Canvas routes remain local. The
compatibility endpoint `/api/keys/current` intentionally returns HTTP 400,
which Canvas interprets as a valid legacy API key. It can be removed if OSS
sandbox-server implements the Canvas Cloud-account contract directly.

## Routing

- `/canvas`, `/api/settings`, `/api/cloud-proxy`: local Canvas backend
- `/api/v1`, `/api/keys/current`, `/api/organizations`: Canvas Cloud proxy to
  the internal sandbox-server service
- `/sandbox/<runtime-id>`: runtime adapter ingress and remote Agent Server

The Cloud backend host is intentionally an in-cluster DNS name: Canvas's
server-side Cloud proxy resolves it, avoiding the browser-facing Tinyauth
middleware. The deployment has one remote sandbox profile and zero warm
replicas. It does not provide per-conversation image selection or OIDC
application integration.

## Pins

- Agent Canvas: `1.16.0`
- sandbox-server: `f19f9e0d88272bb393e39e8cbcb78e3e8aa633a3`
- Agent Server: `1.37.1-python`
- openhands-agent-sandbox: `v0.1.3`
- agent-sandbox: `v0.5.3`

## Per-conversation isolation

Each conversation gets:

- A dedicated `SandboxClaim` → `Sandbox`
- An independent workspace PVC (20Gi, `openebs-zfspv`)
- Its own Agent Server pod
- Independent repository checkout at `/workspace/project/<repo>`

## Upgrades

Choose an explicit upstream release tag, replace the vendored chart from that
tag, update `UPSTREAM.md` and image/version configuration, run `render.sh`,
inspect the generated diff, and test before deployment. Never track `main` or
`latest`.
