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

## Image provenance

The Deployment is pinned to the immutable image published from Latchkey source
commit `5812435b40cd1d65209e83d2595251f71ffe715e`. The smoke-gated publisher
passed the standalone search-to-exec smoke test before the immutable GHCR push.
Do not change the Nexus deployment or hostname during pilot validation.

## Pilot validation

The LATCH-44 image replacement is now prepared for deployment:

```bash
kubectl apply -k addrspace/apps/latchkey
kubectl -n nexus rollout status deployment/latchkey --timeout=180s
```

Verify `/healthz` and `/readyz`, then exercise MCP `search` followed by a
read-only `exec` through `latchkey.thejeffer.net`. Keep the Nexus endpoint
active until that search-to-exec check passes.
