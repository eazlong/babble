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
HEALTHCHECK --interval=30s --timeout=5s CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8301/health')" || exit 1
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
