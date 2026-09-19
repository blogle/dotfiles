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

For an Anvil MCP change, update the `anvil.example.invalid/mcp-contract-revision`
pod-template annotation in `deployment.yaml` to the Anvil commit that supplied
the contract. That annotation is intentionally a rollout trigger and makes the
required Nexus bounce visible in the diff. For a config-only change, update the
existing `checksum/config` annotation as well.

## Deployment procedure

Run from the dotfiles repository:

```bash
kubectl apply -k addrspace/apps/nexus
kubectl -n nexus rollout status deployment/nexus --timeout=180s
kubectl -n nexus rollout status deployment/nexus-mcp-compat --timeout=180s
```

If applying a local change without changing the pod annotation, explicitly
restart the gateway:

```bash
kubectl -n nexus rollout restart deployment/nexus
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
