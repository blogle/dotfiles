# Anvil Next

This Kustomize overlay deploys a second Anvil instance into the dedicated
`dotfiles` namespace. The canonical public name is Anvil Next. It is registered
in `addrspace/apps/kustomization.yaml`
after the incumbent `anvil` overlay and is reconciled with the apps layer.
Render it independently with:

```sh
kubectl kustomize addrspace/apps/anvil-next
```

The overlay pins the published Anvil v0.2.2 release at merged commit
`ff9d253c01e4e049b19b54a642d6cd4b6b70e061`. The base and all three application
images (`anvil`, `anvil-sandbox`, and `anvil-nix-daemon`) use this same commit's
`sha-*` tags, verified with `docker manifest inspect`. The preceding v0.2.1
release was published but intentionally not promoted because of a model warmup
race; Anvil Next moves directly from v0.2.0 to v0.2.2.

The Anvil Next instance intentionally shares the existing GitHub App identity
with the incumbent Anvil instance. Its credentials are supplied by the
namespace-scoped `github-app-credentials-dotfiles` SealedSecret; `anvild`
requires all three GitHub App keys and will not start without that Secret. This
shared identity means both instances act as the same GitHub App, not separate
identities.

Sealed Secrets are strictly bound to metadata name and namespace. Keep the
`dotfiles` namespace and every existing SealedSecret name, template name, and
ciphertext unchanged; renaming those identities would make decryption fail.

Other state and access boundaries remain independent: the profile-password
Secret (`anvil-profile-credentials`) and controller-signing Secret
(`anvil-controller-signing`) are separately sealed for `dotfiles`; profile
password remains a direct SecretKeyRef in the profile Deployment. The
namespace, profile/Nix/history PVCs, and ingress/certificate/TLS Secret and
preview routing are also separate from incumbent Anvil. No incumbent Secret,
PVC, Namespace, or ingress route is copied or reused. The overlay does not add
cluster-scoped RBAC or storage resources.

The separately sealed `anvil-provider-credentials` Secret configures the
Anvil provider encryption key and operator token for this namespace. An
authorized operator can retrieve the token from the namespace Secret with
`kubectl -n dotfiles get secret anvil-provider-credentials -o
jsonpath='{.data.ANVIL_PROVIDER_OPERATOR_TOKEN}' | base64 -d`. Preserve and back
up `ANVIL_PROVIDER_ENCRYPTION_KEY` securely: existing provider database records
depend on it for decryption, and rotating or losing it can make that data
unreadable. No actual provider/model API credential is onboarded; supplying an
authorized provider credential remains a separate step.

The Ingress uses the shared Traefik SSO authentication middlewares and covers
`anvil-next.thejeffer.net` plus `*.next.preview.thejeffer.net`. The Ingress and
Certificate retain their existing Kubernetes metadata names, as does the TLS
Secret, so Flux with pruning disabled updates their hosts in place rather than
orphaning the old resources. No temporary alias for the previous hostname is
configured; cutover is direct. Before
depending on external access, confirm DNS, certificate issuance, middleware
availability, Agent Sandbox admission/authorization, and sandbox routing.

No new Flux healthChecks are added for these workloads at initial adoption:
the new deployments must first be inspected and their readiness verified
manually, without making the entire apps Kustomization wait on the Anvil Next
instance. Nexus is configured to route the `anvil_next` downstream; runtime
transport is smoke-tested, but tool-parity validation remains pending after
deployment. The incumbent Anvil pin and the Renovate SEV-1 hold are unchanged.
Rendering is structural validation only and does not establish runtime
behavior or external dependency readiness.
