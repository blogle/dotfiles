# Anvil dotfiles

This Kustomize overlay deploys a second Anvil instance into the dedicated
`dotfiles` namespace. It is registered in `addrspace/apps/kustomization.yaml`
after the incumbent `anvil` overlay and is reconciled with the apps layer.
Render it independently with:

```sh
kubectl kustomize addrspace/apps/anvil-dotfiles
```

The overlay pins Anvil release v0.1.1 at merged commit
`6dce30b1963cbc26c31baa1187498f59f92b014e`. The base and all three application
images (`anvil`, `anvil-sandbox`, and `anvil-nix-daemon`) use this same commit;
the immutable GHCR `sha-*` tags were verified to exist (HTTP 200).

The dotfiles instance intentionally shares the existing GitHub App identity
with the incumbent Anvil instance. Its credentials are supplied by the
namespace-scoped `github-app-credentials-dotfiles` SealedSecret; `anvild`
requires all three GitHub App keys and will not start without that Secret. This
shared identity means both instances act as the same GitHub App, not separate
identities.

Other state and access boundaries remain independent: the profile-password
Secret (`anvil-profile-credentials`) and controller-signing Secret
(`anvil-controller-signing`) are separately sealed for `dotfiles`; profile
password remains a direct SecretKeyRef in the profile Deployment. The
namespace, profile/Nix/history PVCs, and ingress/certificate/TLS Secret and
preview routing are also separate from incumbent Anvil. No incumbent Secret,
PVC, Namespace, or ingress route is copied or reused. The overlay does not add
cluster-scoped RBAC or storage resources.

No model/API credential is configured. The service and profile can be deployed,
but real worker/model execution remains gated until an authorized model
credential and its approved secret wiring are provided.

The Ingress uses the shared Traefik SSO authentication middlewares and covers
`anvil-dotfiles.thejeffer.net` plus `*.dotfiles.preview.thejeffer.net`. Before
depending on external access, confirm DNS, certificate issuance, middleware
availability, Agent Sandbox admission/authorization, and sandbox routing.

No new Flux healthChecks are added for these workloads at initial adoption:
the new deployments must first be inspected and their readiness verified
manually, without making the entire apps Kustomization wait on the dotfiles
instance. Do not change Nexus MCP wiring as part of this deployment; that work
is gated on a separately ready MCP service. The incumbent Anvil pin and the
Renovate SEV-1 hold are unchanged. Rendering is structural validation only and
does not establish runtime behavior or external dependency readiness.
