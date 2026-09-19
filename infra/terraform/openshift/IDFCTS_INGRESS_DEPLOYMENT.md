# Sonic Pulse deployment: `idfcts-ingress`

This deployment uses Terraform and creates only the three services used by the
local setup: the public API, beat worker, and chord worker. The namespace
already existed and is reused; Redis, Qwen, the Qwen PVC, and their Services
are disabled for this deployment.

## Terraform resources

| Terraform address | Kubernetes resource | Purpose |
| --- | --- | --- |
| `kubernetes_config_map_v1.runtime` | `ConfigMap/sonic-pulse-runtime` | Service URLs and runtime configuration |
| `kubernetes_secret_v1.runtime` | `Secret/sonic-pulse-secrets` | Optional runtime secret values |
| `kubernetes_service_v1.api` | `Service/api` | Public API service on port 8080 |
| `kubernetes_deployment_v1.api` | `Deployment/api` | Public API pods |
| `kubernetes_service_v1.beat` | `Service/beat-service` | Internal beat service on port 8080 |
| `kubernetes_deployment_v1.beat` | `Deployment/beat-service` | Beat model worker pod |
| `kubernetes_service_v1.chord` | `Service/chord-service` | Internal chord service on port 8080 |
| `kubernetes_deployment_v1.chord` | `Deployment/chord-service` | Chord model worker pod |
| `kubernetes_manifest.api_route` | `Route/api` | External HTTPS route to the API |

The existing `Namespace/idfcts-ingress` and `Secret/registry-med-one` are
reused and are not created by this Terraform deployment.

## Inspection commands

```bash
oc get deployment,service,route,configmap,secret -n idfcts-ingress \\
  -l app=sonic-pulse -o wide

oc describe deployment api -n idfcts-ingress
oc describe deployment beat-service -n idfcts-ingress
oc describe deployment chord-service -n idfcts-ingress

oc logs deployment/api -n idfcts-ingress
oc logs deployment/beat-service -n idfcts-ingress
oc logs deployment/chord-service -n idfcts-ingress

oc get route api -n idfcts-ingress \\
  -o jsonpath='https://{.spec.host}{"\\n"}'
```
