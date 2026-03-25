FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PORT=8080
ENV CACHE_DIR=/var/cache/registry-gateway
ENV CACHE_TTL_SECONDS=300
ENV UPSTREAM_TIMEOUT_SECONDS=10
ENV UPSTREAM_RETRY_COUNT=1
ENV UPSTREAM_RETRY_BACKOFF_SECONDS=0.2

WORKDIR /app

COPY server.py /app/server.py

RUN mkdir -p "${CACHE_DIR}"

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD python3 -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/healthz', timeout=3).read()"

CMD ["python3", "/app/server.py"]
