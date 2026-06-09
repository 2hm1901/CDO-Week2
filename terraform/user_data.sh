#!/usr/bin/env bash
set -euxo pipefail

# Ghi log bootstrap để debug khi EC2 vừa được tạo.
exec > >(tee /var/log/cdo-week2-user-data.log) 2>&1

# Cài các gói nền tảng cần cho Docker, Minikube, kubectl, Helm và thao tác lab.
apt-get update
apt-get install -y ca-certificates curl gnupg git jq make conntrack apt-transport-https

# Cài Docker bằng script chính thức để Minikube có thể chạy driver docker.
curl -fsSL https://get.docker.com | sh
usermod -aG docker ubuntu
systemctl enable docker
systemctl start docker

# Cài Minikube binary.
curl -LO https://storage.googleapis.com/minikube/releases/latest/minikube-linux-amd64
install minikube-linux-amd64 /usr/local/bin/minikube
rm -f minikube-linux-amd64

# Cài kubectl bản stable mới nhất.
curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
install kubectl /usr/local/bin/kubectl
rm -f kubectl

# Cài Helm để deploy ArgoCD/Prometheus/Loki/OTel bằng chart.
curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# Start Minikube dưới user ubuntu để kubeconfig nằm ở /home/ubuntu/.kube/config.
sudo -iu ubuntu minikube start --driver=docker --cpus=4 --memory=8192 --disk-size=25g

# Chuẩn bị Helm repo thường dùng trong lab để người học có thể chạy ngay.
sudo -iu ubuntu helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
sudo -iu ubuntu helm repo add grafana https://grafana.github.io/helm-charts
sudo -iu ubuntu helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
sudo -iu ubuntu helm repo update

# Clone repo lab vào EC2 để có sẵn manifest và values file.
sudo -iu ubuntu git clone https://github.com/2hm1901/CDO-Week2.git /home/ubuntu/CDO-Week2 || true

# Marker file giúp biết user-data đã chạy xong.
date -Is > /var/log/cdo-week2-ready
