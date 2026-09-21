variable "namespace" {
  type    = string
  default = "sonic-pulse"
}

variable "manage_namespace" {
  type    = bool
  default = true
}

variable "kubeconfig_path" {
  type    = string
  default = null
}

variable "kubeconfig_context" {
  type    = string
  default = null
}

variable "api_image" {
  type = string
}

variable "chord_image" {
  type = string
}

variable "beat_image" {
  type = string
}

variable "qwen_image" {
  type    = string
  default = "vllm/vllm-openai:latest"
}

variable "qwen_model" {
  type    = string
  default = "Qwen/Qwen3-8B"
}

variable "qwen_served_model" {
  type    = string
  default = "qwen3-8b"
}

variable "qwen_max_model_len" {
  type    = number
  default = 8192
}

variable "qwen_gpu_count" {
  type    = number
  default = 1
}

variable "qwen_node_selector" {
  type    = map(string)
  default = {}
}

variable "api_replicas" {
  type    = number
  default = 2
}

variable "chord_replicas" {
  type    = number
  default = 1
}

variable "beat_replicas" {
  type    = number
  default = 1
}

variable "qwen_replicas" {
  type    = number
  default = 0
}

variable "deploy_qwen" {
  type    = bool
  default = true
}

variable "deploy_redis" {
  type    = bool
  default = true
}

variable "api_route_host" {
  type    = string
  default = null
}

variable "redis_image" {
  type    = string
  default = "redis:7.4-alpine"
}

variable "model_storage_size" {
  type    = string
  default = "20Gi"
}

variable "image_pull_secret_name" {
  type    = string
  default = null
}

variable "image_pull_policy" {
  type    = string
  default = "Always"

  validation {
    condition     = contains(["Always", "IfNotPresent", "Never"], var.image_pull_policy)
    error_message = "image_pull_policy must be Always, IfNotPresent, or Never."
  }
}

variable "env_file" {
  type        = string
  default     = "../../../python_backend/.env"
  description = "Path to the local dotenv file whose values are loaded into the runtime Secret."
}
