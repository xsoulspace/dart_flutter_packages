"""ADR 0054 R2 parity reference — greedy token ids from mlx-lm for the
cached Qwen3-0.6B-4bit snapshot, plus byte-level-BPE tokenizer probes.

Writes testdata/qwen3_06b_parity.json next to the laya_rust crate. The
fixture contains a synthetic prompt and token ids only — no private data.

Run: ~/.venvs/mlx-ref/bin/python tool/gen_qwen3_parity_fixture.py
"""

import glob
import json
import os
import sys

from mlx_lm import load
from mlx_lm.generate import stream_generate
from mlx_lm.sample_utils import make_sampler

PROMPT = (
    "The history of the Apple Silicon unified memory architecture begins "
    "with a simple observation: bandwidth, not peak flops, decides how "
    "fast a small transformer thinks."
)

# Tokenizer probes: each branch of the pre-tokenizer alternation, digits,
# contractions (case-insensitive), unicode letters, punctuation runs,
# trailing whitespace. Encode-only — no model involvement.
PROBES = [
    PROMPT,
    "I'll can't WE'VE he'd It's don't",
    "x = 12345 + 7; y2 = 0.5%",
    "naïve café 東京都 résumé",
    "  leading and trailing   ",
    "line one\nline two\n\nline three",
    "<|im_start|>special tokens stay literal<|im_end|>",
    "a,b.c:d!e?f;g(h) [i] {j} \"k\" 'l'",
]


def main() -> int:
    snaps = glob.glob(
        os.path.expanduser(
            "~/.cache/huggingface/hub/models--mlx-community--Qwen3-0.6B-4bit/snapshots/*"
        )
    )
    if not snaps:
        print("Qwen3-0.6B-4bit snapshot not found in HF cache", file=sys.stderr)
        return 1
    snap = snaps[0]

    model, tokenizer = load(snap)
    sampler = make_sampler(temp=0.0)

    prompt_ids = [int(i) for i in tokenizer.encode(PROMPT)]
    generated = []
    for resp in stream_generate(
        model, tokenizer, PROMPT, max_tokens=64, sampler=sampler
    ):
        generated.append(int(resp.token))

    probes = {}
    for text in PROBES:
        probes[text] = [int(i) for i in tokenizer.encode(text)]

    out_path = os.path.join(
        os.path.dirname(__file__),
        "..",
        "native",
        "laya_rust",
        "testdata",
        "qwen3_06b_parity.json",
    )
    fixture = {
        "snapshot": os.path.basename(os.path.normpath(snap)),
        "prompt": PROMPT,
        "prompt_ids": prompt_ids,
        "greedy_ids": generated,
        "tokenizer_probes": probes,
    }
    with open(out_path, "w") as f:
        json.dump(fixture, f, ensure_ascii=False, indent=2)
        f.write("\n")
    print(f"wrote {out_path}")
    print(f"prompt_ids[{len(prompt_ids)}] = {prompt_ids[:12]}...")
    print(f"greedy_ids[{len(generated)}] = {generated}")
    text = tokenizer.decode(generated)
    print(f"decoded: {text!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
