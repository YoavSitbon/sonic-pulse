locals {
  labels = {
    app         = "sonic-pulse"
    managed-by  = "terraform"
    environment = "openshift"
  }
}

resource "kubernetes_namespace_v1" "sonic_pulse" {
  metadata {
    name = var.namespace
    labels = {
      "app.kubernetes.io/name"       = "sonic-pulse"
      "app.kubernetes.io/managed-by" = "terraform"
    }
  }
}

resource "kubernetes_config_map_v1" "runtime" {
  metadata {
    name      = "sonic-pulse-runtime"
    namespace = kubernetes_namespace_v1.sonic_pulse.metadata[0].name
  }

  data = {
    SERVICE_ROLE           = "api"
    AUDIO_SERVICE_URL      = "http://audio-analysis:8080"
    MUSIC_AI_BASE_URL      = "http://qwen-inference:8000/v1"
    MUSIC_AI_MODEL         = var.qwen_served_model
    AUDIO_SERVICE_TIMEOUT  = "600"
    MUSIC_AI_TIMEOUT       = "120"
    REDIS_URL              = "redis://redis:6379/0"
  }
}

resource "kubernetes_secret_v1" "runtime" {
  metadata {
    name      = "sonic-pulse-secrets"
    namespace = kubernetes_namespace_v1.sonic_pulse.metadata[0].name
  }

  type = "Opaque"

  data = {
    MUSIC_AI_API_KEY = ""
  }
}

resource "kubernetes_persistent_volume_claim_v1" "qwen_models" {
  metadata {
    name      = "qwen-model-cache"
    namespace = kubernetes_namespace_v1.sonic_pulse.metadata[0].name
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    resources {
      requests = {
        storage = var.model_storage_size
      }
    }
  }
}

resource "kubernetes_service_v1" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = { component = "api" }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_service_v1" "audio" {
  metadata {
    name      = "audio-analysis"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = { component = "audio-analysis" }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_service_v1" "qwen" {
  metadata {
    name      = "qwen-inference"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = { component = "qwen-inference" }
    port {
      name        = "http"
      port        = 8000
      target_port = 8000
    }
  }
}

resource "kubernetes_service_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = { component = "redis" }
    port {
      name        = "redis"
      port        = 6379
      target_port = 6379
    }
  }
}

resource "kubernetes_deployment_v1" "api" {
  metadata {
    name      = "api"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = var.api_replicas
    selector { match_labels = { component = "api" } }
    template {
      metadata { labels = { component = "api" } }
      spec {
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret_name == null ? [] : [var.image_pull_secret_name]
          content {
            name = image_pull_secrets.value
          }
        }
        container {
          name              = "api"
          image             = var.api_image
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 8080
          }
          env_from { config_map_ref { name = kubernetes_config_map_v1.runtime.metadata[0].name } }
          env_from {
            secret_ref {
              name     = kubernetes_secret_v1.runtime.metadata[0].name
              optional = true
            }
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 15
            period_seconds        = 10
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 30
            period_seconds        = 20
          }
          resources {
            requests = { cpu = "500m", memory = "1Gi" }
            limits   = { cpu = "2", memory = "3Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "audio" {
  metadata {
    name      = "audio-analysis"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = var.audio_replicas
    selector { match_labels = { component = "audio-analysis" } }
    template {
      metadata { labels = { component = "audio-analysis" } }
      spec {
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret_name == null ? [] : [var.image_pull_secret_name]
          content {
            name = image_pull_secrets.value
          }
        }
        container {
          name              = "audio-analysis"
          image             = var.audio_image
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 8080
          }
          env {
            name  = "SERVICE_ROLE"
            value = "audio"
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 60
            period_seconds        = 15
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            initial_delay_seconds = 120
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "2", memory = "6Gi" }
            limits   = { cpu = "6", memory = "12Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "qwen" {
  metadata {
    name      = "qwen-inference"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = var.qwen_replicas
    selector { match_labels = { component = "qwen-inference" } }
    template {
      metadata { labels = { component = "qwen-inference" } }
      spec {
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret_name == null ? [] : [var.image_pull_secret_name]
          content {
            name = image_pull_secrets.value
          }
        }
        node_selector = var.qwen_node_selector
        container {
          name              = "qwen"
          image             = var.qwen_image
          image_pull_policy = "IfNotPresent"
          command           = ["vllm"]
          args              = ["serve", var.qwen_model, "--host", "0.0.0.0", "--port", "8000", "--served-model-name", var.qwen_served_model, "--max-model-len", tostring(var.qwen_max_model_len)]
          port {
            name           = "http"
            container_port = 8000
          }
          volume_mount {
            name       = "model-cache"
            mount_path = "/root/.cache/huggingface"
          }
          readiness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 120
            period_seconds        = 15
            failure_threshold     = 20
          }
          liveness_probe {
            http_get {
              path = "/health"
              port = 8000
            }
            initial_delay_seconds = 180
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "4", memory = "12Gi", "nvidia.com/gpu" = tostring(var.qwen_gpu_count) }
            limits   = { cpu = "8", memory = "20Gi", "nvidia.com/gpu" = tostring(var.qwen_gpu_count) }
          }
        }
        volume {
          name = "model-cache"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.qwen_models.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "redis" {
  metadata {
    name      = "redis"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = 1
    selector { match_labels = { component = "redis" } }
    template {
      metadata { labels = { component = "redis" } }
      spec {
        container {
          name  = "redis"
          image = var.redis_image
          port {
            name           = "redis"
            container_port = 6379
          }
          args = ["redis-server", "--appendonly", "yes"]
          resources {
            requests = { cpu = "50m", memory = "128Mi" }
            limits   = { cpu = "250m", memory = "512Mi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_manifest" "api_route" {
  manifest = {
    apiVersion = "route.openshift.io/v1"
    kind       = "Route"
    metadata = {
      name      = "api"
      namespace = var.namespace
    }
    spec = merge(
      {
        to   = { kind = "Service", name = kubernetes_service_v1.api.metadata[0].name }
        port = { targetPort = "http" }
        tls  = { termination = "edge", insecureEdgeTerminationPolicy = "Redirect" }
      },
      var.api_route_host == null ? {} : { host = var.api_route_host }
    )
  }
}
