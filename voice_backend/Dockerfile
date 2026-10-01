FROM node:22-bookworm-slim AS node-runtime
FROM python:3.13-slim-bookworm

# The Python API owns HTTP, auth, storage, and provider proxying. This small Node
# runtime executes the existing, validated planner contract without an n8n server.
COPY --from=node-runtime /usr/local/bin/node /usr/local/bin/node
RUN apt-get update && apt-get install -y --no-install-recommends libstdc++6 \
    && rm -rf /var/lib/apt/lists/* \
    && groupadd --gid 10001 mixroom && useradd --uid 10001 --gid mixroom --no-create-home mixroom \
    && mkdir -p /app /data && chown mixroom:mixroom /app /data
WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt
COPY --chown=mixroom:mixroom mixroom_backend ./mixroom_backend
COPY --chown=mixroom:mixroom planner ./planner
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 MIXROOM_DATA_DIR=/data
USER 10001:10001
EXPOSE 8765
HEALTHCHECK --interval=15s --timeout=3s --start-period=10s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8765/health', timeout=2)"
CMD ["uvicorn", "mixroom_backend.app:app", "--host", "0.0.0.0", "--port", "8765", "--workers", "1", "--no-access-log", "--no-proxy-headers"]
