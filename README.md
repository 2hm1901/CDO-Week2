# CDO Week 2 Lab: GitOps, CI/CD, Observability, SLO

Repo: <https://github.com/2hm1901/CDO-Week2>

Lab này chạy trên AWS EC2. Terraform tạo một EC2 Ubuntu, user-data cài Docker, Minikube, kubectl, Helm và clone repo này vào máy. Trên Minikube, lab cài ArgoCD, deploy app demo bằng GitOps, cài Prometheus/Grafana/Loki/OpenTelemetry Collector, rồi thực hành drift, rollback, SLO và burn rate alert.

## Mục Tiêu

- Cài ArgoCD trên Minikube chạy trong EC2 AWS.
- Deploy app backend demo có metrics endpoint, log stdout, endpoint tạo lỗi và latency giả lập.
- Lưu Kubernetes manifest trong GitOps repo.
- Dùng GitHub Actions validate manifest khi Pull Request.
- Sau khi merge vào `main`, build image, push GHCR và update image tag trong manifest.
- Để ArgoCD sync app từ Git vào cluster.
- Sửa manifest trực tiếp bằng `kubectl` để tạo drift và quan sát ArgoCD `OutOfSync`.
- Rollback đúng kiểu GitOps bằng `git revert`.
- Thử `kubectl rollout undo` và hiểu vì sao thao tác này tạo drift trong GitOps.
- Cài kube-prometheus-stack, Loki, Promtail, OpenTelemetry Collector.
- Query request rate, error rate, latency, logs.
- Tạo availability SLO, latency SLO và burn rate alert.

## Cấu Trúc Dự Án

```text
.
├── README.md
├── .gitignore
├── .github/
│   └── workflows/
│       ├── validate-pr.yaml
│       └── release-on-main.yaml
├── app/
│   ├── Dockerfile
│   ├── main.py
│   └── requirements.txt
├── argocd/
│   ├── root.yaml
│   └── apps/
│       └── demo.yaml
├── k8s/
│   └── apps/
│       └── demo/
│           ├── kustomization.yaml
│           ├── namespace.yaml
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── service-monitor.yaml
│           └── prometheus-rule.yaml
├── observability/
│   ├── kube-prometheus-stack-values.yaml
│   ├── loki-values.yaml
│   ├── promtail-values.yaml
│   ├── otel-collector-values.yaml
│   └── grafana-dashboard-demo.json
└── terraform/
    ├── versions.tf
    ├── variables.tf
    ├── main.tf
    ├── outputs.tf
    ├── user_data.sh
    └── terraform.tfvars.example
```

Ý nghĩa từng phần:

- [terraform/versions.tf](./terraform/versions.tf): khai báo Terraform version và AWS provider.
- [terraform/variables.tf](./terraform/variables.tf): khai báo biến đầu vào như region, instance type, CIDR được phép SSH và thư mục xuất SSH key.
- [terraform/main.tf](./terraform/main.tf): tạo SSH key bằng provider `tls`, ghi key về máy bằng provider `local`, tạo EC2, key pair, security group, chọn Ubuntu AMI và default VPC/subnet.
- [terraform/outputs.tf](./terraform/outputs.tf): in ra public IP, lệnh SSH, lệnh SSH tunnel và đường dẫn key được tạo.
- [terraform/user_data.sh](./terraform/user_data.sh): bootstrap EC2 bằng cách cài Docker, Minikube, kubectl, Helm, add Helm repo và clone repo lab.
- [terraform/terraform.tfvars.example](./terraform/terraform.tfvars.example): file mẫu để tạo `terraform.tfvars`.
- [app/main.py](./app/main.py): app FastAPI demo, expose `/metrics`, `/work`, `/fail`, `/healthz`, log request và tạo Prometheus metric.
- [app/Dockerfile](./app/Dockerfile): build container image cho app demo.
- [app/requirements.txt](./app/requirements.txt): dependency Python của app.
- [argocd/root.yaml](./argocd/root.yaml): root ArgoCD Application áp dụng pattern app-of-apps, trỏ vào thư mục `argocd/apps`.
- [argocd/apps/demo.yaml](./argocd/apps/demo.yaml): child ArgoCD Application trỏ vào repo GitHub và path `k8s/apps/demo`.
- [k8s/apps/demo/kustomization.yaml](./k8s/apps/demo/kustomization.yaml): Kustomize entrypoint, gom manifest và quản lý image tag.
- [k8s/apps/demo/namespace.yaml](./k8s/apps/demo/namespace.yaml): namespace `cdo-demo`.
- [k8s/apps/demo/deployment.yaml](./k8s/apps/demo/deployment.yaml): Deployment chạy app demo.
- [k8s/apps/demo/service.yaml](./k8s/apps/demo/service.yaml): Service nội bộ cho app.
- [k8s/apps/demo/service-monitor.yaml](./k8s/apps/demo/service-monitor.yaml): cấu hình Prometheus Operator scrape `/metrics`.
- [k8s/apps/demo/prometheus-rule.yaml](./k8s/apps/demo/prometheus-rule.yaml): recording rules và burn rate alerts cho availability/latency SLO.
- [observability/kube-prometheus-stack-values.yaml](./observability/kube-prometheus-stack-values.yaml): Helm values cài Prometheus, Alertmanager, Grafana và Loki datasource.
- [observability/loki-values.yaml](./observability/loki-values.yaml): Helm values cài Loki mode SingleBinary cho lab.
- [observability/promtail-values.yaml](./observability/promtail-values.yaml): Helm values cài Promtail để đẩy container logs vào Loki.
- [observability/otel-collector-values.yaml](./observability/otel-collector-values.yaml): Helm values cài OpenTelemetry Collector với OTLP receiver và debug exporter.
- [observability/grafana-dashboard-demo.json](./observability/grafana-dashboard-demo.json): dashboard Grafana mẫu cho request rate, error rate, p95 latency và logs.
- [.github/workflows/validate-pr.yaml](./.github/workflows/validate-pr.yaml): workflow chạy khi Pull Request, render Kustomize và validate manifest bằng kubeconform.
- [.github/workflows/release-on-main.yaml](./.github/workflows/release-on-main.yaml): workflow chạy khi merge vào `main`, build image, push GHCR và commit image tag mới vào manifest.
- [.gitignore](./.gitignore): bỏ qua cache Python, Terraform state, provider cache và file local.

## 1. Tạo AWS Resources Bằng Terraform

Yêu cầu trên máy local:

- AWS CLI đã cấu hình credential có quyền tạo EC2, security group, key pair.
- Terraform `>= 1.5.0`.

Bạn không cần chuẩn bị SSH key trước. Terraform dùng:

- Provider `tls` để tạo SSH private/public key.
- Provider `local` để ghi key về máy local tại `terraform/generated/`.

Lưu ý bảo mật: private key được ghi ra file local và cũng nằm trong Terraform state. Không commit `terraform.tfstate`, `terraform.tfvars` hoặc thư mục `terraform/generated/`.

Tạo file biến:

```bash
cd terraform
cp terraform.tfvars.example terraform.tfvars
```

Sửa `terraform.tfvars`:

```hcl
aws_region       = "ap-southeast-1"
project_name     = "cdo-week2"
instance_type    = "t3.large"
ubuntu_release   = "24.04"
allowed_ssh_cidr = "YOUR_PUBLIC_IP/32"
minikube_cpus    = 2
minikube_memory_mb = 6144
minikube_disk_size = "25g"
ssh_key_output_dir = "generated"
```

Lấy public IP local:

```bash
curl -s https://checkip.amazonaws.com
```

Apply:

```bash
terraform init
terraform fmt
terraform validate
terraform apply
```

Sau khi apply xong, Terraform output sẽ in ra:

- `public_ip`: IP public của EC2.
- `ssh_command`: lệnh SSH vào EC2.
- `tunnel_command`: lệnh SSH tunnel cho ArgoCD, Grafana, Prometheus.
- `private_key_path`: đường dẫn private key được tạo trên máy local.
- `public_key_path`: đường dẫn public key tương ứng.

Xem đường dẫn private key nếu cần:

```bash
terraform output -raw private_key_path
```

SSH vào EC2:

```bash
terraform output -raw ssh_command
$(terraform output -raw ssh_command)
```

Kiểm tra user-data đã chạy xong:

```bash
sudo tail -f /var/log/cdo-week2-user-data.log
test -f /var/log/cdo-week2-ready && echo ready
minikube status
kubectl get nodes
```

Nếu EC2 đã được tạo từ version cũ của repo và user-data fail với lỗi `RSRC_INSUFFICIENT_CORES`, chạy thủ công trên EC2:

```bash
sudo -iu ubuntu minikube start --driver=docker --cpus=2 --memory=6144 --disk-size=25g
sudo -iu ubuntu helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
sudo -iu ubuntu helm repo add grafana https://grafana.github.io/helm-charts
sudo -iu ubuntu helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
sudo -iu ubuntu helm repo update
sudo -iu ubuntu git clone https://github.com/2hm1901/CDO-Week2.git /home/ubuntu/CDO-Week2 || true
sudo touch /var/log/cdo-week2-ready
```

Repo đã được clone sẵn ở:

```bash
cd ~/CDO-Week2
```

## 2. Cấu Hình GitHub Actions

Repo này đã trỏ về:

```text
https://github.com/2hm1901/CDO-Week2
```

Image mặc định:

```text
ghcr.io/2hm1901/cdo-demo-app:<git-sha>
```

Lưu ý GHCR: package image cần public để Minikube pull được mà không cần secret. Nếu package đang private, vào GitHub package settings và đổi visibility sang public, hoặc tạo `imagePullSecret` trong namespace `cdo-demo`.

Trong GitHub repo, vào:

- `Settings` -> `Actions` -> `General`.
- `Workflow permissions`: chọn `Read and write permissions`.

Workflow cần quyền này vì sau khi merge vào `main`, workflow sẽ commit lại file [k8s/apps/demo/kustomization.yaml](./k8s/apps/demo/kustomization.yaml) với image tag mới.

## 3. Cài ArgoCD Trên Minikube

Chạy trên EC2:

```bash
cd ~/CDO-Week2

kubectl create namespace argocd
kubectl apply -n argocd -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl -n argocd rollout status deploy/argocd-server

kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath='{.data.password}' | base64 -d; echo
```

Port-forward ArgoCD:

```bash
kubectl -n argocd port-forward svc/argocd-server 8080:443
```

Từ máy local, mở tunnel:

```bash
cd terraform
$(terraform output -raw tunnel_command)
```

Đăng nhập ArgoCD:

- URL: `https://localhost:8080`
- User: `admin`
- Password: lấy từ secret `argocd-initial-admin-secret`.

## 4. Cài Observability Stack

Chạy trên EC2:

```bash
cd ~/CDO-Week2
kubectl create namespace observability
```

Cài Prometheus + Grafana:

```bash
helm upgrade --install kube-prometheus-stack prometheus-community/kube-prometheus-stack \
  -n observability \
  -f observability/kube-prometheus-stack-values.yaml
```

Cài Loki và Promtail:

```bash
helm upgrade --install loki grafana/loki \
  -n observability \
  -f observability/loki-values.yaml

helm upgrade --install promtail grafana/promtail \
  -n observability \
  -f observability/promtail-values.yaml
```

Cài OpenTelemetry Collector:

```bash
helm upgrade --install otel-collector open-telemetry/opentelemetry-collector \
  -n observability \
  -f observability/otel-collector-values.yaml
```

Kiểm tra:

```bash
kubectl -n observability get pods
```

Truy cập Grafana:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80
```

Từ máy local:

```bash
cd terraform
$(terraform output -raw tunnel_command)
```

Login Grafana:

- URL: `http://localhost:3000`
- User: `admin`
- Password: `admin123`

Import dashboard từ [observability/grafana-dashboard-demo.json](./observability/grafana-dashboard-demo.json).

## 5. Deploy App Bằng ArgoCD App-Of-Apps

Apply root ArgoCD Application:

```bash
cd ~/CDO-Week2
kubectl apply -f argocd/root.yaml
```

Root app sẽ đọc thư mục [argocd/apps](./argocd/apps) và tạo child Application `cdo-demo-app`. Sync root app trước:

```bash
kubectl -n argocd patch application cdo-week2-root \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Sau đó sync child app bằng UI hoặc CLI:

```bash
kubectl -n argocd patch application cdo-demo-app \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Kiểm tra app:

```bash
kubectl -n cdo-demo get pods,svc
kubectl -n argocd get applications
kubectl -n cdo-demo port-forward svc/cdo-demo-app 8081:80
```

Từ một terminal khác trên EC2:

```bash
curl http://localhost:8081/
curl http://localhost:8081/metrics
```

## 6. Pull Request: Validate Manifest

Tạo branch:

```bash
git checkout -b test/replicas
```

Sửa [k8s/apps/demo/deployment.yaml](./k8s/apps/demo/deployment.yaml):

```yaml
replicas: 3
```

Commit, push và mở Pull Request:

```bash
git add k8s/apps/demo/deployment.yaml
git commit -m "test: change demo replicas"
git push origin test/replicas
```

Workflow [validate-pr.yaml](./.github/workflows/validate-pr.yaml) sẽ:

- Render manifest bằng `kustomize build`.
- Validate YAML Kubernetes bằng `kubeconform`.

## 7. Merge: Build Image Và Update Manifest

Khi merge PR vào `main`, workflow [release-on-main.yaml](./.github/workflows/release-on-main.yaml) sẽ:

- Build Docker image từ [app/Dockerfile](./app/Dockerfile).
- Push image lên GHCR.
- Chạy `kustomize edit set image`.
- Commit lại image tag mới vào [k8s/apps/demo/kustomization.yaml](./k8s/apps/demo/kustomization.yaml).

Sau commit update manifest, ArgoCD phát hiện desired state mới. Nếu auto-sync chưa bật, bấm `Sync` trong UI hoặc dùng CLI ở bước trước.

## 8. Tạo Drift Bằng kubectl

Sửa trực tiếp live state trong cluster:

```bash
kubectl -n cdo-demo scale deploy/cdo-demo-app --replicas=1
kubectl -n cdo-demo set env deploy/cdo-demo-app DRIFT_TEST=true
```

Quan sát trong ArgoCD:

- App chuyển `OutOfSync`.
- Desired state là manifest trong Git.
- Live state là Deployment vừa bị sửa trực tiếp bằng `kubectl`.

Sync lại ArgoCD:

```bash
kubectl -n argocd patch application cdo-demo-app \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Kết quả: ArgoCD đưa cluster quay lại đúng trạng thái trong Git.

## 9. Rollback Bằng git revert

Giả sử một commit trên `main` làm app lỗi, rollback đúng kiểu GitOps:

```bash
git log --oneline
git revert <bad_commit_sha>
git push origin main
```

ArgoCD thấy commit revert là desired state mới và sync cluster về manifest trước đó.

Ý nghĩa:

- Git vẫn là source of truth.
- Có audit trail rõ ràng.
- Rollback có thể review qua PR nếu team yêu cầu.

## 10. Thử kubectl rollout undo

Chạy:

```bash
kubectl -n cdo-demo rollout history deploy/cdo-demo-app
kubectl -n cdo-demo rollout undo deploy/cdo-demo-app
kubectl -n cdo-demo rollout status deploy/cdo-demo-app
```

Điều xảy ra:

- Kubernetes rollback live Deployment về ReplicaSet trước đó.
- Git không đổi.
- ArgoCD thấy live state khác desired state nên app `OutOfSync`.
- Nếu ArgoCD sync hoặc auto-sync đang bật, ArgoCD sẽ đưa Deployment quay lại đúng manifest trong Git.

Kết luận: `kubectl rollout undo` hữu ích để chữa cháy nhanh, nhưng trong GitOps nó tạo drift. Rollback bền vững nên đi qua `git revert`.

## 11. Metrics, Logs, Latency

Gửi traffic:

```bash
for i in $(seq 1 200); do curl -s "http://localhost:8081/work?delay_ms=50" > /dev/null; done
for i in $(seq 1 30); do curl -s "http://localhost:8081/fail" > /dev/null; done
for i in $(seq 1 20); do curl -s "http://localhost:8081/work?delay_ms=900" > /dev/null; done
```

PromQL request rate:

```promql
sum(rate(http_requests_total{namespace="cdo-demo"}[5m]))
```

PromQL error rate:

```promql
sum(rate(http_requests_total{namespace="cdo-demo",status=~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="cdo-demo"}[5m]))
```

PromQL p95 latency:

```promql
histogram_quantile(
  0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{namespace="cdo-demo"}[5m]))
)
```

LogQL tất cả log app:

```logql
{namespace="cdo-demo", app="cdo-demo-app"}
```

LogQL chỉ lỗi:

```logql
{namespace="cdo-demo", app="cdo-demo-app"} |= "status=500"
```

## 12. SLO Và Burn Rate Alert

File [k8s/apps/demo/prometheus-rule.yaml](./k8s/apps/demo/prometheus-rule.yaml) định nghĩa:

- Availability SLO: 99% request không lỗi 5xx, error budget 1%.
- Latency SLO: 95% request có latency <= 500 ms, error budget 5%.
- Fast burn alert: cửa sổ 5 phút và 1 giờ.
- Slow burn alert: cửa sổ 30 phút và 6 giờ.

Tạo lỗi giả lập:

```bash
for i in $(seq 1 300); do curl -s "http://localhost:8081/fail" > /dev/null; done
```

Tạo latency cao:

```bash
for i in $(seq 1 300); do curl -s "http://localhost:8081/work?delay_ms=1200" > /dev/null; done
```

Truy cập Prometheus:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-prometheus 9090:9090
```

Từ máy local:

```bash
cd terraform
$(terraform output -raw tunnel_command)
```

Mở:

```text
http://localhost:9090/alerts
```

## 13. Dọn AWS Resources

Sau khi học xong, xoá EC2 và security group:

```bash
cd terraform
terraform destroy
```

Nếu có image GHCR không cần dùng nữa, xoá package trong GitHub Packages của repo/user.

## Câu Hỏi Review

1. Vì sao ArgoCD coi Git là desired state?
2. Drift khác gì rollout rollback?
3. Khi nào dùng `git revert`, khi nào tạm dùng `kubectl rollout undo`?
4. Workflow sau merge tự commit manifest thì cần tránh vòng lặp CI như thế nào?
5. Vì sao burn rate alert cần nhiều cửa sổ thay vì chỉ một ngưỡng error rate?
