terraform {
  # Terraform version mới đủ hỗ trợ AWS provider 5.x ổn định.
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    # Provider tls tạo SSH key pair ngay trong Terraform state.
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
    # Provider local ghi private/public key ra máy đang chạy Terraform.
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }
}
