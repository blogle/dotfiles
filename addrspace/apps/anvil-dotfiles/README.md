# Anvil dotfiles (standalone render-only overlay)

This overlay is intentionally **not registered** in
`addrspace/apps/kustomization.yaml` or Flux. Render it for inspection with:

```sh
kubectl kustomize addrspace/apps/anvil-dotfiles
```

The overlay includes its own `Namespace/dotfiles`. Namespaced PVCs, Services,
Deployments, ServiceAccount, Role, and RoleBinding render into `dotfiles`; the
incumbent `Namespace/anvil` and upstream `github-app-credentials` Secret are
removed. The overlay does not create cluster-scoped RBAC or storage resources,
or copy any incumbent Secret, PVC, or ingress route. There are no GitHub App
credentials or fake Secret data in this overlay. The independently generated
`anvil-profile-credentials` and `anvil-controller-signing` SealedSecrets provide
the profile password and controller signing configuration in the `dotfiles`
namespace. The V2 profile's `ANVIL_OPENCODE_SERVER_PASSWORD` is supplied by its
own `anvil-profile-credentials` Secret.

This remains render-only and **cannot be deployed**: `anvild` startup requires
real GitHub App credentials, which are intentionally not included or wired yet.
Do not register the overlay in the apps layer or Flux until those credentials
are provisioned through an approved secret workflow and the other deployment
gates below are cleared.

The upstream Anvil base and all three image tags are pinned to merged release
candidate commit `17b4640ff5b27d3282cef9ac9e9a384c223ee4e6`. Its protected PR
has merged, but image publication is still pending. Do not treat any of the
three immutable image tags as available until the publisher succeeds and the
artifacts are verified. This overlay remains unregistered and must not be
deployed or compared against the live cluster before all deployment gates are
cleared. Rendering is structural validation only; it does not establish
artifact availability, compatibility, or runtime behavior.

The separate ingress/certificate cover only `anvil-dotfiles.thejeffer.net` and
`*.dotfiles.preview.thejeffer.net`, with a unique TLS Secret. The Ingress
references shared Traefik SSO authentication middlewares, which must be
independently confirmed available. DNS, certificate issuance, SSO middleware
availability, and routing also require verification before deployment.

Outstanding deployment gates:

- Wait for publication of the `anvil`, `anvil-sandbox`, and `anvil-nix-daemon`
  artifacts for `17b4640ff5b27d3282cef9ac9e9a384c223ee4e6`, then verify all
  three immutable image references. Publication is pending; do not infer the
  artifacts exist from the merged source commit.
- Provision and independently review a real GitHub App credential Secret for
  `dotfiles` via an approved secret workflow; `anvild` cannot start without it.
  The profile password and controller-signing SealedSecrets are already
  included, sealed for this namespace with independent keys. Do not reuse
  incumbent credential values.
- Review namespace-specific PVC capacity/storage policy, Agent Sandbox
  admission/authorization behavior, DNS and certificate issuance, SSO, and
  sandbox routing.
