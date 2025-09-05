# Node role used by EC2 instances launched by Karpenter
resource "aws_iam_role" "karpenter_node_role" {
  name               = "${var.cluster_name}-karpenter-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_instance_profile" "karpenter_node_instance_profile" {
  name = "${var.cluster_name}-karpenter-node-instance-profile"
  role = aws_iam_role.karpenter_node_role.name
  tags = var.tags
}

# Standard EKS worker policies for Karpenter-launched nodes
resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "karpenter_node_AmazonSSMManagedInstanceCore" {
  role       = aws_iam_role.karpenter_node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Karpenter controller IRSA role + permissions
resource "aws_iam_policy" "karpenter_controller_policy" {
  name        = "${var.cluster_name}-karpenter-controller-policy"
  description = "Permissions for Karpenter controller to manage EC2 capacity"
  policy      = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "EC2"
        Effect = "Allow"
        Action = [
          "ec2:CreateLaunchTemplate",
          "ec2:CreateFleet",
          "ec2:CreateTags",
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:Describe*",
          "ec2:DeleteLaunchTemplate"
        ]
        Resource = "*"
      },
      {
        Sid    = "SSMGetParameters"
        Effect = "Allow"
        Action = ["ssm:GetParameter", "ssm:GetParameters"]
        Resource = "arn:aws:ssm:*:*:parameter/*" # allows public Bottlerocket SSM params
      },
      {
        Sid    = "PassNodeRole"
        Effect = "Allow"
        Action = ["iam:PassRole"]
        Resource = aws_iam_role.karpenter_node_role.arn
      },
      {
        Sid    = "Pricing"
        Effect = "Allow"
        Action = ["pricing:GetProducts"]
        Resource = "*"
      },
      {
        Sid    = "CreateSLRForSpot"
        Effect = "Allow"
        Action = ["iam:CreateServiceLinkedRole"]
        Resource = "*"
        Condition = {
          StringEquals = { "iam:AWSServiceName" = "spot.amazonaws.com" }
        }
      }
    ]
  })
  tags = var.tags
}

resource "aws_iam_role" "karpenter_controller_role" {
  name = "${var.cluster_name}-karpenter-controller-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Federated = module.eks.oidc_provider_arn
      }
      Action = "sts:AssumeRoleWithWebIdentity"
      Condition = {
        StringEquals = {
          "${replace(module.eks.oidc_provider, "https://", "")}:sub" = "system:serviceaccount:karpenter:karpenter"
          "${replace(module.eks.oidc_provider, "https://", "")}:aud" = "sts.amazonaws.com"
        }
      }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "karpenter_controller_attach" {
  role       = aws_iam_role.karpenter_controller_role.name
  policy_arn = aws_iam_policy.karpenter_controller_policy.arn
}
