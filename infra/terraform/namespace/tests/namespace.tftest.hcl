mock_provider "kubernetes" {}
run "isolated_namespace" {
  command = plan
  variables {
    kube_context = "kind-mesh-showcase"
  }
  assert {
    condition     = kubernetes_namespace_v1.mesh.metadata[0].name == "mesh-showcase"
    error_message = "The namespace must remain isolated."
  }
  assert {
    condition     = kubernetes_resource_quota_v1.mesh.spec[0].hard["services.loadbalancers"] == "0"
    error_message = "This local scope must not create paid public load balancers."
  }
}
