# AWS region nơi lab EC2 sẽ được tạo.
variable "aws_region" {
  type        = string
  description = "AWS region to deploy the Minikube lab host."
  default     = "ap-southeast-1"
}

# Prefix dùng để đặt tên resource, giúp dễ tìm và dễ xoá sau lab.
variable "project_name" {
  type        = string
  description = "Name prefix for AWS resources."
  default     = "cdo-week2"
}

# Instance type cần đủ CPU/RAM cho Minikube, ArgoCD và observability stack.
variable "instance_type" {
  type        = string
  description = "EC2 instance type for the lab host."
  default     = "t3.large"
}

# Ubuntu release lấy từ Canonical public SSM parameter.
variable "ubuntu_release" {
  type        = string
  description = "Ubuntu LTS release used for the EC2 lab host."
  default     = "24.04"
}

# CIDR được phép SSH vào EC2. Nên thay bằng IP public của bạn dạng x.x.x.x/32.
variable "allowed_ssh_cidr" {
  type        = string
  description = "CIDR block allowed to SSH into the EC2 instance."
  default     = "0.0.0.0/0"
}

# Kích thước root disk. Observability stack cần disk lớn hơn mặc định EC2.
variable "root_volume_size" {
  type        = number
  description = "Root EBS volume size in GiB."
  default     = 40
}

# Số CPU cấp cho Minikube. t3.large chỉ có 2 vCPU nên mặc định phải là 2.
variable "minikube_cpus" {
  type        = number
  description = "CPU count allocated to Minikube."
  default     = 2
}

# RAM cấp cho Minikube, tính bằng MB. Chừa lại một phần RAM cho OS và Docker.
variable "minikube_memory_mb" {
  type        = number
  description = "Memory allocated to Minikube in MB."
  default     = 6144
}

# Disk ảo của Minikube.
variable "minikube_disk_size" {
  type        = string
  description = "Disk size allocated to Minikube."
  default     = "25g"
}

# Thư mục local để Terraform ghi SSH private/public key.
variable "ssh_key_output_dir" {
  type        = string
  description = "Local directory where Terraform writes the generated SSH key pair."
  default     = "generated"
}
