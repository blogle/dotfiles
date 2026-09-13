# OpenHands Agent Sandbox Runtime

This is the `nandstorm` overlay for
[`blogle/openhands-agent-sandbox`](https://github.com/blogle/openhands-agent-sandbox).

It pins the adapter and Agent Server images, configures the public runtime URL,
holds the encrypted runtime credentials, and exposes the adapter through the
cluster's Traefik ingress.

The reusable base manifests remain in the project repository. Do not add
cluster credentials or the `thejeffer.net` URL there.

## Validation

```bash
kubectl diff -k hosts/nandstorm/k8s
kubectl apply -k hosts/nandstorm/k8s
```

Run the opt-in project lifecycle test through a local adapter port-forward:

```bash
kubectl -n openhands-sandboxes port-forward svc/openhands-runtime-adapter 18080:80
RUN_LIVE_E2E=1 \
KUBECONFIG=/workspace/kube_config/config \
RUNTIME_API_URL=http://127.0.0.1:18080 \
RUNTIME_PROXY_URL=http://127.0.0.1:18080 \
RUNTIME_API_KEY="$(kubectl -n openhands-sandboxes get secret openhands-runtime-secrets -o jsonpath='{.data.api-key}' | base64 -d)" \
OPENHANDS_SERVER_IMAGE=ghcr.io/openhands/agent-server:1.37.1-python \
LIVE_TEST_NAMESPACE=openhands-sandboxes \
nix develop /workspace/openhands-agent-sandbox --command make test-live
```

The default profile is intentionally coupled to the pinned
sandbox-server Agent Server dependency: `ghcr.io/openhands/agent-server:1.37.1-python`.
