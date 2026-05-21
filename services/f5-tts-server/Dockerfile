# F5-TTS MLX Server - Apple Silicon only
# For Linux GPU deployment, use the official F5-TTS image instead:
#   ghcr.io/swivid/f5-tts:main
FROM python:3.12-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py .
COPY assets/voices ./assets/voices

ENV F5_HOST=0.0.0.0
ENV F5_PORT=8002
ENV F5_STEPS=8
ENV F5_METHOD=euler

EXPOSE 8002

CMD ["python", "main.py"]
