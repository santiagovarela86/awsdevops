terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "3.55.0"
    }
  }

  backend "s3" {
  }
}

provider "aws" {
}
