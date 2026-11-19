# Anvil dotfiles (standalone render-only overlay)

This overlay is intentionally **not registered** in `addrspace/apps/kustomization.yaml`
or Flux. Render it for inspection with:

```sh
kubectl kustomize addrspace/apps/anvil-dotfiles
```

Do not apply it or compare it against the live cluster. It is isolated to the
`dotfiles` namespace: all PVCs, Services, Deployments, ServiceAccount,
Role, and RoleBinding are namespaced there. The Namespace itself is intentionally
omitted from the render, as are cluster-scoped RBAC/storage resources and
migration resources; any future deployment would require the namespace to be
provisioned separately. Each PVC is a distinct claim in `dotfiles`, not a
reference to an incumbent PVC. No incumbent Secret or ingress route is reused
or copied; this overlay has a separate host, TLS Secret, and annotation prefix.

The overlay pins its Anvil base and all three application images to incumbent
commit `9fdd0b9f5a72236c63770d0e95e89b784c9cadda` **provisionally only**. This is
not an MVP image/release approval and must be replaced with an explicitly
reviewed immutable release-image pin before deployment. This old pin predates
the newer Anvil features being validated and cannot run them; do not treat a
successful render as evidence that those features work. After updating to a
compatible reviewed build, provision its required V2 profile Secret specifically
for `dotfiles`, sealed for this namespace. Never reuse the incumbent
profile Secret or its values.

The separate ingress/certificate cover only `anvil-dotfiles.thejeffer.net`
and `*.dotfiles.preview.thejeffer.net`, with a unique TLS Secret. They do not
reuse an incumbent ingress route. The Ingress references the shared Traefik SSO
authentication middlewares, which must be independently confirmed available.
MCP's allowed-host list is scoped to the `dotfiles` namespace. DNS, certificate
issuance, SSO middleware availability, and routing still require independent
verification before any deployment.

Outstanding before this can become a functional deployment:

- Provision and independently review credentials specifically for
  `dotfiles`, including the V2 profile Secret required by a compatible
  updated build, sealed for this namespace and backed by an explicitly approved
  key/rotation path. Do not copy incumbent credential values. The production
  Secret resource is deleted from the rendered overlay; no secret payload is
  present here. Credential-consuming Anvil functionality is not provisioned by
  this render-only overlay.
- Replace the provisional incumbent image/base pin with an approved immutable
  MVP/release image pin and verify the exact published artifacts.
- Review namespace-specific PVC capacity/storage policy, Agent Sandbox
  admission/authorization behavior, DNS and certificate issuance, SSO, and
  sandbox routing before deployment.
