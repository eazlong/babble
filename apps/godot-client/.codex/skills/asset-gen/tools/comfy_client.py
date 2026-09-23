#!/usr/bin/env python3
"""ComfyUI API client — local Qwen-Image 2.1 backend for asset-gen.

Why this exists
---------------
`asset_gen.py`'s other backends speak the Gemini SDK, the xAI SDK, or the
DashScope async-task protocol (`POST /services/aigc/text2image/image-synthesis`
then poll `GET /tasks/{id}`). A locally deployed Qwen-Image runs inside
**ComfyUI**, which speaks none of those: it takes a node graph at `POST /prompt`,
reports progress in `GET /history/{prompt_id}`, and serves pixels from
`GET /view`. This module is that translation layer, so asset-gen can use local
Qwen-Image instead of a paid API.

Verified against (2026-09-22)
-----------------------------
ComfyUI 0.30.0 on nv241, reachable at http://1.14.203.171:24181 (public) or via
SSH tunnel `ssh -N -L 18081:127.0.0.1:8081 -p 24122 netgpu@wgma.bbxyard.com`.

    UnetLoaderGGUF        unet_name = qwen_image_2.1_Q6_K.gguf      (only option)
    CLIPLoader            clip_name = qwen3vl_8b_int8_convrot.safetensors
                          type      = qwen_image                    (in the 29-value enum)
    VAELoader             vae_name  = qwen_image_2.1_vae_bf16.safetensors
    TextEncodeQwenImage21 outputs   = positive(0) / negative(1) / latent(2)

Qwen-Image 2.1 renders true RGBA when the prompt is wrapped in the transparency
sentence (see TRANSPARENT_TEMPLATE), so sprite work needs no background removal.

Reference-image editing (added 2026-09-23)
-----------------------------------------
Qwen-Image 2.1 does image-to-image *editing* by splicing the reference into the
text encoder's sequence and handing the VAE latents to the sampler as
`reference_latents`. `TextEncodeQwenImage21` is the node that does it, and it
also emits the empty latent to sample from, so an edit graph is the t2i graph
with the reference wired in.

Two things bit us and are worth not re-learning:

1. **The Autogrow key is a top-level input literally named `images.image_1`.**
   The reference images are an `io.Autogrow` whose 16 named slots
   (`image_1`..`image_16`) live in the *node's input dict*, not inside an
   `"images"` value: `{"images.image_1": ["10", 0]}`. Passing
   `{"images": {"image_1": [...]}}`, `{"images": {"images.image_1": [...]}}` or
   `{"images": ["10", 0]}` all validate **without error** and are then silently
   dropped, so the job runs as a plain text-to-image and you get a plausible
   picture of the wrong thing. `resolution=0` is the tell: with a reference the
   output matches that reference's size (rounded to 32), without one it is the
   `resolution or 1024` square.
2. **`resolution` is a pixel budget, not a dimension.** 0 keeps each reference
   at its own size rounded to a multiple of 32; >0 resizes to about
   `resolution x resolution` preserving aspect, and the output follows
   `image_1`. There is no separate width/height.

CLI
---
    python3 comfy_client.py --prompt "..." -o out.png [--size 512] [--transparent]
    python3 comfy_client.py --prompt "..." --ref in.png -o out.png   # edit/isolate
"""

from __future__ import annotations

import argparse
import json
import os
import random
import sys
import time
from pathlib import Path
from urllib.parse import urlencode

import requests

DEFAULT_COMFY_URL = "http://1.14.203.171:24181"
DEFAULT_UNET = "qwen_image_2.1_Q6_K.gguf"
DEFAULT_CLIP = "qwen3vl_8b_int8_convrot.safetensors"
DEFAULT_CLIP_TYPE = "qwen_image"
DEFAULT_VAE = "qwen_image_2.1_vae_bf16.safetensors"

# The official Qwen-Image 2.1 path: cfg 1.0, euler, ~25 steps (template default).
DEFAULT_STEPS = 25
DEFAULT_CFG = 1.0
DEFAULT_SAMPLER = "euler"
DEFAULT_SCHEDULER = "simple"
DEFAULT_POLL_INTERVAL_SECONDS = 4
DEFAULT_TIMEOUT_SECONDS = 1800

TRANSPARENT_TEMPLATE = (
    "This is an RGBA format image with transparency. {subject}. "
    "The image has an alpha channel and a transparent background."
)


def base_url() -> str:
    return os.environ.get("COMFY_URL", DEFAULT_COMFY_URL).rstrip("/")


def wrap_transparent(subject: str) -> str:
    """Qwen-Image 2.1 renders alpha only when the prompt asks for RGBA explicitly."""
    return TRANSPARENT_TEMPLATE.format(subject=subject.strip().rstrip("."))


def build_t2i_graph(
    prompt: str,
    negative_prompt: str = "",
    width: int = 512,
    height: int = 512,
    seed: int | None = None,
    steps: int = DEFAULT_STEPS,
    cfg: float = DEFAULT_CFG,
    sampler_name: str = DEFAULT_SAMPLER,
    scheduler: str = DEFAULT_SCHEDULER,
    filename_prefix: str = "asset_gen",
    unet_name: str | None = None,
    clip_name: str | None = None,
    clip_type: str = DEFAULT_CLIP_TYPE,
    vae_name: str | None = None,
) -> dict:
    """Build an API-format node graph (what POST /prompt expects under "prompt")."""
    unet_name = unet_name or os.environ.get("COMFY_UNET", DEFAULT_UNET)
    clip_name = clip_name or os.environ.get("COMFY_CLIP", DEFAULT_CLIP)
    vae_name = vae_name or os.environ.get("COMFY_VAE", DEFAULT_VAE)
    if seed is None:
        seed = random.randint(0, 2**31 - 1)

    return {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": unet_name}},
        "2": {
            "class_type": "CLIPLoader",
            "inputs": {"clip_name": clip_name, "type": clip_type},
        },
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": vae_name}},
        "4": {
            "class_type": "TextEncodeQwenImage21",
            "inputs": {
                "clip": ["2", 0],
                "prompt": prompt,
                "negative_prompt": negative_prompt,
                "resolution": width,
                "images": [],
            },
        },
        "5": {
            "class_type": "EmptyLatentImage",
            "inputs": {"width": width, "height": height, "batch_size": 1},
        },
        "6": {
            "class_type": "KSampler",
            "inputs": {
                "model": ["1", 0],
                "seed": seed,
                "steps": steps,
                "cfg": cfg,
                "sampler_name": sampler_name,
                "scheduler": scheduler,
                "positive": ["4", 0],
                "negative": ["4", 1],
                "latent_image": ["5", 0],
                "denoise": 1.0,
            },
        },
        "7": {
            "class_type": "VAEDecode",
            "inputs": {"samples": ["6", 0], "vae": ["3", 0]},
        },
        "8": {
            "class_type": "SaveImage",
            "inputs": {"images": ["7", 0], "filename_prefix": filename_prefix},
        },
    }


def submit(graph: dict, client_id: str = "asset-gen") -> str:
    url = f"{base_url()}/prompt"
    resp = requests.post(
        url, json={"prompt": graph, "client_id": client_id}, timeout=60
    )
    if not resp.ok:
        raise RuntimeError(f"ComfyUI /prompt HTTP {resp.status_code}: {resp.text[:500]}")
    data = resp.json()
    prompt_id = data.get("prompt_id")
    if not prompt_id:
        raise RuntimeError(f"ComfyUI /prompt returned no prompt_id: {data}")
    return prompt_id


def wait_for_outputs(prompt_id: str, timeout: int = DEFAULT_TIMEOUT_SECONDS) -> dict:
    """Poll /history until the prompt finishes; return its outputs dict."""
    start = time.time()
    while time.time() - start < timeout:
        resp = requests.get(f"{base_url()}/history/{prompt_id}", timeout=30)
        if resp.ok:
            history = resp.json()
            entry = history.get(prompt_id)
            if entry:
                status = entry.get("status", {})
                if status.get("status_str") == "error" or status.get("completed") is False and status.get("messages"):
                    for message in status.get("messages", []):
                        if message and message[0] == "execution_error":
                            raise RuntimeError(f"ComfyUI execution error: {message[1]}")
                outputs = entry.get("outputs") or {}
                if outputs:
                    return outputs
        elapsed = int(time.time() - start)
        print(f"  ComfyUI {prompt_id}: {elapsed}s elapsed", file=sys.stderr)
        time.sleep(DEFAULT_POLL_INTERVAL_SECONDS)
    raise TimeoutError(f"ComfyUI prompt {prompt_id} timed out after {timeout}s")


def first_image(outputs: dict) -> dict:
    for node_output in outputs.values():
        images = node_output.get("images") or []
        if images:
            return images[0]
    raise RuntimeError(f"ComfyUI returned no images: {json.dumps(outputs)[:400]}")


def all_images(outputs: dict) -> list[dict]:
    """Every image in the outputs, in node-then-frame order (for batch/layer jobs)."""
    found: list[dict] = []
    for node_output in outputs.values():
        found.extend(node_output.get("images") or [])
    return found


def upload_image(path: Path, name: str | None = None, subfolder: str = "",
                 overwrite: bool = True) -> str:
    """Push a local file into ComfyUI's input dir; return the name LoadImage wants."""
    path = Path(path)
    name = name or path.name
    with open(path, "rb") as fh:
        resp = requests.post(
            f"{base_url()}/upload/image",
            files={"image": (name, fh, "image/png")},
            data={"overwrite": "true" if overwrite else "false", "subfolder": subfolder,
                  "type": "input"},
            timeout=300,
        )
    if not resp.ok:
        raise RuntimeError(f"ComfyUI /upload/image HTTP {resp.status_code}: {resp.text[:300]}")
    data = resp.json()
    stored = data.get("name", name)
    if data.get("subfolder"):
        stored = f"{data['subfolder']}/{stored}"
    return stored


def fetch_image(image: dict) -> bytes:
    query = urlencode(
        {
            "filename": image.get("filename", ""),
            "subfolder": image.get("subfolder", ""),
            "type": image.get("type", "output"),
        }
    )
    resp = requests.get(f"{base_url()}/view?{query}", timeout=180)
    if not resp.ok:
        raise RuntimeError(f"ComfyUI /view HTTP {resp.status_code}: {resp.text[:300]}")
    return resp.content


def build_edit_graph(
    prompt: str,
    refs: list[str],
    negative_prompt: str = "",
    resolution: int = 0,
    seed: int | None = None,
    steps: int = DEFAULT_STEPS,
    cfg: float = DEFAULT_CFG,
    sampler_name: str = DEFAULT_SAMPLER,
    scheduler: str = DEFAULT_SCHEDULER,
    denoise: float = 1.0,
    filename_prefix: str = "asset_gen",
    unet_name: str | None = None,
    clip_name: str | None = None,
    clip_type: str = DEFAULT_CLIP_TYPE,
    vae_name: str | None = None,
) -> dict:
    """API-format graph for a reference-image edit (Qwen-Image 2.1).

    `refs` are ComfyUI input names from `upload_image()`, or `"node_id:slot"`
    strings to reuse another node's IMAGE output. The first ref is the edit
    target; with `resolution=0` the sampled latent takes that ref's size, so the
    output comes back at the reference's own dimensions.
    """
    unet_name = unet_name or os.environ.get("COMFY_UNET", DEFAULT_UNET)
    clip_name = clip_name or os.environ.get("COMFY_CLIP", DEFAULT_CLIP)
    vae_name = vae_name or os.environ.get("COMFY_VAE", DEFAULT_VAE)
    if seed is None:
        seed = random.randint(0, 2**31 - 1)
    if not refs:
        raise ValueError("build_edit_graph needs at least one reference image")
    if len(refs) > 16:
        raise ValueError(f"TextEncodeQwenImage21 accepts at most 16 refs, got {len(refs)}")

    graph: dict = {
        "1": {"class_type": "UnetLoaderGGUF", "inputs": {"unet_name": unet_name}},
        "2": {
            "class_type": "CLIPLoader",
            "inputs": {"clip_name": clip_name, "type": clip_type},
        },
        "3": {"class_type": "VAELoader", "inputs": {"vae_name": vae_name}},
    }

    encode_inputs: dict = {
        "clip": ["2", 0],
        "vae": ["3", 0],
        "prompt": prompt,
        "negative_prompt": negative_prompt,
        "resolution": resolution,
    }
    for index, ref in enumerate(refs, start=1):
        # NOTE: the key is the *top-level* input id "images.image_N" -- see module docstring.
        encode_inputs[f"images.image_{index}"] = ref_link(graph, ref, index)

    graph["4"] = {"class_type": "TextEncodeQwenImage21", "inputs": encode_inputs}
    graph["6"] = {
        "class_type": "KSampler",
        "inputs": {
            "model": ["1", 0],
            "seed": seed,
            "steps": steps,
            "cfg": cfg,
            "sampler_name": sampler_name,
            "scheduler": scheduler,
            "positive": ["4", 0],
            "negative": ["4", 1],
            # The encoder's own latent: sized to image_1, which is what keeps an edit in place.
            "latent_image": ["4", 2],
            "denoise": denoise,
        },
    }
    graph["7"] = {"class_type": "VAEDecode", "inputs": {"samples": ["6", 0], "vae": ["3", 0]}}
    graph["8"] = {
        "class_type": "SaveImage",
        "inputs": {"images": ["7", 0], "filename_prefix": filename_prefix},
    }
    return graph


def ref_link(graph: dict, ref: str, index: int) -> list:
    """Resolve one reference entry to a node link, adding a LoadImage node if needed."""
    if ":" in ref:
        node_id, slot = ref.split(":", 1)
        return [node_id, int(slot)]
    node_id = str(100 + index)
    graph[node_id] = {"class_type": "LoadImage", "inputs": {"image": ref}}
    return [node_id, 0]


def generate_from_refs(
    refs: list[str],
    prompt: str,
    output: Path,
    resolution: int = 0,
    negative_prompt: str = "",
    seed: int | None = None,
    steps: int = DEFAULT_STEPS,
    cfg: float = DEFAULT_CFG,
    denoise: float = 1.0,
    filename_prefix: str = "asset_gen",
    timeout: int = DEFAULT_TIMEOUT_SECONDS,
    output_index: int = 0,
) -> Path:
    """Reference-grounded generation/edit. Returns the written path.

    `output_index` picks from the job's saved images when a single prompt yields
    several (batches, layer stacks).
    """
    graph = build_edit_graph(
        prompt=prompt,
        refs=refs,
        negative_prompt=negative_prompt,
        resolution=resolution,
        seed=seed,
        steps=steps,
        cfg=cfg,
        denoise=denoise,
        filename_prefix=filename_prefix,
    )
    prompt_id = submit(graph)
    print(f"  ComfyUI queued: {prompt_id}", file=sys.stderr)
    outputs = wait_for_outputs(prompt_id, timeout=timeout)
    images = all_images(outputs)
    if not images:
        raise RuntimeError(f"ComfyUI returned no images: {json.dumps(outputs)[:400]}")
    data = fetch_image(images[output_index])
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    return output


def generate_image(
    prompt: str,
    output: Path,
    width: int = 512,
    height: int = 512,
    negative_prompt: str = "",
    seed: int | None = None,
    steps: int = DEFAULT_STEPS,
    cfg: float = DEFAULT_CFG,
    transparent: bool = False,
    filename_prefix: str = "asset_gen",
    timeout: int = DEFAULT_TIMEOUT_SECONDS,
) -> Path:
    """Text-to-image via local ComfyUI + Qwen-Image 2.1. Returns the written path."""
    if transparent:
        prompt = wrap_transparent(prompt)
    graph = build_t2i_graph(
        prompt=prompt,
        negative_prompt=negative_prompt,
        width=width,
        height=height,
        seed=seed,
        steps=steps,
        cfg=cfg,
        filename_prefix=filename_prefix,
    )
    prompt_id = submit(graph)
    print(f"  ComfyUI queued: {prompt_id}", file=sys.stderr)
    outputs = wait_for_outputs(prompt_id, timeout=timeout)
    data = fetch_image(first_image(outputs))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(data)
    return output


def main() -> None:
    parser = argparse.ArgumentParser(description="Generate an image via local ComfyUI + Qwen-Image 2.1")
    parser.add_argument("--prompt", required=True)
    parser.add_argument("--negative-prompt", default="")
    parser.add_argument("-o", "--output", required=True)
    parser.add_argument("--ref", action="append", default=[],
                        help="Reference image for an edit (repeatable, first is the edit target)")
    parser.add_argument("--resolution", type=int, default=0,
                        help="Pixel budget for refs; 0 keeps each ref at its own size")
    parser.add_argument("--denoise", type=float, default=1.0)
    parser.add_argument("--width", type=int, default=512)
    parser.add_argument("--height", type=int, default=512)
    parser.add_argument("--steps", type=int, default=DEFAULT_STEPS)
    parser.add_argument("--cfg", type=float, default=DEFAULT_CFG)
    parser.add_argument("--seed", type=int, default=None)
    parser.add_argument("--transparent", action="store_true",
                        help="Wrap the prompt to request an RGBA image with alpha")
    parser.add_argument("--filename-prefix", default="asset_gen")
    parser.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_SECONDS)
    args = parser.parse_args()

    try:
        if args.ref:
            refs = [upload_image(Path(p)) for p in args.ref]
            path = generate_from_refs(
                refs=refs,
                prompt=wrap_transparent(args.prompt) if args.transparent else args.prompt,
                output=Path(args.output),
                resolution=args.resolution,
                negative_prompt=args.negative_prompt,
                seed=args.seed,
                steps=args.steps,
                cfg=args.cfg,
                denoise=args.denoise,
                filename_prefix=args.filename_prefix,
                timeout=args.timeout,
            )
        else:
            path = generate_image(
                prompt=args.prompt,
                output=Path(args.output),
                width=args.width,
                height=args.height,
                negative_prompt=args.negative_prompt,
                seed=args.seed,
                steps=args.steps,
                cfg=args.cfg,
                transparent=args.transparent,
                filename_prefix=args.filename_prefix,
                timeout=args.timeout,
            )
    except Exception as exc:  # noqa: BLE001 - surface any backend failure to the CLI
        print(json.dumps({"ok": False, "cost_cents": 0, "error": str(exc)}))
        sys.exit(1)

    print(json.dumps({"ok": True, "cost_cents": 0, "path": str(path)}))


if __name__ == "__main__":
    main()
