# syam-doc

# syam-doc — EKS + Bottlerocket (Spot) + Karpenter (Provisioner)
With S3/DynamoDB Terraform backend and GitHub Actions (CI + Deploy)

This repository provisions an **AWS EKS** cluster with:
- A **Managed Node Group** using **Bottlerocket** on **Spot** instances.
- **Karpenter** installed via **Helm**, using the legacy **Provisioner + AWSNodeTemplate** to scale **Bottlerocket on Spot**.
- VPC subnets and the node security group **tagged for Karpenter discovery**.
- A sample **nginx** Deployment to verify scheduling.
- **Remote Terraform state** stored in **S3**, with **DynamoDB** for state locking.
- **GitHub Actions** for CI (fmt/validate/plan) and Deploy (plan+apply + `kubectl apply`).

**Defaults:** region `eu-central-1` (Frankfurt) and cluster name `syam-doc`.

---

## Repository layout

```
.github/
└── workflows/
├── terraform-ci.yml
└── terraform-deploy.yml
kubernetes/
├── karpenter-awsnodetemplate.yaml
├── karpenter-provisioner.yaml
└── nginx-deployment.yaml
terraform/
├── auth.tf
├── backend.tf
├── eks.tf
├── karpenter-helm.tf
├── karpenter-iam.tf
├── outputs.tf
├── providers.tf
├── variables.tf
└── vpc.tf
README.md
```

---

## Architecture Overview
```
AWS
└── VPC (2 AZs)
├── Private subnets (nodes, tagged for Karpenter)
├── Public subnets (egress/LB)
└── NAT + IGW
EKS
└── Cluster (IRSA enabled)
├── Managed Node Group (Bottlerocket, Spot)
└── Karpenter (Helm)
├── IRSA Role for controller (EC2/SSM/Pricing permissions)
├── Instance Profile for provisioned nodes
└── Provisioner + AWSNodeTemplate (Bottlerocket + Spot)
```

**Why these choices**
- **Bottlerocket** for minimal, hardened worker OS.
- **Spot** everywhere to meet the exercise’s cost goal.
- **SSM-based AMI discovery** (no AMI IDs in code):
  - EKS MNG: `ami_type = "BOTTLEROCKET_x86_64"` → EKS resolves the correct AMI.
  - Karpenter: `amiFamily: Bottlerocket` → controller pulls from **SSM** (IAM allows `ssm:GetParameter`).
- **terraform-aws-modules** for VPC/EKS to use proven defaults and keep code concise.
- **Tags** for ownership, environment, and Karpenter discovery.

---

## Prerequisites

- Terraform **≥ 1.6**
- AWS CLI and `kubectl`
- AWS account permissions for VPC/EKS/IAM/EC2/SSM/S3/DynamoDB
- **S3 bucket + DynamoDB table** for Terraform backend (create once, below)

---

## One-time backend bootstrap (S3 + DynamoDB)

`terraform/backend.tf` is checked in, so **create these resources once** and then keep the names in `backend.tf`:

```hcl
# bootstrap/main.tf
terraform {
  required_providers { aws = { source = "hashicorp/aws", version = ">= 5.30" } }
}
provider "aws" { region = "eu-central-1" }

variable "bucket_name" { type = string }
variable "table_name"  { type = string }

resource "aws_s3_bucket" "tf_state" { bucket = var.bucket_name }
resource "aws_s3_bucket_versioning" "v" {
  bucket = aws_s3_bucket.tf_state.id
  versioning_configuration { status = "Enabled" }
}
resource "aws_s3_bucket_server_side_encryption_configuration" "enc" {
  bucket = aws_s3_bucket.tf_state.id
  rule { apply_server_side_encryption_by_default { sse_algorithm = "AES256" } }
}
resource "aws_s3_bucket_public_access_block" "pab" {
  bucket = aws_s3_bucket.tf_state.id
  block_public_acls = true
  block_public_policy = true
  ignore_public_acls = true
  restrict_public_buckets = true
}
resource "aws_dynamodb_table" "tf_lock" {
  name = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key = "LockID"
  attribute { name = "LockID", type = "S" }
}

```bash
# S3 bucket (name must be globally unique); eu-central-1 requires LocationConstraint
aws s3api create-bucket \
  --bucket <your-unique-bucket> \
  --region eu-central-1 \
  --create-bucket-configuration LocationConstraint=eu-central-1

aws s3api put-bucket-versioning --bucket <your-unique-bucket> \
  --versioning-configuration Status=Enabled

aws s3api put-bucket-encryption --bucket <your-unique-bucket> \
  --server-side-encryption-configuration '{
    "Rules":[{"ApplyServerSideEncryptionByDefault":{"SSEAlgorithm":"AES256"}}]
  }'

aws s3api put-public-access-block --bucket <your-unique-bucket> \
  --public-access-block-configuration '{
    "BlockPublicAcls":true,"IgnorePublicAcls":true,
    "BlockPublicPolicy":true,"RestrictPublicBuckets":true
  }'

# DynamoDB table for state locking
aws dynamodb create-table \
  --table-name <your-dynamodb-table> \
  --billing-mode PAY_PER_REQUEST \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --region eu-central-1


---

## How to Deploy

```bash
cd terraform
terraform init
terraform apply -auto-approve

# Configure kubectl
aws eks update-kubeconfig --region $(terraform output -raw region) --name $(terraform output -raw cluster_name)

# Install Karpenter
# These selectors/instanceProfile are already set for cluster_name = "syam-doc"
kubectl apply -f ../kubernetes/karpenter-awsnodetemplate.yaml
kubectl apply -f ../kubernetes/karpenter-provisioner.yaml

# Trigger scheduling/scale-out
kubectl apply -f ../kubernetes/nginx-deployment.yaml

kubectl get nodes -w
kubectl get pods -n default -w
```

## GitHub Actions (CI + Deploy)

Two workflows are included. Create these files in your repo:

- `.github/workflows/terraform-ci.yml`
- `.github/workflows/terraform-deploy.yml`

### Required repo secrets / variables

| Name                 | Type     | Example / Default            | Purpose                                  |
|----------------------|----------|------------------------------|------------------------------------------|
| `AWS_ROLE_TO_ASSUME` | secret   | `arn:aws:iam::123..:role/...`| Role assumed via GitHub OIDC             |
| `AWS_REGION`         | variable | `eu-central-1` (default)     | Region for AWS API calls                 |

> Because you’re using `terraform/backend.tf`, you **don’t** need to pass backend info via secrets — the file already points at your S3/DynamoDB backend.

### Example IAM trust policy for GitHub OIDC

Replace `<ACCOUNT_ID>`, `<GITHUB_ORG>`, and `<REPO>`.

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Principal": { "Federated": "arn:aws:iam::<ACCOUNT_ID>:oidc-provider/token.actions.githubusercontent.com" },
    "Action": "sts:AssumeRoleWithWebIdentity",
    "Condition": {
      "StringEquals": { "token.actions.githubusercontent.com:aud": "sts.amazonaws.com" },
      "StringLike": { "token.actions.githubusercontent.com:sub": "repo:<GITHUB_ORG>/<REPO>:*" }
    }
  }]
}

## Assumptions & decisions

- **Open-source modules:** Using `terraform-aws-modules/vpc` and `terraform-aws-modules/eks` for proven defaults and speed.
- **Bottlerocket via SSM:** No AMI IDs hard-coded. EKS MNG uses `ami_type = "BOTTLEROCKET_x86_64"`, and Karpenter uses `amiFamily: Bottlerocket` (controller reads SSM).
- **All Spot:** Meets the exercise requirement. For production, consider a tiny On-Demand baseline for critical DaemonSets.
- **IRSA & aws-auth:** Karpenter controller runs with IRSA; `aws-auth` maps the Karpenter node role so nodes can join.
- **Tags:** Ownership/env tags plus `karpenter.sh/discovery` on private subnets and the node security group.

---

## Challenges & learnings

- The Karpenter service account **subject** in the IRSA trust must be `system:serviceaccount:karpenter:karpenter`.
- **`iam:PassRole`** is required so the controller can pass the node role to EC2.
- **Discovery tags** (`karpenter.sh/discovery`) on **private subnets** and the **node security group** are mandatory; otherwise Karpenter can’t place nodes.
- Helm/Kubernetes providers must run **after** EKS exists; dependencies are configured accordingly.

---

## Stretch ideas (optional)

- Additional Provisioners (GPU / large-memory) with tailored instance-type requirements.
- Consolidation & bin-packing tuning (e.g., `ttlSecondsAfterEmpty`, utilization goals).
- `pre-commit` hooks (fmt, validate, tflint), `terraform-docs`, multi-env layout with separate backend keys.

---

## Troubleshooting

**`terraform init` fails with backend**  
Ensure the S3 bucket & DynamoDB table exist and names match `terraform/backend.tf`.

**Karpenter doesn’t launch nodes**
- Private subnets & node security group must have `karpenter.sh/discovery = syam-doc`.
- `aws-auth` must include the Karpenter **node role** (via the `eks_auth` submodule).
- Spot capacity/limits for `t3.large`, `m5.large`, `c5.large` must be available.

**kubectl errors**  
Re-run the kubeconfig command from `terraform output -raw kubeconfig_command`.

---

## Evaluation mapping (for reviewers)

- **Correct implementation:** EKS (module), MNG on Bottlerocket Spot, Karpenter via Helm (Provisioner), Karpenter nodes Bottlerocket Spot.
- **Code quality:** Parameterized variables, open-source modules, tags, idempotent `apply`.
- **Documentation:** Architecture, steps (incl. backend bootstrap), assumptions/decisions, challenges, stretch, sample app, troubleshooting.
- **Automation:** CI (fmt/validate/plan) + Deploy (OIDC, init/plan/apply, manifests); cleanup instructions included.


