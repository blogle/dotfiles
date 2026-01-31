# OpenClaw (Gateway) on nandstorm k3s

This deploys the OpenClaw Gateway as a single-replica StatefulSet with:
- token auth (stored as a SealedSecret)
- device pairing enabled (recommended for Control UI)
- state persisted on a PVC (`/home/node/.openclaw/state`)
- config copied into the state PVC at startup (`/home/node/.openclaw/state/openclaw.json`)
- workspace persisted on a PVC (`/home/node/openclaw/workspace`)
- ingress restricted to tailnet + LAN via a Traefik IP allowlist middleware

## Token rotation (gateway auth)

1. Generate a new strong token (32+ bytes).
2. Re-seal it (do not commit plaintext):

```sh
./scripts/seal-secret.sh \
  --name openclaw-gateway-token \
  -n openclaw \
  --literal OPENCLAW_GATEWAY_TOKEN=REPLACE_ME \
  --output-dir hosts/nandstorm/k8s/apps/openclaw \
  --scope strict
```

This writes `hosts/nandstorm/k8s/apps/openclaw/openclaw-gateway-token-openclaw.sealed.yaml`.

3. Apply:

```sh
kubectl apply -k hosts/nandstorm/k8s/apps/openclaw
```

## Device pairing (Control UI)

The Control UI requires device identity pairing when device auth is enabled.

- Open the UI (from a LAN or tailnet client): `https://moltbot.thejeffer.net/`
- Follow the pairing prompt and approve using the CLI inside the pod.

Common commands:

```sh
kubectl -n openclaw exec -it statefulset/openclaw-gateway -- sh
node dist/index.js pairing list node
node dist/index.js pairing approve node <code>
```

## OpenAI Codex (ChatGPT OAuth) login

Exec into the gateway pod and run the OAuth flow. Tokens are stored in the state PVC.

```sh
kubectl -n openclaw exec -it statefulset/openclaw-gateway -- sh
node dist/index.js models auth login --provider openai-codex
node dist/index.js models status
```

If the PKCE callback can't bind in a headless shell, open the printed URL in your browser and paste the redirect/code back into the CLI flow.

## Security audit

Run inside the gateway pod:

```sh
kubectl -n openclaw exec -it statefulset/openclaw-gateway -- sh
node dist/index.js security audit
node dist/index.js security audit --deep
node dist/index.js security audit --fix
```
