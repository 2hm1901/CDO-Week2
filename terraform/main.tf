provider "aws" {
  region = var.aws_region
}

locals {
  # path.module giúp đường dẫn key ổn định dù chạy Terraform từ thư mục nào.
  ssh_key_name       = "${var.project_name}-key"
  ssh_key_output_dir = "${path.module}/${var.ssh_key_output_dir}"
  private_key_path   = "${local.ssh_key_output_dir}/${local.ssh_key_name}.pem"
  public_key_path    = "${local.ssh_key_output_dir}/${local.ssh_key_name}.pub"
}

# Lấy default VPC/subnet để lab gọn và không phải dựng network phức tạp.
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

# Ubuntu LTS chính thức từ Canonical, dùng amd64 cho t3.large.
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"]

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-*-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Tạo SSH key pair bằng tls provider để người học không cần chuẩn bị key trước.
resource "tls_private_key" "lab" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# Ghi private key về máy local với permission 0600 để SSH chấp nhận file key.
resource "local_sensitive_file" "private_key" {
  filename        = local.private_key_path
  content         = tls_private_key.lab.private_key_pem
  file_permission = "0600"
}

# Ghi public key để người học có thể kiểm tra hoặc tái sử dụng khi cần.
resource "local_file" "public_key" {
  filename        = local.public_key_path
  content         = tls_private_key.lab.public_key_openssh
  file_permission = "0644"
}

# AWS key pair dùng public key do Terraform vừa tạo.
resource "aws_key_pair" "lab" {
  key_name   = local.ssh_key_name
  public_key = tls_private_key.lab.public_key_openssh
}

# Security group chỉ mở SSH. ArgoCD/Grafana/Prometheus nên truy cập bằng SSH tunnel.
resource "aws_security_group" "lab" {
  name        = "${var.project_name}-sg"
  description = "Security group for CDO Week 2 Minikube lab"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "SSH from allowed CIDR"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.allowed_ssh_cidr]
  }

  egress {
    description = "Allow outbound internet access for package and image downloads"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name    = "${var.project_name}-sg"
    Project = var.project_name
  }
}

# EC2 host chạy Docker + Minikube. User data sẽ bootstrap các tool cần cho lab.
resource "aws_instance" "lab" {
  ami                         = data.aws_ami.ubuntu.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.lab.id]
  key_name                    = aws_key_pair.lab.key_name
  associate_public_ip_address = true
  user_data                   = file("${path.module}/user_data.sh")

  root_block_device {
    volume_size = var.root_volume_size
    volume_type = "gp3"
  }

  tags = {
    Name    = "${var.project_name}-minikube"
    Project = var.project_name
  }
}
