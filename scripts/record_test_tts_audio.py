#!/usr/bin/env python3
"""
Generate TTS test audio files for ASR testing.

Requires macOS `say` command.

Examples:
  python scripts/record_test_tts_audio.py
  python scripts/record_test_tts_audio.py --out apps/godot-client/assets/test_audio
  python scripts/record_test_tts_audio.py --voice Samantha
"""

from __future__ import annotations

import argparse
import subprocess
from pathlib import Path


DEFAULT_LINES = [
    {
        "filename": "hello_my_name_is_lily.wav",
        "text": "Hello, my name is Lily.",
    },
    {
        "filename": "i_like_apples.wav",
        "text": "I like apples.",
    },
    {
        "filename": "can_i_have_some_water.wav",
        "text": "Can I have some water?",
    },
    {
        "filename": "the_magic_spell_is_rainbow.wav",
        "text": "The magic spell is rainbow.",
    },
    {
        "filename": "my_favorite_color_is_blue.wav",
        "text": "My favorite color is blue.",
    },
    {
        "filename": "where_is_the_library.wav",
        "text": "Where is the library?",
    },
    {
        "filename": "i_am_ready_for_the_quest.wav",
        "text": "I am ready for the quest.",
    },
]


def contains_cjk(text: str) -> bool:
    return any("一" <= char <= "鿿" for char in text)


def choose_default_voice(text: str) -> str:
    return "Tingting" if contains_cjk(text) else "Samantha"


def run_say(text: str, output_path: Path, voice: str, rate: int) -> None:
    command = [
        "say",
        "-v",
        voice,
        "-r",
        str(rate),
        "--file-format=WAVE",
        "--data-format=LEI16@22050",
        "-o",
        str(output_path),
        text,
    ]

    try:
        subprocess.run(command, check=True)
    except FileNotFoundError as error:
        raise RuntimeError("macOS `say` command not found.") from error
    except subprocess.CalledProcessError as error:
        raise RuntimeError(f"Failed to generate audio: {output_path}") from error


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate TTS audio files for ASR tests."
    )
    parser.add_argument(
        "--out",
        default="apps/godot-client/assets/test_audio",
        help="Output directory for generated audio files.",
    )
    parser.add_argument(
        "--voice",
        help="macOS voice name. Chinese text defaults to Tingting, otherwise Samantha.",
    )
    parser.add_argument(
        "--rate",
        type=int,
        default=150,
        help="Speech rate for macOS say command.",
    )
    parser.add_argument(
        "--text",
        help="Generate one custom audio file from this text.",
    )
    parser.add_argument(
        "--filename",
        default="custom_test_audio.wav",
        help="Output filename when using --text.",
    )
    parser.add_argument(
        "--alphabet",
        action="store_true",
        help="Generate one wav file per letter (A-Z).",
    )

    args = parser.parse_args()

    output_dir = Path(args.out)
    output_dir.mkdir(parents=True, exist_ok=True)

    if args.alphabet:
        lines = [
            {"filename": f"letter_{chr(ord('a') + i)}.wav", "text": chr(ord("a") + i)}
            for i in range(26)
        ]
    elif args.text:
        lines = [{"filename": args.filename, "text": args.text}]
    else:
        lines = DEFAULT_LINES

    for item in lines:
        output_path = output_dir / item["filename"]
        run_say(
            text=item["text"],
            output_path=output_path,
            voice=args.voice or choose_default_voice(item["text"]),
            rate=args.rate,
        )
        print(f"generated: {output_path} <- {item['text']}")


if __name__ == "__main__":
    main()
