# Shared local inference

Ollama runs as one replica in the `ai` namespace and is available only inside
the cluster at `http://ollama.ai.svc.cluster.local:11434`. It has no Ingress or
external Service. The pod requests all three Titan V GPUs and uses `Recreate`,
because a rolling replacement could not schedule while the old pod held every
GPU. Ollama cloud features are disabled so requests remain local.

Ollama is used here for heterogeneous, intermittent homelab inference with
dynamic model residency. Reconsider vLLM or SGLang if sustained throughput,
large concurrency, or production serving features become dominant. Ollama
currently owns all three GPUs and Kubernetes GPU sharing is intentionally not
configured. If another workload needs direct GPU allocation, revisit that
ownership model rather than bypassing scheduler accounting.

## Versions and models

- Ollama 0.32.6, linux/amd64 image digest
  `sha256:6b1ea96f5e72f4fbeaa3ddce98dafec32682b17a94f3e635417aafdf2eaed43a`
- `qwen3.5:9b`: model digest
  `6488c96fa5faab64bb65cbd30d4289e20e6130ef535a93ef9a49f42eda893ea7`
- `phi4-mini-reasoning:3.8b`: model digest
  `3ca8c2865ce91b6be853a25e56edfefa4f473db55a391611989b753ecf0fa419`
- `qwen3-embedding:0.6b`: model digest
  `ac6da0dfba84a81fdbfbaf330198c33cd77c4cdfc53e8bc50eb581914a15621d`

The model sidecar idempotently pulls these tags and gates pod readiness until
all are present. `/root/.ollama` is backed by the 40 GiB `ollama-models` claim,
a retained hostPath PV at `/persist/llm/ollama`.

The node actually has about 48 GiB RAM, rather than the approximately 128 GiB
assumed by the initial specification, so the pod is limited to 32 GiB. The
40 GiB hostPath claim is a declared allocation rather than a filesystem quota;
operators must also watch physical free space on `rpool/safe/persist`.

## GPU and observability

Titan V is compute capability 7.0. Ollama 0.32.6 rejects its CUDA 13 runner for
that architecture and automatically selects its CUDA 12 runner; startup logs
must show three `NVIDIA TITAN V` devices using CUDA, not CPU.

DCGM Exporter uses the pinned NVIDIA 4.4.2-4.7.1 Ubuntu image at digest
`sha256:6b5975cdd430d05692c92137bb264938196ee9165e55205a0e31a5e89a9873ee`.
The newer 4.6.0-4.8.3 distroless image exited during DCGM initialization on this
NixOS/Volta host; the Ubuntu image was the smallest compatible adjustment.
Prometheus discovers `ServiceMonitor/dcgm-exporter` at a 15-second interval.
Grafana imports the **Ollama and NVIDIA GPUs** dashboard (UID `ollama-gpu`) from
the `ollama-gpu-dashboard` ConfigMap. Ollama stdout/stderr is collected by Alloy
and queried in Loki with `{namespace="ai", app="ollama"}`. Request-body debug
logging is disabled; prompts, responses, and embedding inputs are not logged.

`maravexa/ollama-exporter` was evaluated but rejected for this deployment. It
is a new, single-maintainer project with low adoption, no signed release/SBOM
or image provenance, and an internally inconsistent build (`go 1.25.9` versus
a Go 1.22 Docker build). GPU, pod, health, logs, and `/api/ps` provide sufficient
initial coverage without making the core service depend on it.

## Operations

```sh
# API and models
kubectl -n ai exec deployment/ollama -c model-bootstrap -- \
  curl -fsS http://127.0.0.1:11434/api/version
kubectl -n ai exec deployment/ollama -c model-bootstrap -- \
  curl -fsS http://127.0.0.1:11434/api/tags
kubectl -n ai exec deployment/ollama -c model-bootstrap -- \
  curl -fsS http://127.0.0.1:11434/api/ps

# Pull an additional model into the persistent store.
kubectl -n ai exec deployment/ollama -c ollama -- ollama pull MODEL:TAG

# Explicitly unload a model. Normal idle unloading uses OLLAMA_KEEP_ALIVE=5m.
kubectl -n ai exec deployment/ollama -c model-bootstrap -- \
  curl -fsS -X POST http://127.0.0.1:11434/api/generate \
  -H 'Content-Type: application/json' \
  -d '{"model":"MODEL:TAG","keep_alive":0}'

# Logs and GPU telemetry
kubectl -n ai logs deployment/ollama -c ollama
kubectl -n ai logs deployment/ollama -c model-bootstrap
kubectl get --raw \
  '/api/v1/namespaces/kube-system/services/http:dcgm-exporter:9400/proxy/metrics'
kubectl -n kube-system logs daemonset/dcgm-exporter

# Recreate is safe with the all-GPU allocation.
kubectl -n ai rollout restart deployment/ollama
kubectl -n ai rollout status deployment/ollama --timeout=30m
```

The NixOS NVIDIA device plugin uses CDI. Plugin-generated CDI hooks assume
`/usr/bin/nvidia-ctk`, so the host configuration and the plugin init container
provide that stable FHS symlink to the Nix-store binary before registration.

## Validation record (2026-08-11)

- The pod was allocated `nvidia.com/gpu: 3`; Ollama discovered three 11.8 GiB
  Titan Vs and selected its CUDA 12 compute library for all three.
- Ollama selected one GPU per fitting model and fully offloaded every layer.
  With all three models resident, DCGM reported approximately 6,620 MiB for
  Qwen on GPU 2, 3,980 MiB for Phi on GPU 0, and 6,216 MiB for embeddings on
  GPU 1. `OLLAMA_SCHED_SPREAD=false` did not force a small model across GPUs.
- Qwen generated 128 tokens at 57.72 tokens/s. A cold reload after eviction
  took 15.40 seconds. Phi generated 128 reasoning tokens at 84.22 tokens/s
  with a 10.84-second cold load.
- Native batched embeddings returned eight 1,024-dimensional vectors in
  0.692 seconds. The OpenAI-compatible chat and embeddings APIs also passed.
- Qwen, Phi, and the embedding model coexisted. After five idle minutes Qwen
  and Phi disappeared from `/api/ps`; DCGM showed their GPUs return to 32 MiB
  and 0 MiB used. A later request transparently reloaded Qwen.
- The forced Markdown Vault rebuild embedded 18,222 chunks in 3,479 seconds
  (57m59s), about 3.1 times faster than the previous approximately three-hour
  CPU/FastEmbed run. The client currently hardcodes batches of four; DCGM
  showed one Titan V at 100% and about 6.2 GiB during the rebuild. FTS,
  semantic, and hybrid searches all returned results afterward.
- A pod-template rollout completed in 53 seconds. Deployment events showed
  the old replica scaled to zero before the new pod was created, so the
  all-GPU allocation did not deadlock. The replacement found 11 existing
  blobs, retained all three model digests and 9.7 GiB store size, and performed
  no model downloads.
- Prometheus reported `up{service="dcgm-exporter"}=1`, three GPU series, and
  Ollama CPU/RAM metrics. The Prometheus Operator validated `ollama-alerts`.
  Grafana mounted `ollama-gpu.json`, and a Loki query for
  `{namespace="ai", app="ollama"}` returned logs carrying namespace, pod,
  container, node, and app labels.
