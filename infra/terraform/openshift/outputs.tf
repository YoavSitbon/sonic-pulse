output "namespace" {
  value = kubernetes_namespace_v1.sonic_pulse.metadata[0].name
}

output "api_service" {
  value = kubernetes_service_v1.api.metadata[0].name
}

output "api_route_host" {
  value = try(kubernetes_manifest.api_route.object.spec.host, var.api_route_host)
}

output "qwen_service" {
  value = kubernetes_service_v1.qwen.metadata[0].name
}
