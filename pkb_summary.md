# Personal Knowledge Base Deployment Summary

Implemented and deployed the knowledge-base stack. Ignis, markdown-vault-mcp,
FastEmbed, and the OpenAI Secure MCP Tunnel are operational.

## Files changed

- `pkgs/tunnel-client.nix`
- `pkgs/default.nix`
- `hosts/nandstorm/default.nix`
- `hosts/nandstorm/k8s/apps/kustomization.yaml`
- `hosts/nandstorm/k8s/apps/knowledge/{namespace,storage,markdown-vault-mcp,ignis}.yaml`
- `hosts/nandstorm/k8s/apps/knowledge/kustomization.yaml`
- `hosts/nandstorm/k8s/apps/knowledge/tunnel-credentials.sealed.yaml`
- `hosts/nandstorm/k8s/apps/knowledge/README.md`

No NVIDIA configuration was changed.

## Deployed versions

- markdown-vault-mcp: `v3.1.0`
  - Image digest: `sha256:02a03afbe0d6ffc2d03733f1925c6233390c951753e873544b5843968f42d9be`
  - MCP `get_server_info`: server `3.1.0`, core `4.3.0`
- Ignis: `0.8.8`
- Obsidian: `1.12.7`
- tunnel-client: `0.0.10`
- Sidecar runtime: Alpine `sha256:4bcff63911fcb4448bd4fdacec207030997caf25e9bea4045fa6c8c44de311d1`

## Storage

Dynamic `local-path` PVCs are bound:

- `markdown-vault-mcp-state`: 10Gi
- `ignis-data`: 5Gi
- `ignis-obsidian-app`: 5Gi

They were provisioned by `rancher.io/local-path` under `/var/lib/rancher/k3s/storage/...`; no static PVs were added.

Human Markdown remains exclusively at:

```text
/persist/knowledge/vaults
```

The root is `0775` and owned by `1000:1000`. Validation-only content was
removed after testing; subsequent user-created vault content remains there.

## tunnel-client packaging

The proven v0.0.10 `buildGoModule` derivation was promoted into `pkgs/` and installed system-wide.

Verified on `nandstorm`:

```text
/run/current-system/sw/bin/tunnel-client --version
0.0.10

ldd:
not a dynamic executable
```

It executes successfully inside the pinned Alpine sidecar, which has CA certificates and no `/nix/store` mount.

## FastEmbed

Configured with:

```text
provider: fastembed
model: BAAI/bge-small-en-v1.5
cache: /data/state/fastembed
vectors: /data/state/embeddings/embeddings
```

The model cache contains the persisted 66 MB ONNX model. No GPU resources or NVIDIA runtime settings are requested.

## Live MCP evidence

A real FastMCP client initialized the server and enumerated 33 tools, including `write`, `read`, `edit`, `search`, `embeddings_status`, and `build_embeddings`.

A temporary MCP note was written, read, edited, and keyword-searched successfully.

Conceptual query:

```text
colorful tropical bird hiding fruit at night
```

retrieved content describing:

```text
a scarlet macaw tucked ripe guavas beneath broad leaves...
```

Results:

- Semantic score: `0.6872315406799316`
- Hybrid search ranked the same note first.

## External synchronization and Ignis vault creation

Ignis created temporary vault `knowledge-validation-20260722` through its `/api/vault/create` API without any manifest change.

A note then written through Ignis—not MCP—was automatically indexed after the two-second watcher debounce. Keyword `quartzwhistle` returned:

```text
knowledge-validation-20260722/external-watcher.md
```

A newly created top-level vault was detected without restart in this test. The documented restart/reindex caveat remains for environments where watcher registration does not occur.

All temporary validation content and its vault were removed afterward; MCP now reports zero documents.

## Restart persistence

After MCP Pod recreation:

- Markdown remained available.
- SQLite state remained.
- Two vectors were loaded from persisted storage.
- FastEmbed reported `added=0`, reusing existing vectors and model cache.
- Semantic search returned the same result and score.

Ignis was also restarted and logged:

```text
Obsidian already set up.
```

confirming its application cache persisted.

## Ignis and exposure

- Certificate: Ready
- `https://obsidian.thejeffer.net`: HTTP `401`, proving Tinyauth protection
- HTTP redirects permanently to HTTPS
- Ignis has only a ClusterIP Service
- No MCP Service, Ingress, NodePort, or LoadBalancer exists
- MCP listens only at `127.0.0.1:8000`

## Validation

Passed:

```text
nix flake check path:.
nix build path:.#nixosConfigurations.nandstorm.config.system.build.toplevel
kubectl kustomize hosts/nandstorm/k8s
kubectl diff -k hosts/nandstorm/k8s
```

The built NixOS configuration was copied to and activated on `nandstorm`. Final Kubernetes diff is clean.

## Tunnel resolution

The namespace-scoped SealedSecret now contains a valid runtime key and the
existing Homelab tunnel ID. The Alpine sidecar waits for the loopback MCP port
before executing tunnel-client, preventing the one-time MCP probe from racing
markdown-vault-mcp startup.

Verified final state:

- MCP Pod: `2/2 Running`
- tunnel-client `/healthz`: `200 live`
- tunnel-client `/readyz`: `200 ready`
- MCP session initialized through the tunnel
- Homelab tunnel metadata fetched successfully
- ChatGPT created `Tests/markdown-vault-integration-test.md` through MCP, and
  Ignis discovered `Tests` as a vault without Kubernetes changes
