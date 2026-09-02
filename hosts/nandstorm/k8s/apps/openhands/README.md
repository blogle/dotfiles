# OpenHands Agent Canvas

## Deployment

OpenHands Agent Canvas 1.16.0, using the official upstream `helm/agent-canvas`
chart, runs as a single StatefulSet. It is single-tenant.

## URL

https://openhands.thejeffer.net/canvas

## LLM

- Ollama: `http://ollama.ai.svc.cluster.local:11434/v1`
- Primary: `qwen3.6:35b-a3b`
- Context: `32768`

## Persistent paths

`/home/openhands/.openhands` and `/home/openhands/workspace` are backed by
`openhands-state-zfs` using StorageClass `openebs-zfspv-retain`.

## Regeneration

```bash
./render.sh
```

## Upgrades

Choose an explicit upstream release tag, replace the vendored chart from that
tag, update `UPSTREAM.md` and image/version configuration, run `render.sh`,
inspect the generated diff, and test before deployment. Never track `main` or
`latest`.

## Known P0 limitation

This is vanilla OpenHands OSS Agent Canvas. Conversations share one backend pod
and filesystem. This deployment does not provide Enterprise-style isolated
agent sandboxes or multi-user tenant isolation.
