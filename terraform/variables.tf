variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "syam-doc"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "eu-central-1"
}

variable "vpc_cidr" {
  description = "VPC CIDR"
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "How many AZs to span"
  type        = number
  default     = 2
}

variable "node_instance_types" {
  description = "Instance types for the EKS Managed Node Group (Spot)"
  type        = list(string)
  default     = ["t3.large"]
}

variable "karpenter_instance_types" {
  description = "Allowed instance types for Karpenter (Spot)"
  type        = list(string)
  default     = ["t3.large", "m5.large", "c5.large"]
}

variable "tags" {
  description = "Common tags"
  type        = map(string)
  default = {
    Project     = "eks-bottlerocket-spot-karpenter"
    Environment = "demo"
    Owner       = "syam@doc.io"
  }
}
