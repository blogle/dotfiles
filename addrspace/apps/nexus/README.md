# Nexus MCP Gateway

Nexus snapshots downstream MCP tool catalogs when the process starts. It does
not reliably refresh that catalog when a downstream server changes, so a Nexus
restart is part of the deployment contract.

## When to restart Nexus

Bounce Nexus after either of these changes:

- `configmap.yaml` changes, including a downstream MCP URL, protocol, or auth
  change.
- A downstream MCP server changes its tool names, descriptions, input schema,
  protocol implementation, or image.
- A downstream MCP tool call starts failing with an `invalid session` HTTP 400.
  Nexus keeps static downstream MCP sessions for the lifetime of each pod, so
  replacing the pods establishes fresh upstream sessions.

For an Anvil MCP change, update the appropriate pod-template contract annotation
in `deployment.yaml` (`anvil.example.invalid/mcp-contract-revision` for Anvil or
`anvil-next.example.invalid/mcp-contract-revision` for Anvil Next) to the Anvil
commit that supplied the contract. That annotation is intentionally a rollout
trigger and makes the required Nexus bounce visible in the diff. For a
config-only change, update the existing `checksum/config` annotation as well.

## Deployment procedure

Nexus is managed by Flux. Commit and merge the desired-state change through the
normal PR workflow; Flux reconciles it from `master`. Do not use `kubectl apply`
or an out-of-band rollout restart for routine deployment. The pod-template
annotations above trigger a rollout when the config or downstream contract
changes. Verify the rollout after Flux reports the `addrspace-apps`
reconciliation complete.

## Recover expired downstream sessions

This deployment is Flux-managed, so an out-of-band `kubectl rollout restart`
can be reverted. Replace Nexus pods one at a time and wait for all replicas to
be ready before continuing:

```bash
desired=$(kubectl -n nexus get deployment nexus -o jsonpath='{.spec.replicas}')
pods=$(kubectl -n nexus get pods -l app=nexus -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{end}')
for pod in $pods; do
  kubectl -n nexus delete pod "$pod" --wait=true
  until [ "$(kubectl -n nexus get pods -l app=nexus -o jsonpath='{range .items[*]}{.status.containerStatuses[0].ready}{"\n"}{end}' | awk '$1 == "true" { n++ } END { print n+0 }')" = "$desired" ]; do
    sleep 2
  done
done
kubectl -n nexus rollout status deployment/nexus --timeout=180s
```

The compatibility deployment does not own the downstream tool catalog. Restart
it only when its image or configuration changes.

## Smoke check

Verify the direct Anvil MCP endpoint with `initialize` followed by `tools/list`,
then verify the public Nexus compatibility endpoint with `search` followed by
`execute`. The Anvil controller surface must include all of:

```text
anvil_list_sessions
anvil_get_session
anvil_get_activity
anvil_get_status
anvil_create_session
anvil_send_message
anvil_get_messages
anvil_get_diff
anvil_get_preview
anvil_suspend
anvil_resume
anvil_abort
anvil_delete_session
anvil_rebind_session
anvil_complete_session
```

Do not treat a successful `search` response alone as parity. Execute at least
one read-only operation through Nexus and record any missing operation names
before proceeding with a destructive recovery test.
