terraform {
  backend "s3" {
    bucket         = "aws-eu-central-1-dooc-dev"
    key            = "syam-doc/terraform.tfstate"
    region         = "eu-central-1"
    dynamodb_table = "aws-eu-central-1-dooc-dev"
    encrypt        = true
  }
}
