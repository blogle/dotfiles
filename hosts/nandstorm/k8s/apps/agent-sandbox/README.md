# kubernetes-sigs/agent-sandbox

Declarative installation of the upstream
[kubernetes-sigs/agent-sandbox](https://github.com/kubernetes-sigs/agent-sandbox)
controller and CRDs into the `nandstorm` cluster.

## Vendored release

- Upstream repository: `kubernetes-sigs/agent-sandbox`
- Release version: `v1.0.2`
- Source asset: `sandbox-with-extensions.yaml`
- Date vendored: 2026-09-12

The manifest is vendored verbatim from the upstream release asset for
reproducibility. Do not edit the vendored file directly; update by replacing
the file with a new release asset and updating this README.

## CRDs installed

- `sandboxes.agents.x-k8s.io`
- `sandboxclaims.extensions.agents.x-k8s.io`
- `sandboxtemplates.extensions.agents.x-k8s.io`
- `sandboxwarmpools.extensions.agents.x-k8s.io`

## Target namespace

`agent-sandbox-system`

## Validation

```bash
kubectl get pods -n agent-sandbox-system
kubectl get crd | grep agents.x-k8s.io
kubectl get crd | grep extensions.agents.x-k8s.io
```
