output "namespace" {
  value = var.namespace
}

output "api_service" {
  value = kubernetes_service_v1.api.metadata[0].name
}

output "api_route_host" {
  value = try(kubernetes_manifest.api_route.object.spec.host, var.api_route_host)
}

output "qwen_service" {
  value = try(kubernetes_service_v1.qwen[0].metadata[0].name, null)
}
