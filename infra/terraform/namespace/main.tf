terraform {
  required_version = ">= 1.16, < 2.0"
  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "= 3.3.0"
    }
  }
}
provider "kubernetes" {
  config_path    = var.kubeconfig_path
  config_context = var.kube_context
}
resource "kubernetes_namespace_v1" "mesh" {
  metadata {
    name = var.namespace
    labels = {
      "mesh.showcase/managed-by"                   = "terraform"
      "pod-security.kubernetes.io/enforce"         = "restricted"
      "pod-security.kubernetes.io/enforce-version" = "latest"
    }
  }
  lifecycle {
    prevent_destroy = true
  }
}
resource "kubernetes_resource_quota_v1" "mesh" {
  metadata {
    name      = "mesh-budget"
    namespace = kubernetes_namespace_v1.mesh.metadata[0].name
  }
  spec {
    hard = {
      "requests.cpu"           = "4"
      "requests.memory"        = "4Gi"
      "limits.cpu"             = "12"
      "limits.memory"          = "10Gi"
      "pods"                   = "20"
      "persistentvolumeclaims" = "4"
      "services.loadbalancers" = "0"
    }
  }
}
resource "kubernetes_limit_range_v1" "mesh" {
  metadata {
    name      = "mesh-defaults"
    namespace = kubernetes_namespace_v1.mesh.metadata[0].name
  }
  spec {
    limit {
      type = "Container"
      default = {
        cpu    = "1"
        memory = "640Mi"
      }
      default_request = {
        cpu    = "100m"
        memory = "128Mi"
      }
    }
  }
}
output "namespace" {
  value = kubernetes_namespace_v1.mesh.metadata[0].name
}
