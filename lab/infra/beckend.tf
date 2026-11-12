terraform {
  required_version = ">= 1.10"
  required_providers {
    aws = { source = "hashicorp/aws", version = ">= 5.0" }
  }
  backend "s3" {
    bucket       = "its-lab-tfstate-vanguard-2026"
    key          = "lab/terraform.tfstate"
    region       = var.region
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" { 
    region = var.region 
}