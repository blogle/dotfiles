# OpenCode on nandstorm

This overlay owns nandstorm's OpenCode deployment. It consumes the reusable
upstream base at an immutable commit and keeps cluster-specific configuration,
storage, authentication, TLS, and routing in this repository.

The `core` overlay intentionally excludes Ingress resources so a new release
can be checked through port-forwards before public cutover.

## Release procedure

1. Update the upstream commit in `core/kustomization.yaml` and all four image
   tags in `core/kustomization.yaml` and `core/config/platform.yaml`.
2. Confirm the four images are publicly pullable.
3. Render and validate both overlays:

   ```bash
   kubectl kustomize hosts/nandstorm/k8s/apps/opencode/core >/tmp/opencode-core.yaml
   kubectl kustomize hosts/nandstorm/k8s/apps/opencode >/tmp/opencode-nandstorm.yaml
   kubectl apply --dry-run=server -f /tmp/opencode-core.yaml
   kubectl apply --dry-run=server -f /tmp/opencode-nandstorm.yaml
   ```

4. Apply `core`, verify `central` and `gateway`, and test through port-forwards.
5. Remove the legacy `opencode` namespace Ingresses and apply the complete
   overlay.

The adapter token is stored only as a strict-scope SealedSecret. Dojo's ignored
`.env` is uploaded through `ocws env push`; it is never committed here.

NetworkPolicy enforcement, backups, quotas, metrics, and lifecycle race
hardening remain post-MVP work.
