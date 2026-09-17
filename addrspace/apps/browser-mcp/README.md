# Browser MCP

This app provides a private, cluster-local browser MCP for Nexus. It uses one
two-container Pod:

```text
Nexus -> browser-mcp:8080/mcp -> mcp-proxy -> agent-browser -> Chrome CDP
```

## Pinned runtime

- MCP container: `node:24-slim`
- HTTP-to-stdio bridge: `mcp-proxy@6.7.18`
- Browser MCP server: `agent-browser@0.37.1`
- Browser runtime: `chromedp/headless-shell:151.0.7922.109`
- agent-browser profile: `core,network,debug`

`mcp-proxy` is required because Nexus and ChatGPT use Streamable HTTP while
agent-browser exposes an MCP server over stdio. It also handles the MCP
protocol revision boundary without a local compatibility implementation.

Chrome is a sidecar so the browser runtime is separate from the Node/npm
process. Both containers share the Pod network namespace, and agent-browser
connects to `http://127.0.0.1:9222` using its supported JSON config file. The
config also enables tab pinning so named sessions remain isolated when using
external CDP. No browser binary is installed or downloaded by the MCP container.

Browserless is intentionally not used. The browser is the public
`chromedp/headless-shell` image controlled directly over CDP.

## Endpoints

- MCP Service: `http://browser-mcp.browser-mcp.svc.cluster.local:8080/mcp`
- Proxy health: `http://browser-mcp.browser-mcp.svc.cluster.local:8080/ping`
- Chrome CDP, Pod-internal only: `http://127.0.0.1:9222/json/version`

The Service exposes only port `8080`. There is no Chrome Service, Ingress,
NodePort, or LoadBalancer.

## Nexus registration

The recovered Nexus configuration is in `../nexus/configmap.yaml`. It registers
the server as `browser` using:

```toml
[mcp.servers.browser]
protocol = "streamable-http"
url = "http://browser-mcp.browser-mcp.svc.cluster.local:8080/mcp"
```

Nexus's public `/mcp` path continues to use the existing
`nexus-mcp-compat` compatibility endpoint. This browser app is not a Nexus
sidecar and does not install Chrome into Nexus.

## Deployment and inspection

Apply the app with:

```bash
kubectl apply -k addrspace/apps/browser-mcp
kubectl -n browser-mcp rollout status deployment/browser-mcp
```

Inspect both containers independently:

```bash
kubectl -n browser-mcp logs deployment/browser-mcp -c mcp
kubectl -n browser-mcp logs deployment/browser-mcp -c chrome
kubectl -n browser-mcp describe pod -l app=browser-mcp
```

Check health from inside the Pod:

```bash
kubectl -n browser-mcp exec deployment/browser-mcp -c mcp -- \
  node -e 'fetch("http://127.0.0.1:8080/ping").then(async r => { console.log(r.status, await r.text()) })'
kubectl -n browser-mcp exec deployment/browser-mcp -c mcp -- \
  node -e 'fetch("http://127.0.0.1:9222/json/version").then(async r => { console.log(r.status, await r.text()) })'
```

The Chrome image currently starts its upstream entrypoint with its own
defaults, including an internal `9223` listener and a loopback relay on
`9222`. This manifest adds no Chrome flags and does not add `--no-sandbox`.

## MCP smoke tests

Use an MCP client that supports Streamable HTTP and discover the actual tool
names with `tools/list`; do not assume tool names. The basic sequence is:

```text
initialize -> tools/list -> agent_browser_open -> agent_browser_snapshot
-> agent_browser_screenshot -> agent_browser_get_url -> agent_browser_close
```

For interaction, use a public page with controls, take a fresh snapshot, then
use the returned element references with `agent_browser_click` and
`agent_browser_fill` or `agent_browser_type`. Use a subsequent snapshot to
confirm the changed state.

The screenshot result must contain an MCP `image` content item with usable
PNG or JPEG bytes. A path such as `/tmp/screenshot.png` inside the Pod is not
an acceptance result by itself. Test this through Nexus as well as directly
against the Service.

With the enabled profile, verify at least:

- `agent_browser_network_requests` after opening a page
- `agent_browser_console`
- `agent_browser_errors`

The `core` profile includes navigation, snapshots, interaction, waits,
screenshots, JavaScript evaluation, and basic tabs. `network` adds request
inspection and interception. `debug` adds console and page-error inspection.
Tabs/windows/frames/dialogs and persistent state profiles are intentionally
not enabled unless a later requirement demonstrates they are needed.

Use distinct `session` arguments for concurrent logical sessions. Tab pinning is
enabled in the config because the browser is externally connected over CDP. For
example, open one page with session `review-a`, another with `review-b`, alternate
calls, and verify each session retains its own URL and page state. Browser state is
ephemeral and lasts only while the Pod and its session daemon remain alive.

## Startup measurement

`npx -y` installs the two pinned packages at every Pod creation. This is
intentional for the proof of concept and requires npm registry egress. Record
these values for each rollout:

| Measurement | Value |
| --- | --- |
| Pod created to `/ping` healthy | ~17s (cached-image rollout) |
| Pod created to Chrome `/json/version` healthy | ~1s (cached-image rollout) |
| Pod created to first successful browser action | ~48s (includes MCP client startup) |

If this startup behavior is consistently irritating, the follow-up is a small
pre-baked OCI image containing these exact pinned dependencies. That image is
not part of this deployment.

## Security and limitations

The app has a dedicated `browser-mcp` namespace, disables service-account token
mounting, grants no RBAC, drops all container capabilities, disallows
privilege escalation, avoids host networking/PID/IPC/mounts, and exposes only
the MCP Service port. `/dev/shm` is an ephemeral 512 MiB memory volume for
Chrome. No PVC or persistent browser profile is used.

This is not the final hardened deployment. NetworkPolicy is deferred, so the
Pod currently has broader egress than intended. The next phase should add
default-deny egress with DNS, approved internet, and the Anvil preview route,
while denying arbitrary cluster, Kubernetes API, LAN, and Tailscale access.
Machine authentication to Anvil previews is also a separate follow-up; this
PoC tests public or unauthenticated pages only and does not change Tinyauth,
PocketID, Traefik auth, or Anvil authentication.
