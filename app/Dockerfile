# Image Python slim đủ nhẹ cho lab nhưng vẫn dễ debug.
FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

WORKDIR /app

# Cài dependency trước khi copy source để Docker layer cache hiệu quả hơn.
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .

EXPOSE 8080
# Uvicorn serve FastAPI trên port container 8080.
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8080"]
