locals {
  labels = {
    app         = "sonic-pulse"
    managed-by  = "terraform"
    environment = "openshift"
  }
}

resource "kubernetes_namespace_v1" "sonic_pulse" {
  count = var.manage_namespace ? 1 : 0
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
    namespace = var.namespace
  }

  data = {
    SERVICE_ROLE          = "api"
    CHORD_SERVICE_URL     = "http://chord-service:8080"
    BEAT_SERVICE_URL      = "http://beat-service:8080"
    MUSIC_AI_BASE_URL     = var.deploy_qwen ? "http://qwen-inference:8000/v1" : ""
    MUSIC_AI_MODEL        = var.qwen_served_model
    AUDIO_SERVICE_TIMEOUT = "600"
    MUSIC_AI_TIMEOUT      = "120"
    REDIS_URL             = var.deploy_redis ? "redis://redis:6379/0" : ""
  }
}

resource "kubernetes_secret_v1" "runtime" {
  metadata {
    name      = "sonic-pulse-secrets"
    namespace = var.namespace
  }

  type = "Opaque"

  data = {
    MUSIC_AI_API_KEY = ""
  }
}

resource "kubernetes_persistent_volume_claim_v1" "qwen_models" {
  count = var.deploy_qwen ? 1 : 0
  metadata {
    name      = "qwen-model-cache"
    namespace = var.namespace
  }

  spec {
    access_modes = ["ReadWriteOnce"]
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

resource "kubernetes_service_v1" "chord" {
  metadata {
    name      = "chord-service"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = { component = "chord-service" }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_service_v1" "qwen" {
  count = var.deploy_qwen ? 1 : 0
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
  count = var.deploy_redis ? 1 : 0
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
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.runtime.metadata[0].name
            }
          }
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
            requests = { cpu = "500m", memory = "3Gi" }
            limits   = { cpu = "2", memory = "3Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "beat" {
  metadata {
    name      = "beat-service"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = { component = "beat-service" }
    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}

resource "kubernetes_deployment_v1" "chord" {
  metadata {
    name      = "chord-service"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = var.chord_replicas
    selector { match_labels = { component = "chord-service" } }
    template {
      metadata { labels = { component = "chord-service" } }
      spec {
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret_name == null ? [] : [var.image_pull_secret_name]
          content {
            name = image_pull_secrets.value
          }
        }
        container {
          name              = "chord-service"
          image             = var.chord_image
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 8080
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.runtime.metadata[0].name
            }
          }
          env {
            name  = "SERVICE_ROLE"
            value = "chord"
          }
          startup_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            failure_threshold = 60
            period_seconds    = 10
            timeout_seconds   = 5
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
            tcp_socket {
              port = 8080
            }
            initial_delay_seconds = 120
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "2.5", memory = "6Gi" }
            limits   = { cpu = "10", memory = "6Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "beat" {
  metadata {
    name      = "beat-service"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    replicas = var.beat_replicas
    selector { match_labels = { component = "beat-service" } }
    template {
      metadata { labels = { component = "beat-service" } }
      spec {
        dynamic "image_pull_secrets" {
          for_each = var.image_pull_secret_name == null ? [] : [var.image_pull_secret_name]
          content { name = image_pull_secrets.value }
        }
        container {
          name              = "beat-service"
          image             = var.beat_image
          image_pull_policy = "IfNotPresent"
          port {
            name           = "http"
            container_port = 8080
          }
          env_from {
            config_map_ref {
              name = kubernetes_config_map_v1.runtime.metadata[0].name
            }
          }
          env {
            name  = "SERVICE_ROLE"
            value = "beat"
          }
          startup_probe {
            http_get {
              path = "/health"
              port = 8080
            }
            failure_threshold = 60
            period_seconds    = 10
            timeout_seconds   = 5
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
            tcp_socket {
              port = 8080
            }
            initial_delay_seconds = 120
            period_seconds        = 30
          }
          resources {
            requests = { cpu = "1500m", memory = "6Gi" }
            limits   = { cpu = "6", memory = "6Gi" }
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "qwen" {
  count = var.deploy_qwen ? 1 : 0
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
            claim_name = kubernetes_persistent_volume_claim_v1.qwen_models[0].metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_deployment_v1" "redis" {
  count = var.deploy_redis ? 1 : 0
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
      annotations = {
        "haproxy.router.openshift.io/timeout" = "3m"
      }
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
