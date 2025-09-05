module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.17"

  cluster_name    = var.cluster_name
  cluster_version = "1.29"

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_irsa = true

  cluster_endpoint_public_access = true

  # Managed Node Group → Bottlerocket + Spot
  eks_managed_node_groups = {
    br_spot = {
      ami_type       = "BOTTLEROCKET_x86_64"
      capacity_type  = "SPOT"
      instance_types = var.node_instance_types

      min_size     = 1
      max_size     = 3
      desired_size = 1

      platform = "linux"
      labels = { "workload" = "system" }
      taints = []
      tags   = merge(var.tags, { Name = "${var.cluster_name}-mng-br-spot" })
    }
  }

  # Allow nodes ↔ control plane
  cluster_security_group_additional_rules = {
    ingress_nodes_ephemeral = {
      description                = "Workers → control plane (ephemeral)"
      protocol                   = "tcp"
      from_port                  = 1024
      to_port                    = 65535
      type                       = "ingress"
      source_node_security_group = true
    }
  }

  # Tag the node SG for Karpenter discovery
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }

  tags = var.tags
}

# OIDC provider (handy output reference)
data "aws_iam_openid_connect_provider" "oidc" {
  arn = module.eks.oidc_provider_arn
}
