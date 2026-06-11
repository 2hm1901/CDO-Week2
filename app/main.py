import logging
import random
import time

from fastapi import FastAPI, Request, Response
from fastapi.middleware.cors import CORSMiddleware
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest


# Log dạng key=value giúp Promtail/Loki query dễ hơn khi xem log ứng dụng.
logging.basicConfig(
    level=logging.INFO,
    format="time=%(asctime)s level=%(levelname)s message=%(message)s",
)

app = FastAPI(title="CDO Backend API")

# FE chạy qua port-forward khác port BE, nên bật CORS cho lab browser local.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Counter chính để tính request rate, error rate và availability SLO.
REQUESTS = Counter(
    "http_requests_total",
    "Total HTTP requests",
    ["method", "path", "status"],
)

# Histogram dùng để tính p95 latency và latency SLO theo bucket <= 500 ms.
LATENCY = Histogram(
    "http_request_duration_seconds",
    "HTTP request latency in seconds",
    ["method", "path"],
    buckets=(0.025, 0.05, 0.1, 0.25, 0.5, 1, 2, 5),
)


@app.middleware("http")
async def metrics_middleware(request: Request, call_next):
    # Middleware đo toàn bộ request, kể cả request trả lỗi.
    start = time.perf_counter()
    status = "500"
    path = request.url.path

    try:
        response = await call_next(request)
        status = str(response.status_code)
        return response
    finally:
        # Luôn ghi metric/log trong finally để lỗi runtime vẫn xuất hiện trong telemetry.
        duration = time.perf_counter() - start
        REQUESTS.labels(request.method, path, status).inc()
        LATENCY.labels(request.method, path).observe(duration)
        logging.info(
            "method=%s path=%s status=%s duration_ms=%.2f",
            request.method,
            path,
            status,
            duration * 1000,
        )


@app.get("/")
def root():
    # Endpoint đơn giản để kiểm tra app đang phục vụ request.
    logging.info("event=root_check service=cdo-be-app")
    return {"service": "cdo-be-app", "status": "ok"}


@app.get("/healthz")
def healthz():
    # Kubernetes liveness/readiness probe gọi endpoint này.
    return {"status": "healthy"}


@app.get("/work")
def work(delay_ms: int = 100, fail_percent: int = 0):
    # Clamp input để người học có thể giả lập latency/lỗi nhưng không treo app quá lâu.
    delay_ms = max(0, min(delay_ms, 5000))
    fail_percent = max(0, min(fail_percent, 100))
    time.sleep(delay_ms / 1000)

    if random.randint(1, 100) <= fail_percent:
        logging.error("event=work_failed delay_ms=%s fail_percent=%s", delay_ms, fail_percent)
        return Response("synthetic failure\n", status_code=500)

    logging.info("event=work_completed delay_ms=%s", delay_ms)
    return {"status": "ok", "delay_ms": delay_ms}


@app.get("/fail")
def fail():
    # Endpoint tạo lỗi 500 có chủ đích để quan sát error rate và burn rate alert.
    logging.error("event=forced_failure reason=manual_test")
    return Response("synthetic failure\n", status_code=500)


@app.get("/api/products")
def list_products():
    # API đọc dữ liệu giả lập để FE có request thật và tạo access log đều đặn.
    products = [
        {"id": "p-100", "name": "GitOps Starter", "price": 19},
        {"id": "p-200", "name": "Observability Pack", "price": 29},
        {"id": "p-300", "name": "SLO Workbook", "price": 15},
    ]
    logging.info("event=products_listed count=%s", len(products))
    return {"items": products}


@app.post("/api/orders")
def create_order():
    # API ghi dữ liệu giả lập, có latency nhẹ để latency metric có ý nghĩa hơn.
    time.sleep(random.uniform(0.05, 0.25))
    order_id = f"ord-{random.randint(1000, 9999)}"
    logging.info("event=order_created order_id=%s", order_id)
    return {"order_id": order_id, "status": "created"}


@app.get("/api/users/{user_id}")
def get_user(user_id: int):
    # Tạo lỗi có chủ đích cho user_id chia hết cho 5 để dễ sinh error logs.
    if user_id % 5 == 0:
        logging.error("event=user_lookup_failed user_id=%s reason=not_found", user_id)
        return Response("user not found\n", status_code=404)

    logging.info("event=user_lookup user_id=%s", user_id)
    return {"id": user_id, "name": f"user-{user_id}", "tier": "lab"}


@app.post("/api/checkout")
def checkout(fail_percent: int = 20):
    # API giả lập nghiệp vụ có xác suất lỗi để quan sát error rate/logs/alerts.
    fail_percent = max(0, min(fail_percent, 100))
    time.sleep(random.uniform(0.1, 0.6))

    if random.randint(1, 100) <= fail_percent:
        logging.error("event=checkout_failed fail_percent=%s", fail_percent)
        return Response("checkout failed\n", status_code=500)

    logging.info("event=checkout_completed")
    return {"status": "paid"}


@app.get("/metrics")
def metrics():
    # Prometheus scrape endpoint này thông qua ServiceMonitor.
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
