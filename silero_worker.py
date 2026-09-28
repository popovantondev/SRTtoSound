#!/usr/bin/env python3
"""Persistent Silero TTS worker using one JSON object per line."""

import argparse
import json
import os
import re
import sys

import soundfile as sf
import torch
from torch.package import PackageImporter


def reply(payload):
    print(json.dumps(payload, ensure_ascii=False), flush=True)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--model", required=True)
    parser.add_argument("--speaker", default="xenia")
    parser.add_argument("--sample-rate", type=int, default=24000)
    args = parser.parse_args()

    # On Apple M4 this model is CPU-only.  One Torch thread per process is
    # substantially faster than eight contending threads; Ruby runs three
    # independent workers for phrase-level parallelism.
    torch.set_num_threads(1)
    torch.set_num_interop_threads(1)
    if not os.path.isfile(args.model) or os.path.getsize(args.model) == 0:
        raise FileNotFoundError(f"Локальная модель Silero не найдена или пуста: {args.model}")
    model = PackageImporter(args.model).load_pickle("tts_models", "model")
    model.to(torch.device("cpu"))
    reply({"ready": True, "model": "v5_5_ru", "speaker": args.speaker})

    for raw_line in sys.stdin:
        try:
            request = json.loads(raw_line)
            text = request["text"].strip()
            output_path = request["output_path"]
            if not text:
                raise ValueError("пустой текст")
            # Silero silently deletes digits, Latin text and unsupported
            # symbols.  Refuse unsafe input so a lecture can never be published
            # with missing dosages or plant names.
            unsupported = re.sub(r"[А-Яа-яЁё\s.,!?…;:—–\-()\"'«»]", "", text)
            if unsupported:
                preview = unsupported[:40]
                raise ValueError(
                    "после нормализации остались неподдерживаемые знаки: "
                    + repr(preview)
                )

            audio = model.apply_tts(
                text=text,
                speaker=args.speaker,
                sample_rate=args.sample_rate,
                put_accent=True,
                put_yo=True,
            )
            samples = audio.detach().cpu().numpy()
            sf.write(output_path, samples, args.sample_rate, subtype="PCM_16")
            reply({"ok": True, "samples": int(samples.size)})
        except Exception as error:  # keep the worker alive and report the phrase error
            reply({"ok": False, "error": str(error) or type(error).__name__})


if __name__ == "__main__":
    main()
