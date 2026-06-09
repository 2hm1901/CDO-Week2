import logging
import random
import time

from fastapi import FastAPI, Request, Response
from prometheus_client import CONTENT_TYPE_LATEST, Counter, Histogram, generate_latest


# Log dạng key=value giúp Promtail/Loki query dễ hơn khi xem log ứng dụng.
logging.basicConfig(
    level=logging.INFO,
    format="time=%(asctime)s level=%(levelname)s message=%(message)s",
)

app = FastAPI(title="CDO Demo App")

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
    return {"service": "cdo-demo-app", "status": "ok"}


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
        return Response("synthetic failure\n", status_code=500)

    return {"status": "ok", "delay_ms": delay_ms}


@app.get("/fail")
def fail():
    # Endpoint tạo lỗi 500 có chủ đích để quan sát error rate và burn rate alert.
    return Response("synthetic failure\n", status_code=500)


@app.get("/metrics")
def metrics():
    # Prometheus scrape endpoint này thông qua ServiceMonitor.
    return Response(generate_latest(), media_type=CONTENT_TYPE_LATEST)
