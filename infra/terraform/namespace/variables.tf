variable "namespace" {
  type    = string
  default = "mesh-showcase"
  validation {
    condition     = can(regex("^mesh-showcase(?:-[a-z0-9-]+)?$", var.namespace))
    error_message = "Use an isolated showcase namespace."
  }
}
variable "kubeconfig_path" {
  type    = string
  default = "~/.kube/config"
}
variable "kube_context" {
  type = string
  validation {
    condition     = length(trimspace(var.kube_context)) > 0
    error_message = "Choose an explicit target context; never infer current-context."
  }
}
