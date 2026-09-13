# OpenHands

Complete OpenHands deployment with isolated per-conversation sandboxes.

## Architecture

```text
Browser
  → Agent Canvas (openhands.thejeffer.net)
    → sandbox-server (openhands-control.thejeffer.net)
      → runtime adapter (ClusterIP)
        → SandboxClaim → agent-sandbox controller
          → Sandbox + PVC + Agent Server
```

## Components

| Component | Directory | Namespace | URL |
|-----------|-----------|-----------|-----|
| Agent Canvas | `.` (root) | `openhands` | https://openhands.thejeffer.net |
| sandbox-server | `sandbox-server/` | `openhands` | https://openhands-control.thejeffer.net |
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
2. Go to **Manage Backends** → **Add Backend** → **Manual**
3. Fill in:
   - **Name**: `OpenHands Kubernetes`
   - **Host**: `https://openhands-control.thejeffer.net`
   - **Type**: `Cloud`
   - **API Key**: any non-empty string (P0 single-tenant)
4. Select the `OpenHands Kubernetes` backend
5. Start a conversation with repository `blogle/dojo2`

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
