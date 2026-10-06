# Latchkey Standalone Pilot

This is a parallel standalone-mode pilot in the existing `nexus` namespace.
It reuses the Nexus namespace's SealedSecret-backed GitHub and Lific Secrets;
no credential values are stored here. Nexus and its existing tunnel remain
unchanged and available for rollback.

The additive private endpoint is `latchkey.thejeffer.net`, using the existing
Traefik and certificate pattern. The Nexus tunnel is intentionally not
repointed or duplicated during the pilot.

## Image prerequisite

Latchkey PR #47 is currently open and the application repository has no
published OCI image. The deployment is therefore intentionally blocked by the
marker in `image-prerequisite.yaml`. After PR #47 merges and the first
publication succeeds, replace the marker in `deployment.yaml` with the exact
published immutable digest from `ghcr.io/blogle/latchkey`.

Do not point Flux at `master` or invent a tag before that application-repository
change is complete.

## Pilot validation

After the image prerequisite is satisfied:

```bash
kubectl apply -k addrspace/apps/latchkey
kubectl -n nexus rollout status deployment/latchkey --timeout=180s
```

Verify `/healthz` and `/readyz`, then exercise MCP `search` followed by a
read-only `exec` through `latchkey.thejeffer.net`. Keep the Nexus endpoint
active until that search-to-exec check passes.
