# CDO Week 2 Lab: GitOps, CI/CD, Observability, SLO

Repo: <https://github.com/2hm1901/CDO-Week2>

Lab này chạy trên AWS EC2. Terraform tạo một EC2 Ubuntu, user-data cài Docker, Minikube, kubectl, Helm và clone repo này vào máy. Trên Minikube, lab cài ArgoCD, deploy app BE/FE bằng GitOps, cài Prometheus/Grafana/Loki, rồi thực hành drift, rollback, SLO và burn rate alert.

## Mục Tiêu

- Cài ArgoCD trên Minikube chạy trong EC2 AWS.
- Deploy app backend có metrics endpoint, API thật, log stdout, endpoint tạo lỗi và latency giả lập.
- Lưu Kubernetes manifest trong GitOps repo.
- Dùng GitHub Actions validate manifest khi Pull Request.
- Sau khi merge vào `main`, build image, push GHCR và update image tag trong manifest.
- Để ArgoCD sync app từ Git vào cluster.
- Sửa manifest trực tiếp bằng `kubectl` để tạo drift và quan sát ArgoCD `OutOfSync`.
- Rollback đúng kiểu GitOps bằng `git revert`.
- Thử `kubectl rollout undo` và hiểu vì sao thao tác này tạo drift trong GitOps.
- Cài kube-prometheus-stack, Loki, Promtail.
- Query request rate, error rate, latency, logs.
- Tạo availability SLO, latency SLO và burn rate alert.
- Thực hành Progressive Delivery với Argo Rollouts canary, AnalysisTemplate, Prometheus query và abort criteria.

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
│       ├── be.yaml
│       ├── fe.yaml
│       ├── observability-prometheus.yaml
│       ├── observability-loki.yaml
│       └── observability-promtail.yaml
├── k8s/
│   └── apps/
│       ├── be/
│           ├── kustomization.yaml
│           ├── namespace.yaml
│           ├── deployment.yaml
│           ├── service.yaml
│           ├── service-monitor.yaml
│           └── prometheus-rule.yaml
│       ├── be-canary/
│           ├── kustomization.yaml
│           ├── delete-deployment.yaml
│           ├── rollout.yaml
│           └── analysis-template.yaml
│       └── fe/
│           ├── kustomization.yaml
│           ├── namespace.yaml
│           ├── configmap.yaml
│           ├── deployment.yaml
│           └── service.yaml
├── observability/
│   ├── kube-prometheus-stack-values.yaml
│   ├── loki-values.yaml
│   ├── promtail-values.yaml
│   └── grafana-dashboard-be.json
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
- [app/main.py](./app/main.py): app FastAPI BE, expose `/metrics`, `/api/products`, `/api/orders`, `/api/users/{id}`, `/api/checkout`, `/work`, `/fail`, `/healthz`, log request và tạo Prometheus metric.
- [app/Dockerfile](./app/Dockerfile): build container image cho BE app.
- [app/requirements.txt](./app/requirements.txt): dependency Python của app.
- [argocd/root.yaml](./argocd/root.yaml): root ArgoCD Application áp dụng pattern app-of-apps, trỏ vào thư mục `argocd/apps`.
- [argocd/apps/be.yaml](./argocd/apps/be.yaml): child ArgoCD Application trỏ vào repo GitHub và path `k8s/apps/be`.
- [argocd/apps/fe.yaml](./argocd/apps/fe.yaml): child ArgoCD Application thứ hai, trỏ vào path `k8s/apps/fe`.
- [argocd/apps/observability-prometheus.yaml](./argocd/apps/observability-prometheus.yaml): child ArgoCD Application cài `kube-prometheus-stack` bằng Helm chart và values trong repo.
- [argocd/apps/observability-loki.yaml](./argocd/apps/observability-loki.yaml): child ArgoCD Application cài Loki bằng Helm chart và values trong repo.
- [argocd/apps/observability-promtail.yaml](./argocd/apps/observability-promtail.yaml): child ArgoCD Application cài Promtail để thu log container và gửi vào Loki.
- [k8s/apps/be/kustomization.yaml](./k8s/apps/be/kustomization.yaml): Kustomize entrypoint, gom manifest BE và quản lý image tag.
- [k8s/apps/be/namespace.yaml](./k8s/apps/be/namespace.yaml): namespace `cdo-be`.
- [k8s/apps/be/deployment.yaml](./k8s/apps/be/deployment.yaml): Deployment chạy BE app.
- [k8s/apps/be/service.yaml](./k8s/apps/be/service.yaml): Service nội bộ cho BE.
- [k8s/apps/be/service-monitor.yaml](./k8s/apps/be/service-monitor.yaml): cấu hình Prometheus Operator scrape `/metrics`.
- [k8s/apps/be/prometheus-rule.yaml](./k8s/apps/be/prometheus-rule.yaml): recording rules và burn rate alerts cho availability/latency SLO.
- [k8s/apps/be-canary/kustomization.yaml](./k8s/apps/be-canary/kustomization.yaml): overlay Progressive Delivery, thay Deployment BE bằng Argo Rollouts `Rollout`.
- [k8s/apps/be-canary/rollout.yaml](./k8s/apps/be-canary/rollout.yaml): Rollout CRD định nghĩa canary steps 20% -> 50% -> 100%.
- [k8s/apps/be-canary/analysis-template.yaml](./k8s/apps/be-canary/analysis-template.yaml): AnalysisTemplate query Prometheus để abort canary nếu error rate hoặc burn rate vượt ngưỡng.
- [k8s/apps/fe/kustomization.yaml](./k8s/apps/fe/kustomization.yaml): Kustomize entrypoint cho FE app.
- [k8s/apps/fe/configmap.yaml](./k8s/apps/fe/configmap.yaml): HTML/JS frontend gọi BE API.
- [k8s/apps/fe/deployment.yaml](./k8s/apps/fe/deployment.yaml): Deployment nginx phục vụ FE.
- [k8s/apps/fe/service.yaml](./k8s/apps/fe/service.yaml): Service nội bộ cho FE.
- [observability/kube-prometheus-stack-values.yaml](./observability/kube-prometheus-stack-values.yaml): Helm values cài Prometheus, Alertmanager, Grafana, Loki datasource và email receiver cho SLO alerts.
- [observability/loki-values.yaml](./observability/loki-values.yaml): Helm values cài Loki mode SingleBinary cho lab.
- [observability/promtail-values.yaml](./observability/promtail-values.yaml): Helm values cài Promtail để đẩy container logs vào Loki.
- [observability/grafana-dashboard-be.json](./observability/grafana-dashboard-be.json): dashboard Grafana mẫu cho request rate, error rate, p95 latency và logs của BE.
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
- `tunnel_command`: lệnh SSH tunnel cho ArgoCD, Grafana, Prometheus, BE và FE local ports.
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
ghcr.io/2hm1901/cdo-be-app:<git-sha>
```

Lưu ý GHCR: package image cần public để Minikube pull được mà không cần secret. Nếu package đang private, vào GitHub package settings và đổi visibility sang public, hoặc tạo `imagePullSecret` trong namespace `cdo-be`.

Trong GitHub repo, vào:

- `Settings` -> `Actions` -> `General`.
- `Workflow permissions`: chọn `Read and write permissions`.

Workflow cần quyền này vì sau khi merge vào `main`, workflow sẽ commit lại file [k8s/apps/be/kustomization.yaml](./k8s/apps/be/kustomization.yaml) với image tag mới.

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

## 4. Deploy Observability Stack Bằng ArgoCD

Observability stack cũng được quản lý bằng ArgoCD app-of-apps. Root app sẽ tạo thêm ba child Application:

- `cdo-observability-prometheus`: cài Prometheus, Alertmanager, Grafana và CRD `ServiceMonitor`/`PrometheusRule`.
- `cdo-observability-loki`: cài Loki để lưu log.
- `cdo-observability-promtail`: cài Promtail để đọc container log trên node và gửi vào Loki.

Các app này dùng ArgoCD multi-source:

- Source 1 là Helm chart từ Helm repo public.
- Source 2 là Git repo này, dùng để lấy file values trong thư mục [observability](./observability).

Nếu cluster đã từng cài observability bằng Helm thủ công, nên gỡ các release cũ trước khi để ArgoCD quản lý để tránh lệch ownership giữa Helm CLI và ArgoCD:

```bash
cd ~/CDO-Week2
helm -n observability uninstall kube-prometheus-stack loki promtail
```

Lệnh trên có thể báo release không tồn tại nếu bạn đang chạy trên cluster mới. Khi đó có thể bỏ qua.

Trước khi sync Prometheus app, cấu hình email trong [observability/kube-prometheus-stack-values.yaml](./observability/kube-prometheus-stack-values.yaml):

```yaml
alertmanager:
  config:
    global:
      smtp_smarthost: smtp.gmail.com:587
      smtp_from: 2hm1901dev@gmail.com
      smtp_auth_username: 2hm1901dev@gmail.com
      smtp_auth_identity: 2hm1901dev@gmail.com
    receivers:
      - name: email-slo-alerts
        email_configs:
          - to: 2hm1901dev@gmail.com
```

Nếu dùng Gmail, tạo App Password trong Google Account và tạo Kubernetes Secret trên EC2. Không commit password này vào Git:

```bash
kubectl create namespace observability --dry-run=client -o yaml | kubectl apply -f -
kubectl -n observability create secret generic alertmanager-smtp \
  --from-literal=smtp-password='YOUR_GMAIL_APP_PASSWORD'
```

Alertmanager sẽ gửi email khi các alert SLO/burn-rate trong [k8s/apps/be/prometheus-rule.yaml](./k8s/apps/be/prometheus-rule.yaml) firing, ví dụ `CdoBeAvailabilityFastBurn`, `CdoBeAvailabilitySlowBurn`, `CdoBeLatencyFastBurn`, `CdoBeLatencySlowBurn`.

Apply root app nếu chưa apply:

```bash
kubectl apply -f argocd/root.yaml
```

Sync root app để ArgoCD tạo các child Application:

```bash
kubectl -n argocd patch application cdo-week2-root \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Sync các observability app bằng UI hoặc CLI:

```bash
kubectl -n argocd patch application cdo-observability-prometheus \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

kubectl -n argocd patch application cdo-observability-loki \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

kubectl -n argocd patch application cdo-observability-promtail \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Kiểm tra:

```bash
kubectl -n argocd get applications
kubectl -n observability get pods
```

Truy cập Grafana:

```bash
kubectl -n observability port-forward svc/kube-prometheus-stack-grafana 3000:80 > /tmp/grafana-port-forward.log 2>&1 &
```

Login Grafana:

- URL: `http://localhost:3000`
- User: `admin`
- Password: `admin123`

Import dashboard từ [observability/grafana-dashboard-be.json](./observability/grafana-dashboard-be.json).

## 5. Deploy App Bằng ArgoCD App-Of-Apps

Apply root ArgoCD Application:

```bash
cd ~/CDO-Week2
kubectl apply -f argocd/root.yaml
```

Root app sẽ đọc thư mục [argocd/apps](./argocd/apps) và tạo các child Application:

- `cdo-be-app`: backend API có metrics/logs/SLO.
- `cdo-fe-app`: frontend tĩnh phục vụ bằng nginx, gọi BE API để tạo traffic/logs.
- `cdo-observability-prometheus`: Prometheus, Alertmanager và Grafana.
- `cdo-observability-loki`: Loki.
- `cdo-observability-promtail`: Promtail.

Sync root app trước:

```bash
kubectl -n argocd patch application cdo-week2-root \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Sau đó sync từng child app bằng UI hoặc CLI. Nếu đã làm phần 4, chỉ cần sync hai app nghiệp vụ:

```bash
kubectl -n argocd patch application cdo-be-app \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'

kubectl -n argocd patch application cdo-fe-app \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Kiểm tra apps:

```bash
kubectl -n cdo-be get pods,svc
kubectl -n cdo-fe get pods,svc
kubectl -n argocd get applications
kubectl -n cdo-be port-forward svc/cdo-be-app 8081:80
```

Từ một terminal khác trên EC2:

```bash
curl http://localhost:8081/
curl http://localhost:8081/metrics
```

Kiểm tra FE app:

```bash
kubectl -n cdo-fe port-forward svc/cdo-fe-app 8082:80
curl http://localhost:8082/
```

Nếu mở FE từ browser máy local, giữ SSH tunnel từ Terraform đang chạy. FE ở `http://localhost:8082` và mặc định gọi BE ở `http://localhost:8081`.

## 6. Pull Request: Validate Manifest

Tạo branch:

```bash
git checkout -b test/replicas
```

Sửa [k8s/apps/be/deployment.yaml](./k8s/apps/be/deployment.yaml):

```yaml
replicas: 3
```

Commit, push và mở Pull Request:

```bash
git add k8s/apps/be/deployment.yaml
git commit -m "test: change be replicas"
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
- Commit lại image tag mới vào [k8s/apps/be/kustomization.yaml](./k8s/apps/be/kustomization.yaml).

Sau commit update manifest, ArgoCD phát hiện desired state mới. Nếu auto-sync chưa bật, bấm `Sync` trong UI hoặc dùng CLI ở bước trước.

## 8. Tạo Drift Bằng kubectl

Sửa trực tiếp live state trong cluster:

```bash
kubectl -n cdo-be scale deploy/cdo-be-app --replicas=1
kubectl -n cdo-be set env deploy/cdo-be-app DRIFT_TEST=true
```

Quan sát trong ArgoCD:

- App chuyển `OutOfSync`.
- Desired state là manifest trong Git.
- Live state là Deployment vừa bị sửa trực tiếp bằng `kubectl`.

Sync lại ArgoCD:

```bash
kubectl -n argocd patch application cdo-be-app \
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
kubectl -n cdo-be rollout history deploy/cdo-be-app
kubectl -n cdo-be rollout undo deploy/cdo-be-app
kubectl -n cdo-be rollout status deploy/cdo-be-app
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
sum(rate(http_requests_total{namespace="cdo-be"}[5m]))
```

PromQL error rate:

```promql
sum(rate(http_requests_total{namespace="cdo-be",status=~"5.."}[5m]))
/
sum(rate(http_requests_total{namespace="cdo-be"}[5m]))
```

PromQL p95 latency:

```promql
histogram_quantile(
  0.95,
  sum by (le) (rate(http_request_duration_seconds_bucket{namespace="cdo-be"}[5m]))
)
```

LogQL tất cả log app:

```logql
{namespace="cdo-be", app="cdo-be-app"}
```

LogQL chỉ lỗi:

```logql
{namespace="cdo-be", app="cdo-be-app"} |= "status=500"
```

## 12. SLO Và Burn Rate Alert

File [k8s/apps/be/prometheus-rule.yaml](./k8s/apps/be/prometheus-rule.yaml) định nghĩa:

- Availability SLO: 99% request không lỗi 5xx, error budget 1%.
- Latency SLO: 95% request có latency <= 500 ms, error budget 5%.
- Fast burn alert: cửa sổ 5 phút và 1 giờ.
- Slow burn alert: cửa sổ 30 phút và 6 giờ.

Alertmanager trong [observability/kube-prometheus-stack-values.yaml](./observability/kube-prometheus-stack-values.yaml) nhận các alert này và gửi email qua receiver `email-slo-alerts`:

- `severity="critical"`: gửi nhanh sau `10s`, repeat mỗi `30m`.
- `severity="warning"`: gửi sau `30s`, repeat mỗi `4h`.
- Khi alert resolved, email resolved cũng được gửi vì `send_resolved: true`.

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

## 13. Progressive Delivery: Canary Với Argo Rollouts

Phần này là extension sau khi bạn đã có:

- ArgoCD chạy.
- `cdo-be-app` và `cdo-fe-app` đã sync.
- Prometheus đang scrape BE metrics.

Tài liệu chính thức tham khảo:

- Argo Rollouts installation: <https://argo-rollouts.readthedocs.io/en/stable/installation/>
- Argo Rollouts analysis: <https://argo-rollouts.readthedocs.io/en/stable/features/analysis/>

### 13.1 Cài Argo Rollouts Controller

Chạy trên EC2:

```bash
kubectl create namespace argo-rollouts
kubectl apply -n argo-rollouts -f https://github.com/argoproj/argo-rollouts/releases/latest/download/install.yaml
kubectl -n argo-rollouts rollout status deploy/argo-rollouts
```

Tuỳ chọn cài CLI plugin:

```bash
curl -LO https://github.com/argoproj/argo-rollouts/releases/latest/download/kubectl-argo-rollouts-linux-amd64
chmod +x kubectl-argo-rollouts-linux-amd64
sudo mv kubectl-argo-rollouts-linux-amd64 /usr/local/bin/kubectl-argo-rollouts
kubectl argo rollouts version
```

### 13.2 Progressive Delivery Overlay

Repo có thêm overlay:

```text
k8s/apps/be-canary/
```

Overlay này dùng lại base BE từ [k8s/apps/be](./k8s/apps/be/kustomization.yaml), xoá Deployment thường và thay bằng:

- `Rollout`: [k8s/apps/be-canary/rollout.yaml](./k8s/apps/be-canary/rollout.yaml)
- `AnalysisTemplate`: [k8s/apps/be-canary/analysis-template.yaml](./k8s/apps/be-canary/analysis-template.yaml)

Canary steps:

```yaml
steps:
  - setWeight: 20
  - pause:
      duration: 60s
  - analysis:
      templates:
        - templateName: cdo-be-canary-analysis
  - setWeight: 50
  - pause:
      duration: 120s
  - analysis:
      templates:
        - templateName: cdo-be-canary-analysis
  - setWeight: 100
```

Lưu ý: lab này chưa cài service mesh/ingress traffic manager. Vì vậy `setWeight` điều chỉnh tỷ lệ pod canary tương đối theo replica count, còn Service `cdo-be-app` vẫn route đến cả stable và canary pods. Đây vẫn đủ để học Rollout CRD, AnalysisTemplate, promote/abort.

### 13.3 Chuyển BE App Sang Rollout Overlay

Sửa [argocd/apps/be.yaml](./argocd/apps/be.yaml):

```yaml
path: k8s/apps/be-canary
```

Commit và push:

```bash
git checkout -b rollout/be-canary
git add argocd/apps/be.yaml
git commit -m "test: enable be canary rollout"
git push origin rollout/be-canary
```

Mở PR, merge vào `main`, rồi trên EC2:

```bash
cd ~/CDO-Week2
git pull
```

Sync root app để ArgoCD cập nhật child Application:

```bash
kubectl -n argocd patch application cdo-week2-root \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD"}}}'
```

Sync BE app với prune để xoá Deployment cũ và thay bằng Rollout CRD:

```bash
kubectl -n argocd patch application cdo-be-app \
  --type merge \
  -p '{"operation":{"sync":{"revision":"HEAD","prune":true}}}'
```

Nếu sync bằng UI, tick **PRUNE** trong màn hình sync của `cdo-be-app`. Đây là bước quan trọng vì overlay canary xoá `Deployment/cdo-be-app` và thay bằng `Rollout/cdo-be-app`.

Kiểm tra:

```bash
kubectl -n cdo-be get rollout,rs,pods,svc
kubectl -n cdo-be describe rollout cdo-be-app
```

Nếu có CLI plugin:

```bash
kubectl argo rollouts get rollout cdo-be-app -n cdo-be --watch
```

### 13.4 AnalysisTemplate Và Abort Criteria

AnalysisTemplate query Prometheus service nội bộ:

```text
http://kube-prometheus-stack-prometheus.observability.svc.cluster.local:9090
```

Metric `error-rate` fail nếu 5xx ratio >= 5%:

```promql
(
  sum(rate(http_requests_total{namespace="cdo-be",status=~"5.."}[1m]))
  or vector(0)
)
/
clamp_min(sum(rate(http_requests_total{namespace="cdo-be"}[1m])), 0.001)
```

Metric `availability-burn-rate` dùng recording rule SLO:

```promql
(
  cdo_be:availability_error_ratio:5m
  or vector(0)
)
/
0.01
```

Abort criteria trong lab:

- `error-rate >= 0.05`: analysis fail.
- `availability-burn-rate >= 2`: analysis fail.
- `failureLimit: 1`: chỉ cần một lần fail là Rollout bị abort.

### 13.5 Tạo Canary Thành Công

Tạo một thay đổi BE lành mạnh, ví dụ sửa message trong `/` hoặc thêm log mới trong [app/main.py](./app/main.py). Merge vào `main`.

GitHub Actions sẽ:

- Build image `ghcr.io/2hm1901/cdo-be-app:<sha>`.
- Update image tag ở:
  - [k8s/apps/be/kustomization.yaml](./k8s/apps/be/kustomization.yaml)
  - [k8s/apps/be-canary/kustomization.yaml](./k8s/apps/be-canary/kustomization.yaml)

Sau khi ArgoCD sync, Rollout sẽ chạy:

```text
20% canary -> pause -> analysis -> 50% canary -> pause -> analysis -> 100%
```

Gửi traffic sạch trong lúc rollout:

```bash
for i in $(seq 1 300); do curl -s "http://localhost:8081/api/products" > /dev/null; done
for i in $(seq 1 100); do curl -s -X POST "http://localhost:8081/api/orders" > /dev/null; done
```

Promote thủ công nếu rollout đang pause:

```bash
kubectl argo rollouts promote cdo-be-app -n cdo-be
```

### 13.6 Tạo Canary Fail Và Quan Sát Abort

Trong lúc Rollout đang ở bước pause/analysis, tạo lỗi 5xx:

```bash
for i in $(seq 1 300); do curl -s "http://localhost:8081/fail" > /dev/null; done
```

Theo dõi:

```bash
kubectl -n cdo-be get analysisrun
kubectl -n cdo-be describe analysisrun
kubectl -n cdo-be describe rollout cdo-be-app
```

Nếu có CLI plugin:

```bash
kubectl argo rollouts get rollout cdo-be-app -n cdo-be --watch
```

Kỳ vọng:

- AnalysisRun fail vì Prometheus query thấy error rate/burn rate vượt ngưỡng.
- Rollout chuyển trạng thái degraded/aborted.
- Canary ReplicaSet không được promote lên stable.

Abort thủ công nếu cần:

```bash
kubectl argo rollouts abort cdo-be-app -n cdo-be
```

Rollback GitOps đúng cách:

```bash
git revert <bad_commit_sha>
git push origin main
```

Sau đó sync ArgoCD để Rollout quay về image/tag tốt trước đó.

### 13.7 Quay Lại Deployment Thường

Nếu muốn kết thúc phần Progressive Delivery và quay lại manifest thường, sửa [argocd/apps/be.yaml](./argocd/apps/be.yaml):

```yaml
path: k8s/apps/be
```

Commit, push và sync lại `cdo-be-app`.

## 14. Dọn AWS Resources

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
6. Argo Rollouts khác gì Deployment rolling update mặc định của Kubernetes?
7. Vì sao AnalysisTemplate nên query Prometheus thay vì chỉ dựa vào readiness probe?
8. Khi canary bị abort, rollback bằng Git khác gì abort trực tiếp bằng Rollouts CLI?
