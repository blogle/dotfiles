# Upstream: OpenHands/sandbox-server

- Repository: `OpenHands/sandbox-server`
- Git ref: `f19f9e0d88272bb393e39e8cbcb78e3e8aa633a3` (HEAD of main, 2026-09-12)
- Dockerfile: `containers/app/Dockerfile`
- Image: `ghcr.io/blogle/openhands-sandbox-server:f19f9e0d88272bb393e39e8cbcb78e3e8aa633a3`
- Build: `blogle/openhands-sandbox-server-image` GitHub Actions workflow

The Dockerfile is built unmodified from upstream. The entrypoint requires
root (it creates an `enduser` account when `NO_SETUP` is not set). With
`NO_SETUP=true` the entrypoint is a passthrough to `uvicorn`.

Key upstream dependencies:

- `openhands-agent-server==1.37.1`
- `openhands-sdk==1.37.1`
- `openhands-tools==1.37.1`

The sandbox-server listens on port **3000**.

Health endpoints:

- `GET /alive` — liveness probe
- `GET /health` — readiness probe
- `GET /ready` — readiness probe

## Remote runtime mode

When `RUNTIME=remote`, sandbox-server uses `RemoteSandboxServiceInjector`
which requires:

- `SANDBOX_API_KEY` — API key for the runtime adapter
- `SANDBOX_REMOTE_RUNTIME_API_URL` — URL of the runtime adapter

The service communicates with the adapter using the Remote Runtime API
(`/start`, `/stop`, `/pause`, `/resume`, `/list`, `/sessions/{id}`).

## Persistence

`OH_PERSISTENCE_DIR` or `FILE_STORE_PATH` controls the local file-store
root. Default: `$HOME/.openhands`. We override to `/.openhands` for the
PVC mount.
