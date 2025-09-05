# Namespace for Karpenter
resource "kubernetes_namespace" "karpenter" {
  metadata {
    name = "karpenter"
    labels = { "app.kubernetes.io/name" = "karpenter" }
  }
}

# Install Karpenter via Helm (pinned to Provisioner-era chart)
resource "helm_release" "karpenter" {
  name       = "karpenter"
  repository = "https://charts.karpenter.sh"
  chart      = "karpenter"
  version    = "0.32.3" # Provisioner + AWSNodeTemplate era

  namespace = kubernetes_namespace.karpenter.metadata[0].name

  values = [
    yamlencode({
      serviceAccount = {
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.karpenter_controller_role.arn
        }
      }
      settings = {
        aws = {
          clusterName            = module.eks.cluster_name
          clusterEndpoint        = module.eks.cluster_endpoint
          defaultInstanceProfile = aws_iam_instance_profile.karpenter_node_instance_profile.name
          interruptionQueue      = null
        }
      }
      logLevel = "info"
    })
  ]

  depends_on = [
    module.eks,
    aws_iam_role.karpenter_controller_role
  ]
}
