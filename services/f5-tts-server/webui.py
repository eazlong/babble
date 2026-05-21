"""Simple HTML-based WebUI for F5-TTS MLX (no threading issues)."""

import base64
import io
import os
import tempfile
import time

import mlx.core as mx
import numpy as np
import soundfile as sf
from fastapi import FastAPI, Form, UploadFile
from fastapi.responses import HTMLResponse, FileResponse
from f5_tts_mlx.cfm import F5TTS
from f5_tts_mlx.utils import convert_char_to_pinyin

SAMPLE_RATE = 24_000
TARGET_RMS = 0.1

# Load model once at startup
print("Loading F5-TTS MLX model...")
start = time.time()
model = F5TTS.from_pretrained("lucasnewman/f5-tts-mlx", quantization_bits=4)
print(f"Model loaded in {time.time() - start:.1f}s")

app = FastAPI(title="F5-TTS WebUI")

HTML_PAGE = """
<!DOCTYPE html>
<html lang="zh">
<head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>F5-TTS MLX</title>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body { font-family: system-ui, sans-serif; max-width: 800px; margin: 2rem auto; padding: 0 1rem; background: #f5f5f5; }
h1 { text-align: center; margin-bottom: 1rem; font-size: 1.5rem; }
.card { background: #fff; border-radius: 12px; padding: 1.5rem; margin-bottom: 1rem; box-shadow: 0 1px 3px rgba(0,0,0,0.1); }
label { display: block; font-weight: 600; margin-bottom: 0.3rem; font-size: 0.9rem; color: #555; }
input[type=text], textarea { width: 100%; padding: 0.5rem; border: 1px solid #ddd; border-radius: 6px; font-size: 1rem; }
textarea { resize: vertical; min-height: 60px; }
button { width: 100%; padding: 0.7rem; background: #2563eb; color: #fff; border: none; border-radius: 8px; font-size: 1rem; cursor: pointer; }
button:disabled { background: #93a3b8; cursor: not-allowed; }
button:hover:not(:disabled) { background: #1d4ed8; }
audio { width: 100%; margin-top: 0.5rem; }
.status { text-align: center; padding: 0.5rem; font-size: 0.85rem; color: #666; }
.advanced { max-height: 0; overflow: hidden; transition: max-height 0.3s; }
.advanced.open { max-height: 200px; }
.toggle { background: none; color: #2563eb; font-size: 0.85rem; padding: 0.3rem; width: auto; }
.row { display: flex; gap: 0.5rem; }
.row > div { flex: 1; }
input[type=range] { width: 100%; }
</style>
</head>
<body>
<h1>F5-TTS MLX WebUI</h1>

<div class="card">
<form id="ttsForm" action="/synthesize" method="post" enctype="multipart/form-data">
  <div style="margin-bottom:0.8rem">
    <label>参考音频（3-15秒）</label>
    <input type="file" name="ref_audio" accept="audio/*" required>
  </div>
  <div style="margin-bottom:0.8rem">
    <label>参考音频文本</label>
    <input type="text" name="ref_text" value="Hello, I am the forest spirit." placeholder="参考音频中说的话">
  </div>
  <div style="margin-bottom:1rem">
    <label>生成文本</label>
    <textarea name="gen_text" placeholder="想要合成的文本">Hello, young traveler! Welcome to the magical forest.</textarea>
  </div>

  <button class="toggle" type="button" onclick="document.getElementById('adv').classList.toggle('open')">高级参数 ▼</button>
  <div class="advanced" id="adv">
    <div class="row">
      <div><label>步数: <span id="stepsVal">8</span></label><input type="range" name="steps" min="2" max="32" value="8" step="2" oninput="document.getElementById('stepsVal').textContent=this.value"></div>
      <div><label>语速: <span id="speedVal">1.0</span></label><input type="range" name="speed" min="0.5" max="2.0" value="1.0" step="0.1" oninput="document.getElementById('speedVal').textContent=this.value"></div>
    </div>
    <div class="row">
      <div><label>方法</label><select name="method" style="width:100%;padding:0.3rem"><option value="euler">euler</option><option value="midpoint">midpoint</option><option value="rk4">rk4</option></select></div>
      <div><label>CFG: <span id="cfgVal">2.0</span></label><input type="range" name="cfg" min="1.0" max="5.0" value="2.0" step="0.5" oninput="document.getElementById('cfgVal').textContent=this.value"></div>
    </div>
  </div>

  <div style="height:0.8rem"></div>
  <button type="submit" id="submitBtn">生成语音</button>
</form>
</div>

<div class="card" id="resultCard" style="display:none">
  <div class="status" id="status"></div>
  <audio id="audio" controls autoplay></audio>
</div>

<script>
document.getElementById('ttsForm').addEventListener('submit', async function(e) {
  e.preventDefault();
  const btn = document.getElementById('submitBtn');
  btn.disabled = true;
  btn.textContent = '生成中...';

  const fd = new FormData(this);
  try {
    const resp = await fetch('/synthesize', { method: 'POST', body: fd });
    if (!resp.ok) { const t = await resp.text(); alert('Error: ' + t); return; }
    const data = await resp.json();
    document.getElementById('resultCard').style.display = '';
    document.getElementById('status').textContent = data.info;
    document.getElementById('audio').src = 'data:audio/wav;base64,' + data.audio;
  } finally {
    btn.disabled = false;
    btn.textContent = '生成语音';
  }
});
</script>
</body>
</html>
"""


@app.get("/", response_class=HTMLResponse)
async def index():
    return HTML_PAGE


@app.post("/synthesize")
async def synthesize(
    ref_audio: UploadFile,
    ref_text: str = Form("Hello, I am the forest spirit."),
    gen_text: str = Form(...),
    steps: int = Form(8),
    method: str = Form("euler"),
    cfg: float = Form(2.0),
    speed: float = Form(1.0),
):
    # Read uploaded audio
    audio_bytes = await ref_audio.read()
    audio_np, sr = sf.read(io.BytesIO(audio_bytes))
    audio_np = audio_np.astype(np.float32)
    if sr != SAMPLE_RATE:
        from scipy.signal import resample
        audio_np = resample(audio_np, int(len(audio_np) * SAMPLE_RATE / sr))

    audio_np = audio_np.flatten()
    rms = float(np.sqrt(np.mean(np.square(audio_np))))
    if rms < TARGET_RMS:
        audio_np = audio_np * TARGET_RMS / rms

    audio_mx = mx.array(audio_np)
    audio_mx = mx.expand_dims(audio_mx, axis=0)

    full_text = convert_char_to_pinyin([ref_text + " " + gen_text])

    start_t = time.time()
    wave, _ = model.sample(
        audio_mx,
        text=full_text,
        duration=None,
        steps=steps,
        method=method,
        speed=speed,
        cfg_strength=cfg,
        sway_sampling_coef=-1.0,
    )

    wave = wave[audio_np.shape[0]:]
    mx.eval(wave)

    elapsed = time.time() - start_t
    duration_s = wave.shape[0] / SAMPLE_RATE

    # Encode as base64 WAV
    wav_buf = io.BytesIO()
    sf.write(wav_buf, np.array(wave), SAMPLE_RATE, format="WAV")
    audio_b64 = base64.b64encode(wav_buf.getvalue()).decode()

    return {
        "audio": audio_b64,
        "info": f"生成 {duration_s:.2f}s 音频，用时 {elapsed:.2f}s (RTF={elapsed/max(duration_s,0.01):.2f})",
    }


if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="127.0.0.1", port=7860)
