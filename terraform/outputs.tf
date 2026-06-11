# Public IP dùng để SSH hoặc tạo SSH tunnel từ máy local.
output "public_ip" {
  description = "Public IP address of the EC2 lab host."
  value       = aws_instance.lab.public_ip
}

# Lệnh SSH tiện dùng sau khi apply xong.
output "ssh_command" {
  description = "SSH command for the EC2 lab host."
  value       = "ssh -i ${local_sensitive_file.private_key.filename} ubuntu@${aws_instance.lab.public_ip}"
}

# Ví dụ tunnel ArgoCD, Grafana, Prometheus và app ports qua SSH thay vì mở port public.
output "tunnel_command" {
  description = "SSH tunnel command for ArgoCD, Grafana, Prometheus, BE and FE local ports."
  value       = "ssh -i ${local_sensitive_file.private_key.filename} -L 8080:127.0.0.1:8080 -L 3000:127.0.0.1:3000 -L 9090:127.0.0.1:9090 -L 8081:127.0.0.1:8081 -L 8082:127.0.0.1:8082 ubuntu@${aws_instance.lab.public_ip}"
}

# Đường dẫn private key được tạo trên máy chạy Terraform.
output "private_key_path" {
  description = "Local path to the generated private SSH key."
  value       = local_sensitive_file.private_key.filename
  sensitive   = true
}

# Đường dẫn public key tương ứng, tiện để kiểm tra hoặc backup.
output "public_key_path" {
  description = "Local path to the generated public SSH key."
  value       = local_file.public_key.filename
}
