FROM python:3.11-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .

# --- CPU target (default) ---
FROM python:3.11-slim AS cpu
WORKDIR /app
COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --from=builder /app ./

ENV WHISPER_CACHE=/models/whisper
RUN mkdir -p /models/whisper

EXPOSE 8301
# 健康检查不仅看服务是否响应，还看 postprocess provider 是否真的可用：
# 2026-09-15 事故里意图判定整体失效，而 `docker ps` 一直显示 healthy（见计划文档 §15）。
# 这里读 /health 的 postprocess.status，为 error 时容器标记 unhealthy（不 5xx，避免重启风暴）。
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import json,urllib.request,sys; d=json.load(urllib.request.urlopen('http://127.0.0.1:8301/health')); sys.exit(1 if d.get('postprocess',{}).get('status')=='error' else 0)" || exit 1
CMD ["uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8301"]

# # --- GPU target (CUDA) ---
# FROM nvidia/cuda:12.6-runtime-ubuntu24.04 AS gpu
# RUN apt-get update && apt-get install -y --no-install-recommends \
#     python3.11 python3.11-venv python3-pip curl \
#     && rm -rf /var/lib/apt/lists/* \
#     && ln -sf /usr/bin/python3.11 /usr/bin/python3 \
#     && ln -sf /usr/bin/python3.11 /usr/bin/python

# WORKDIR /app
# COPY --from=builder /usr/local/lib/python3.11/site-packages /usr/local/lib/python3.11/site-packages
# COPY --from=builder /usr/local/bin /usr/local/bin
# COPY --from=builder /app ./

# ENV WHISPER_CACHE=/models/whisper
# ENV WHISPER_DEVICE=cuda
# ENV WHISPER_COMPUTE_TYPE=float16
# RUN mkdir -p /models/whisper

# EXPOSE 8301
# HEALTHCHECK --interval=30s --timeout=5s CMD curl -f http://127.0.0.1:8301/health || exit 1
# CMD ["python3.11", "-m", "uvicorn", "src.main:app", "--host", "0.0.0.0", "--port", "8301"]
