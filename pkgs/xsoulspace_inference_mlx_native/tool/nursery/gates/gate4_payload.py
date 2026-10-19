"""GATE-4 — payload fits the back room (TRAIN-GATES.md).

Metric (frozen, shape math from the packed store manifest — never a timed
measurement, so the power law does not reach this gate):
- payload: total store bytes <= the back-room budget;
- bytes/token: sum over MoE layers of (experts_per_tok x mean per-expert
  bytes) <= the rung target (rung-3: <= 25 MB/token).

Runs standalone against a store manifest, and at pack time via
payload_stats() imported from pack_at_birth.py (the pack-at-birth pipeline
gates at birth, not after training).

Usage:
  python gate4_payload.py --manifest store/manifest.json \
      --back-room-gb 10 --bytes-per-token-mb 25
  python gate4_payload.py --self-test
"""

import argparse
import json
import sys

from common import add_self_test_flag, finish

MB = 1024 * 1024
GB = 1024 * MB


def payload_from_manifest(manifest):
    """Reuse pack_at_birth's math so the gate and the packer cannot drift."""
    sys.path.insert(0, __file__.rsplit("/", 2)[0])  # tool/nursery
    import pack_at_birth
    return pack_at_birth.payload_stats(manifest)


def run(manifest_path, back_room_gb, bytes_per_token_mb, out_path=None):
    with open(manifest_path) as fh:
        manifest = json.load(fh)
    stats = payload_from_manifest(manifest)
    payload_ok = stats["total_bytes"] <= back_room_gb * GB
    bpt_ok = stats["bytes_per_token"] <= bytes_per_token_mb * MB
    passed = payload_ok and bpt_ok
    verdict = {
        "name": "GATE-4 payload",
        "passed": passed,
        "metric": {
            "payload_gb": round(stats["total_bytes"] / GB, 4),
            "bytes_per_token_mb": round(stats["bytes_per_token"] / MB, 4),
        },
        "detail": (f"payload {stats['total_bytes'] / GB:.3f} GB "
                   f"(budget {back_room_gb} GB) — "
                   f"{'ok' if payload_ok else 'OVER'}; "
                   f"bytes/token {stats['bytes_per_token'] / MB:.3f} MB "
                   f"(target {bytes_per_token_mb} MB) — "
                   f"{'ok' if bpt_ok else 'OVER'}; "
                   f"router dtypes {stats['router_dtypes']} (law: fp32)"),
    }
    if stats["router_dtypes"] and stats["router_dtypes"] != ["float32"]:
        verdict["detail"] += "; ROUTER NOT FP32 — PORTING-MOE law violated"
        verdict["passed"] = False
    print(json.dumps(verdict, indent=2))
    if out_path:
        with open(out_path, "w") as fh:
            json.dump(verdict, fh, indent=2)
    return verdict


def self_test():
    """Synthetic manifest with exact known math:
    2 MoE layers x 4 experts x 100 B/expert, topk 2
      -> bytes/token = 2 layers * 2 * 100 = 400 B;
    dense + embed 1000 B; total 8*100 + 1000 = 1800 B."""
    seg = lambda names_bytes, role: {
        "file": "seg_x.bin", "digest": "0" * 64, "size": sum(names_bytes.values()),
        "tensors": {name: {"offset": 0, "nbytes": n, "shape": [n],
                           "dtype": "float16", "role": role}
                    for name, n in names_bytes.items()},
    }
    expert_names = {
        f"model.layers.{{l}}.mlp.experts.{{e}}.gate_proj.weight".format(l=l, e=e): 100
        for l in (0, 1) for e in range(4)}
    manifest = {
        "source": {"config": {"num_experts_per_tok": 2}},
        "segments": {
            "experts": seg(expert_names, "expert"),
            "embed": seg({"model.embed_tokens.weight": 1000}, "embed"),
        },
    }
    cases = []
    stats = payload_from_manifest(manifest)
    cases.append(("bytes/token exact (400)", 400.0, stats["bytes_per_token"]))
    cases.append(("payload exact (1800)", 1800, stats["total_bytes"]))
    cases.append(("router fp32 empty ok", [], stats["router_dtypes"]))

    v = run_manifest_verdict(manifest, back_room_gb=1, bpt_mb=1)
    cases.append(("fits 1 GB / 1 MB per token", True, v["passed"]))
    v2 = run_manifest_verdict(manifest, back_room_gb=1, bpt_mb=0.0001)
    cases.append(("tiny per-token budget fails", False, v2["passed"]))
    v3 = run_manifest_verdict(manifest, back_room_gb=0.000001, bpt_mb=1)
    cases.append(("tiny payload budget fails", False, v3["passed"]))

    # The router law is enforced here too: a quantized router fails GATE-4.
    bad = json.loads(json.dumps(manifest))
    bad["segments"]["router"] = seg(
        {"model.layers.0.mlp.gate.weight": 64, "model.layers.1.mlp.gate.weight": 64},
        "router")
    for segentry in bad["segments"].values():
        for t in segentry["tensors"].values():
            if t["role"] == "router":
                t["dtype"] = "uint32"
    v4 = run_manifest_verdict(bad, back_room_gb=1, bpt_mb=1)
    cases.append(("non-fp32 router fails the law", False, v4["passed"]))

    from common import self_test_main
    return self_test_main(sys.modules[__name__], cases)


def run_manifest_verdict(manifest, back_room_gb, bpt_mb):
    sys.path.insert(0, __file__.rsplit("/", 2)[0])
    import pack_at_birth
    stats = pack_at_birth.payload_stats(manifest)
    MB = 1024 * 1024
    GB = 1024 * MB
    payload_ok = stats["total_bytes"] <= back_room_gb * GB
    bpt_ok = stats["bytes_per_token"] <= bpt_mb * MB
    router_ok = not stats["router_dtypes"] or stats["router_dtypes"] == ["float32"]
    return {"passed": payload_ok and bpt_ok and router_ok}


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    add_self_test_flag(ap)
    ap.add_argument("--manifest")
    ap.add_argument("--back-room-gb", type=float)
    ap.add_argument("--bytes-per-token-mb", type=float)
    ap.add_argument("--out")
    result, args = finish(argv, ap, self_test)
    if result is not None:
        return result
    if not args.manifest or args.back_room_gb is None or args.bytes_per_token_mb is None:
        ap.error("--manifest, --back-room-gb and --bytes-per-token-mb are "
                 "required (budgets come from the rung's config)")
    verdict = run(args.manifest, args.back_room_gb, args.bytes_per_token_mb,
                  args.out)
    return 0 if verdict["passed"] else 1


if __name__ == "__main__":
    sys.exit(main())
