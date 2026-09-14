# OpenHands sandbox-server

Standalone OpenHands API / sandbox control plane.

This is the missing dispatch layer between Agent Canvas and the runtime
adapter. Canvas talks to sandbox-server; sandbox-server talks to the
`openhands-runtime-adapter` service.

## Components

| Component | Namespace | Service |
|-----------|-----------|---------|
| sandbox-server | `openhands` | `openhands-sandbox-server:3000` |
| runtime adapter | `openhands-sandboxes` | `openhands-runtime-adapter:80` |
| agent-sandbox controller | `agent-sandbox-system` | (internal) |

## Request flow

```text
Browser → Agent Canvas (openhands.thejeffer.net)
  → sandbox-server (openhands-control.thejeffer.net)
    → runtime adapter (ClusterIP, port 80)
      → SandboxClaim → Sandbox → Agent Server (:60000)
```

## URL

The service is routed through `https://openhands-control.thejeffer.net` for
the Cloud API paths. This hostname is intentionally unauthenticated in this
pass; hardening is deferred to a second pass.

## Image

`ghcr.io/blogle/openhands-sandbox-server@sha256:9d6de002f42b098a5249ab1db7cb0d0856e4c9a5085d1cf943d05b428f2c3085`

Built from `OpenHands/sandbox-server@f19f9e0d` (`containers/app/Dockerfile`,
unmodified). See the packaging repository at
`blogle/openhands-sandbox-server-image`.

## Persistence

`/data` is backed by `openhands-sandbox-server-state` using StorageClass
`openebs-zfspv-retain`. This stores conversations, events, and settings.

## Secrets

The Remote Runtime API key comes from the existing
`openhands-runtime-adapter-client` Secret.

## LLM

sandbox-server discovers models from the cluster-local Ollama instance at
`http://ollama.ai.svc.cluster.local:11434`. Users configure their preferred
model through the Canvas settings UI after connecting.

## Agent Canvas configuration

In the Agent Canvas UI:

1. Go to **Manage Backends** → **Add Backend** → **Manual**
2. Configure:
   - **Name**: `OpenHands Kubernetes`
   - **Host**: `https://openhands-control.thejeffer.net`
   - **Type**: `Cloud`
   - **API Key**: `local-legacy`
3. Select the new backend and start a conversation.

## Validation

```bash
kubectl diff -k hosts/nandstorm/k8s
kubectl apply -k hosts/nandstorm/k8s

# Check sandbox-server health
kubectl -n openhands get pods -l app.kubernetes.io/name=sandbox-server
kubectl -n openhands logs deploy/openhands-sandbox-server

# Check end-to-end
kubectl -n openhands port-forward svc/openhands-sandbox-server 13000:3000
curl -s http://127.0.0.1:13000/health
```
