# OpenHands on nandstorm

This overlay runs OpenHands Agent Canvas as a persistent, single-replica
StatefulSet using `ghcr.io/openhands/agent-canvas:1.16.0`. It mirrors the
official experimental Helm chart in plain manifests so the cluster remains
deployable with the repository's Kustomize workflow.

Agent Canvas is unauthenticated and single-tenant, and the open-source image
does not isolate agent runs in separate sandbox containers. Every run shares
the pod filesystem and can execute commands there. Tinyauth gates the public
Ingress at `https://openhands.thejeffer.net/canvas`. The ServiceAccount has no
Kubernetes RBAC grants and does not receive an API token.

The `/persist/openhands` host path backs one retained 20 Gi volume. Its
`openhands` subdirectory persists settings, encrypted secrets, conversations,
the automation SQLite database, and generated backend keys at
`/home/openhands/.openhands`; its `workspace` subdirectory persists cloned
repositories and agent work at `/home/openhands/workspace`. Configure the LLM
through the UI after first boot; credentials and API keys must not be added to
these manifests.

## Deploy and verify

```sh
kubectl kustomize hosts/nandstorm/k8s/apps/openhands >/tmp/openhands.yaml
kubectl apply --dry-run=server -f /tmp/openhands.yaml
kubectl apply -k hosts/nandstorm/k8s
kubectl -n openhands rollout status statefulset/openhands
```

Open `https://openhands.thejeffer.net/canvas` after the rollout completes.

## One-time OpenCode cleanup

`kubectl apply -k` does not prune resources removed from Kustomize. After the
OpenHands replacement is healthy, explicitly remove the old workloads and
retained PV objects:

```sh
kubectl delete namespace opencode-system opencode-sandboxes
kubectl delete pv opencode-central-state opencode-gateway-state
```

The PVs used a `Retain` policy, so these commands do not erase their host data.
Only after confirming that no OpenCode state is needed, manually remove
`/persist/opencode` on nandstorm.
