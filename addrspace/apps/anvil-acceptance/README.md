# Anvil isolated acceptance — preparation only

This is a **separate, dormant namespace overlay** for the pre-1.0 TypeScript
rewrite in [blogle/anvil PR #123](https://github.com/blogle/anvil/pull/123).
It is intentionally **not** included in `addrspace/apps/kustomization.yaml`.
There is no Flux reconciliation path, no deployed image, no external ingress,
and the Deployment is fixed at zero replicas. The production `anvil`
namespace and `addrspace/apps/anvil/` remain unchanged.

## Deployment contract to close before activation

1. **FS-13 image:** build and inspect the Nix/Bun daemon image, pin its actual
   immutable digest, check CPU architecture, non-root runtime, SQLite schema
   migration, `/healthz` / `/readyz`, startup, and writable state path.
   Replace the unmistakably non-existent image placeholder.
2. **FS-05 Lease:** `src/main.ts` currently supplies a **local-only Lease
   implementation** that unconditionally reports the configured controller as
   current owner. This is not Kubernetes leader fencing. Implement and
   process-test a real `coordination.k8s.io` Lease adapter and takeover logic
   before enabling any configured worker mutations.
3. **FS-10 credentials and Sandbox:** configure provisioned Sandbox/OpenCode
   images, exact OpenCode API routing, helper/capability bootstrap, namespace
   scoped Sandbox permissions and secure controller-to-worker transport.
   The existing local Git-helper test does **not** validate live injection.
   Confirm shared Nix daemon/store, profile PVC mounts, workspace PVC class,
   ownership, and sandbox-controller compatibility. The PVCs here only reserve
   isolated names; their use is not implemented by this overlay.
4. **Secrets:** separately supply `anvil-acceptance-runtime/api-token` and
   the GitHub App signing key, Git capability signing secret, Mergify token,
   and (if needed) OpenCode auth via sealed-secret/external-secret workflow.
   Wire file-backed secret mounts and `ANVIL_GITHUB_APP_ID`,
   `ANVIL_GITHUB_INSTALLATION_ID`, `ANVIL_GITHUB_PRIVATE_KEY_FILE`,
   `ANVIL_GIT_CAPABILITY_SECRET_FILE`, `ANVIL_MERGIFY_TOKEN_FILE`,
   `ANVIL_SANDBOX_IMAGE_DIGEST`, `ANVIL_WORKSPACE_SIZE`,
   `ANVIL_PROFILE_PVC`, `ANVIL_NIX_PVC`,
   `ANVIL_OPENCODE_URL_TEMPLATE`, `ANVIL_OPENCODE_MODEL_PROVIDER` and
   `ANVIL_OPENCODE_MODEL_ID`. Do not commit secret material or reuse
   production credentials without explicit review.
5. **Isolation:** keep acceptance GitHub branches/PRs, preview hostnames,
   sandbox resources, profile/Nix/state PVCs, ingress and credential scopes
   separate from the incumbent controller. Add ingress/network policy only
   after the service exposure and preview-router design is verified.
6. **FS-15 authorization:** prepare a separate dotfiles review, validate a
   rendered manifest and the live `K8S_ACCEPTANCE_REQUEST`, then require
   explicit authorization before adding this directory to the Flux root,
   changing `replicas`, enabling `ANVIL_PROVIDER_MODE=configured`, issuing
   credentials, or running any cluster commands.

## Current preparation contract

`kustomization.yaml` is independently renderable once the local Kustomize
tool is available. It declares an isolated Namespace, ServiceAccount,
namespace Role/RoleBinding, three PVCs, a fail-closed runtime ConfigMap, and
a dormant ClusterIP daemon Service/Deployment. It intentionally contains no
production namespace references or reusable production secret objects.

**Not acceptance evidence:** authoring or rendering this overlay does not
satisfy FS-13 or FS-15. In particular, no Kubernetes cluster or agent-sandbox
controller has been contacted.
