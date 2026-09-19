variable "namespace" {
  type    = string
  default = "sonic-pulse"
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

variable "audio_image" {
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

variable "audio_replicas" {
  type    = number
  default = 1
}

variable "qwen_replicas" {
  type    = number
  default = 1
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
