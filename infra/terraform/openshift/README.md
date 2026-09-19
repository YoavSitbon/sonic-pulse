# SonicPulse OpenShift infrastructure

This stack deploys the first microservice split:

- `api`: public Flask API and orchestration.
- `audio-analysis`: existing heavy audio models.
- `qwen-inference`: Qwen3-8B served by vLLM on GPU nodes.
- `redis`: shared rate-limit and short-lived state store.

The API is the only public service. Audio and Qwen are internal Kubernetes
Services. The API calls the audio service through `AUDIO_SERVICE_URL` and Qwen
through `MUSIC_AI_BASE_URL`.

## Build images

From `python_backend/`:

```bash
podman build -f Dockerfile.api -t <registry>/sonic-pulse/api:dev .
podman build -f Dockerfile -t <registry>/sonic-pulse/audio:dev .
podman push <registry>/sonic-pulse/api:dev
podman push <registry>/sonic-pulse/audio:dev
```

The audio image is intentionally separate because it contains TensorFlow,
PyTorch, Spleeter, madmom, and the bundled audio models. The API image excludes
those dependencies and does not initialize them when `SERVICE_ROLE=api`.

## Deploy

Authenticate with the cluster first so Terraform can use the active kubeconfig:

```bash
oc login ...
terraform init
cp terraform.tfvars.example terraform.tfvars
# Edit image names and the GPU node selector.
terraform plan -var-file=terraform.tfvars
terraform apply -var-file=terraform.tfvars
```

The Qwen pod downloads `Qwen/Qwen3-8B` into a persistent volume on its first
start. The GPU node pool must expose `nvidia.com/gpu` and have the NVIDIA device
plugin/operator installed.
