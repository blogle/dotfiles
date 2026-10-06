# Latchkey Standalone Pilot

This is a parallel standalone-mode pilot in the existing `nexus` namespace.
It reuses the Nexus namespace's SealedSecret-backed GitHub and Lific Secrets;
no credential values are stored here. Nexus and its existing tunnel remain
unchanged and available for rollback.

The additive private endpoint is `latchkey.thejeffer.net`, using the existing
Traefik, certificate, and SSO middleware pattern. This preserves an
authenticated private boundary for `/mcp`; the Nexus tunnel is intentionally
not repointed or duplicated during the pilot.

The existing Nexus credentials are treated as bare tokens. An init container
can read the raw Secret files, writes `Bearer `-prefixed header files into a
memory-backed volume without shell tracing or output, and the main container
can access only those synthesized files. The raw Secret volume is not mounted
in the Latchkey container.

## Image prerequisite

Latchkey PR #47 and the OCI/publisher PR #50 are merged. The smoke-gated
publisher is currently running for latchkey master SHA
`33643144f286a74d5431d641109f6e3ad5116532`. The deployment remains
intentionally blocked by the marker in `image-prerequisite.yaml` until the
publisher provides its exact immutable digest.

Once the digest is available, replace the marker in `deployment.yaml` with the
exact `ghcr.io/blogle/latchkey@sha256:...` value. Do not invent or guess a
digest, and do not change the Nexus deployment or hostname.

## Pilot validation

After the image prerequisite is satisfied:

```bash
kubectl apply -k addrspace/apps/latchkey
kubectl -n nexus rollout status deployment/latchkey --timeout=180s
```

Verify `/healthz` and `/readyz`, then exercise MCP `search` followed by a
read-only `exec` through `latchkey.thejeffer.net`. Keep the Nexus endpoint
active until that search-to-exec check passes.
