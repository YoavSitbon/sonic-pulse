# SonicPulse OpenShift infrastructure

This stack deploys the first microservice split:

- `api`: public Flask API and orchestration.
- `chord-service`: chord recognition models and optional Spleeter preprocessing.
- `beat-service`: beat, downbeat, tempo, and timing analysis models.
- `qwen-inference`: Qwen3-8B served by vLLM on GPU nodes.
- `redis`: shared rate-limit and short-lived state store.

The API is the only public service. Chord, beat, Redis, and Qwen are internal
Kubernetes Services. The API routes chord requests through `CHORD_SERVICE_URL`
and beat requests through `BEAT_SERVICE_URL`.

## Build images

From `python_backend/`:

```bash
podman build -f Dockerfile.api -t <registry>/sonic-pulse/api:dev .
podman build -f Dockerfile --build-arg SERVICE_ROLE=chord -t <registry>/sonic-pulse/chord:dev .
podman build -f Dockerfile --build-arg SERVICE_ROLE=beat -t <registry>/sonic-pulse/beat:dev .
podman push <registry>/sonic-pulse/api:dev
podman push <registry>/sonic-pulse/chord:dev
podman push <registry>/sonic-pulse/beat:dev
```

The API image excludes the ML dependencies and does not initialize them when
`SERVICE_ROLE=api`. The chord and beat roles are separate runtime services,
although the first image iteration still shares the heavy dependency base;
dependency/image slimming can be done after the service boundaries are
validated.

SongFormer is not deployed yet because its runtime and checkpoint are not
present in this repository. Spleeter remains an optional chord preprocessing
dependency until it has a standalone endpoint and a real consumer.

## Deploy

Authenticate with the cluster first so Terraform can use the active kubeconfig:

```bash
oc login ...
terraform init
cp terraform.tfvars.example terraform.tfvars
# Edit image names. Qwen is disabled by default (`qwen_replicas = 0`) until a
# GPU-capable node pool is available.
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

The Qwen pod downloads `Qwen/Qwen3-8B` into a persistent volume on its first
start. The GPU node pool must expose `nvidia.com/gpu` and have the NVIDIA device
plugin/operator installed.
