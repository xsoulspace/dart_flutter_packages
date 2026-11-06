#!/usr/bin/env python3
"""v1v2_prep.py - V1-v2 arc off-device preparation (ARC-OWNED helper).

PREREG-C addendum 2026-11-06b rerun: V-1 null-constructor v2 on the
family-wise subset {plant-1, plant-3, plant-5} + confounded-positive control
(old null-3 shape, plant-1 only) + V-2 (plant-1 only, reused B3).

Prepares (NEVER scores, NEVER touches the device, frozen tools read-only):
  1. format-style contrast banks for null3-v2: seeded 64-prompt subsets of
     the FROZEN neutral bank (prompts_localization_neutral_A3.txt, 128
     lines), rendered UPPERCASE and lowercase. Draw k subset =
     sorted(Random(SEED3 + 7919*k).sample(range(128), 64)), SEED3 frozen
     pre-result in the arc run-plan. Both draws' banks are emitted up front
     so a gate re-draw costs no extra device time.
  2. spec reuse: plant-1 null1/2/4 + confounded (old null3_unrelated) +
     V-2 ablate/restore/relocate + B3.json are REUSED from receipts/V12
     (digest-verified against the v1 ledger rows; copies re-verified).
  3. spec builds: plant-3/plant-5 null1/2/4 built by the FROZEN-RULE v12
     builder (v12_nulls.py, unmodified, digest recorded) on the archived
     arm dirs, seed 20261106 (the v12 run-plan's pre-result frozen seed).
  4. per-arm arc manifests (provenance REUSED_V12 / BUILT_FRESH + digests).
  5. v12_batch.py batch files: <TAG>A (mirror+gates+continuity captures+M+
     null1+null2) and <TAG>B (mirror+gates+fmt captures+M+[confounded]+
     null4+null3v2 build+null3v2 battery), gates read from the archived
     arm receipts (mirror_shard_sha256, recovered direction_sha256) which
     are re-verified here against the frozen join-table digests.
  6. prep_receipt.json with every digest for the run-plan row.

Usage:
  python3 -I -B v1v2_prep.py [--tmp <TMPDIR>]

Exit codes: 0 ok; 1 NAMED error on stderr ('CODE: detail'):
  ARCHIVE_MISSING DIGEST_MISMATCH JOIN_MISMATCH BANK_UNREADABLE
  BUILD_FAILED SPEC_UNWRITABLE
"""

import argparse
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(os.path.dirname(HERE))

SEED3 = 202611063          # frozen pre-result (arc run-plan); fmt subsets
SEED3_OFFSET = 7919        # re-draw seed offset
SUBSET_N = 64
SEED_NULLS = 20261106      # v12 run-plan frozen seed for null1/2/4

LAYERS = ("15", "19")
REMOVAL_SCALE = -4.8

# edit_id, arm, tag, v12-reuse?
EDITS = [
    ("a3-plant-1", "arm-002", "P1"),
    ("a3-plant-3", "arm-009", "P3"),
    ("a3-plant-5", "arm-015", "P5"),
]

# expected digests of REUSED artifacts (v1 ledger rows / v12 run-plan v2_rules)
REUSE_EXPECT = {
    "null1_gaussian_spec.json":
        "0b87f0f167be76d2448549760d6702de18a98b37f770bcd014aeb277298b58f2",
    "null2_shuffle_spec.json":
        "20be6f5bfbf9e83c2de117a9127276f3345e8c9d60b12b0bbb9be8541c92d369",
    "null4_quantnoise_spec.json":
        "2a0cbec62c7e0fcae4ffa98523811dc68e115ca0353e42c047fe353c30c4f510",
    "null3_unrelated_spec.json":
        "b939db2fbad79082040de7993c3f113860a820c7f4f3a89677fcb1bb23ee752f",
    "ablate_spec.json":
        "14fa817bbb998b3a4c0d4efa45432cd863a608156e03694f9a4ff1f499668b0c",
    "restore_spec.json":
        "65d1f5e0ed03c2cb2014a6652ef62e06810d1c6ed0a86bed4b7e242261cab35f",
    "relocate_spec.json":
        "5c92194390d23ca727d44be2b94c47a813884b9832bd766f6af134fe43ed69d2",
    "recovered_slugify.json":
        "b8ac36e20dfad41fb1959e64d69b3f969df5d6ea5bf7cecbb1861d7646793ac1",
}

FROZEN_TOOLS = [
    "tool/runs/a3_battery.py", "tool/runs/a3_lock.py",
    "tool/runs/a3_propose.py", "tool/runs/a3_score.dart",
    "tool/eval/apply_delta.py", "tool/eval/capture_activations.py",
    "tool/runs/cells_frozen_A3.json", "tool/runs/make_mirror.py",
    "tool/runs/prompts_localization_loop_A3.txt",
    "tool/runs/prompts_localization_neutral_A3.txt",
    "lib/src/scorers.dart",
]
V12_HELPERS = ["tool/runs/v12_batch.py", "tool/runs/v12_nulls.py",
               "tool/runs/v12_verdict.py"]

BASE_MODEL = os.path.expanduser(
    "~/.cache/huggingface/hub/models--mlx-community--Qwen3-0.6B-bf16/"
    "snapshots/42096995f6402fde107068cf530136fe64b604f8")
VENV_PY = "/Users/antonio/.local/share/wm-mlx/bin/python"
LOCK_DIR_NAME = "wm-device.lock"


def fail(code, detail):
    print("%s: %s" % (code, detail), file=sys.stderr)
    return 1


def now():
    return datetime.now(timezone.utc).isoformat(timespec="seconds")


def sha256_file(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tmp", default=os.environ.get("TMPDIR", "/tmp"))
    args = ap.parse_args()
    tmp = args.tmp.rstrip("/")

    wm = os.path.join(tmp, "wm-v1v2")
    a3 = os.path.join(tmp, "wm-a3")
    v12specs = os.path.join(tmp, "wm-v12", "specs")
    v12rec = os.path.join(REPO, "receipts", "V12")
    for d in ("banks", "batches", "batches/receipts", "gen", "mirrors",
              "scorework", "specs"):
        os.makedirs(os.path.join(wm, d), exist_ok=True)

    receipt = {"tool": "v1v2_prep.py", "at": now(), "tmp": tmp,
               "seed_fmt": SEED3, "seed_fmt_offset": SEED3_OFFSET,
               "seed_nulls": SEED_NULLS, "subset_n": SUBSET_N}

    # ---------- frozen tool + helper digests (current tree bytes) ----------
    receipt["frozen_tools_sha256"] = {
        p: sha256_file(os.path.join(REPO, p)) for p in FROZEN_TOOLS}
    receipt["v12_helpers_sha256"] = {
        p: sha256_file(os.path.join(REPO, p)) for p in V12_HELPERS}
    receipt["arc_helpers_sha256"] = {
        "v1v2_prep.py": sha256_file(os.path.join(HERE, "v1v2_prep.py")),
        "v1v2_null3v2.py": sha256_file(
            os.path.join(HERE, "v1v2_null3v2.py")),
        "v1v2_verdict.py": sha256_file(
            os.path.join(HERE, "v1v2_verdict.py")),
    }

    # ---------- frozen neutral bank + fmt subset banks ----------
    neutral_p = os.path.join(REPO, "tool/runs",
                             "prompts_localization_neutral_A3.txt")
    if not os.path.isfile(neutral_p):
        return fail("BANK_UNREADABLE", neutral_p)
    neutral = [l for l in open(neutral_p, encoding="utf-8").read()
               .splitlines() if l.strip()]
    if len(neutral) != 128:
        return fail("BANK_UNREADABLE",
                    "neutral bank has %d lines, want 128" % len(neutral))
    banks = {"source": neutral_p,
             "source_sha256": sha256_file(neutral_p),
             "rule": "subset_k = sorted(Random(%d + %d*k).sample("
                     "range(128), %d)); upper = line.upper(), "
                     "lower = line.lower(); direction = unit(mean(upper) "
                     "- mean(lower)) via FROZEN a3_propose.py "
                     "(--cap-loop=upper, --cap-neutral=lower)"
                     % (SEED3, SEED3_OFFSET, SUBSET_N),
             "draws": {}}
    for k in (0, 1):
        subset = sorted(random.Random(SEED3 + SEED3_OFFSET * k)
                        .sample(range(len(neutral)), SUBSET_N))
        paths = {}
        for case, fn in (("upper", str.upper), ("lower", str.lower)):
            p = os.path.join(wm, "banks", "fmt_%s_d%d.txt" % (case, k))
            with open(p, "w", encoding="utf-8") as fh:
                fh.write("\n".join(fn(neutral[i]) for i in subset) + "\n")
            paths[case] = {"path": p, "sha256": sha256_file(p)}
        banks["draws"]["d%d" % k] = {
            "seed": SEED3 + SEED3_OFFSET * k,
            "subset_indices": subset,
            "files": paths,
        }
    banks_p = os.path.join(wm, "gen", "fmt_banks.json")
    with open(banks_p, "w", encoding="utf-8") as fh:
        json.dump(banks, fh, indent=1)
    receipt["fmt_banks"] = {"path": banks_p,
                            "sha256": sha256_file(banks_p),
                            "draw_seeds": {dk: dv["seed"]
                                           for dk, dv in
                                           banks["draws"].items()},
                            "file_sha256": {
                                dk: {c: fv["sha256"]
                                     for c, fv in dv["files"].items()}
                                for dk, dv in banks["draws"].items()}}

    # ---------- join-table integrity re-verification (archives) ----------
    join = json.load(open(os.path.join(REPO, "receipts/A3/join-table.json"),
                          encoding="utf-8"))
    join_rows = {r["real_id"]: r for r in join["rows"]}
    integrity = {}
    for edit, arm, tag in EDITS:
        row = join_rows.get(edit)
        if row is None or not row.get("certified"):
            return fail("JOIN_MISMATCH", "%s missing/not certified" % edit)
        if row["label"] != arm:
            return fail("JOIN_MISMATCH",
                        "%s label %s != %s" % (edit, row["label"], arm))
        checks = {}
        adir = os.path.join(a3, "blind", arm)
        for key, fname in (("battery_M", "battery_M.jsonl"),
                           ("battery_R", "battery_R.jsonl"),
                           ("recovered_json", "recovered.json"),
                           ("mirror_receipt", "mirror_receipt.json"),
                           ("repair_receipt", "repair_receipt.json"),
                           ("arm_receipt", "arm_receipt.json")):
            p = os.path.join(adir, fname)
            if not os.path.isfile(p):
                return fail("ARCHIVE_MISSING", p)
            got = sha256_file(p)
            checks[key] = {"want": row["digests"][key], "got": got,
                           "match": got == row["digests"][key]}
            if got != row["digests"][key]:
                return fail("JOIN_MISMATCH", "%s %s %s" % (arm, key, got))
        for L in LAYERS:
            sp = os.path.join(adir, "specs", "spec_L%s.json" % L)
            tp = os.path.join(REPO, "receipts/A3/truth/specs", edit,
                              "spec_L%s.json" % L)
            for p in (sp, tp):
                if not os.path.isfile(p):
                    return fail("ARCHIVE_MISSING", p)
            m = sha256_file(sp) == sha256_file(tp)
            checks["spec_L%s_blind_eq_truth" % L] = m
            if not m:
                return fail("JOIN_MISMATCH", "%s spec_L%s" % (arm, L))
        mir = json.load(open(os.path.join(adir, "mirror_receipt.json"),
                             encoding="utf-8"))
        rec = json.load(open(os.path.join(adir, "recovered.json"),
                             encoding="utf-8"))
        integrity[edit] = {
            "arm": arm, "checks": checks,
            "gate_mirror_shard_sha256": mir["mirror_shard_sha256"],
            "gate_direction_sha256": {
                L: rec["layers"][L]["direction_sha256"] for L in LAYERS},
            "join_metrics": {
                "loop_rate_M": row["loop_rate_M"],
                "loop_rate_R": row["loop_rate_R"],
                "loop_delta_R_minus_M": row["loop_delta_R_minus_M"],
                "task_success_M": row["task_success_M"],
                "task_success_R": row["task_success_R"],
                "net_g1_flips": sum(
                    1 for f in row["flips"]
                    if f["cell_id"].startswith("g1-perm")
                    and not f["M"] and f["R"]) - sum(
                    1 for f in row["flips"]
                    if f["cell_id"].startswith("g1-perm")
                    and f["M"] and not f["R"]),
            },
        }
    receipt["archive_integrity"] = {
        e: {"arm": v["arm"],
            "all_match": all(
                (c["match"] if isinstance(c, dict) else c)
                for c in v["checks"].values())}
        for e, v in integrity.items()}

    # ---------- spec reuse (plant-1) ----------
    reuse = {}
    spec_dir_002 = os.path.join(wm, "specs", "arm-002")
    os.makedirs(spec_dir_002, exist_ok=True)
    v12_manifest_p = os.path.join(v12specs, "nulls_manifest.json")
    if not os.path.isfile(v12_manifest_p):
        return fail("ARCHIVE_MISSING", v12_manifest_p)
    v12_manifest = json.load(open(v12_manifest_p, encoding="utf-8"))
    receipt["v12_nulls_manifest_sha256"] = sha256_file(v12_manifest_p)
    for fname, expect in REUSE_EXPECT.items():
        src_rec = os.path.join(v12rec, fname)
        src_tmp = os.path.join(v12specs, fname)
        for src in (src_rec, src_tmp):
            if not os.path.isfile(src):
                return fail("ARCHIVE_MISSING", src)
            got = sha256_file(src)
            if got != expect:
                return fail("DIGEST_MISMATCH",
                            "%s: %s != expected %s" % (src, got, expect))
        dst = os.path.join(spec_dir_002, fname)
        shutil.copyfile(src_rec, dst)
        if sha256_file(dst) != expect:
            return fail("DIGEST_MISMATCH", "copy %s" % dst)
        reuse[fname] = {"expected_sha256": expect,
                        "sources": [src_rec, src_tmp], "copied_to": dst}
    # B3.json (V-2 batch) reused VERBATIM from receipts/V12
    b3_src = os.path.join(v12rec, "B3.json")
    b3_dst = os.path.join(wm, "batches", "B3_v2.json")
    shutil.copyfile(b3_src, b3_dst)
    reuse["B3.json"] = {"expected_sha256": sha256_file(b3_src),
                        "sources": [b3_src], "copied_to": b3_dst,
                        "note": "V-2 batch reused VERBATIM (specs + "
                                "wm-v12 sidecars must exist at run time)"}
    for sc in ("L15", "L19"):
        p = os.path.join(tmp, "wm-v12", "gen", "sidecars", sc, "delta.npz")
        if not os.path.isfile(p):
            return fail("ARCHIVE_MISSING", "B3 sidecar %s" % p)
    receipt["reused_v12"] = reuse

    # ---------- spec builds (plant-3, plant-5) ----------
    builds = {}
    for edit, arm, tag in EDITS:
        if arm == "arm-002":
            continue
        out_dir = os.path.join(wm, "specs", arm)
        os.makedirs(out_dir, exist_ok=True)
        proc = subprocess.run(
            [sys.executable, "-I", "-B",
             os.path.join(HERE, "v12_nulls.py"),
             "--arm-dir", os.path.join(a3, "blind", arm),
             "--out-dir", out_dir, "--seed", str(SEED_NULLS)],
            capture_output=True, text=True,
            env={**os.environ, "PYTHONDONTWRITEBYTECODE": "1"})
        if proc.returncode != 0:
            return fail("BUILD_FAILED",
                        "%s: %s" % (arm, (proc.stderr or proc.stdout)[-400:]))
        man = json.load(open(os.path.join(out_dir, "nulls_manifest.json"),
                             encoding="utf-8"))
        builds[arm] = {"stdout": proc.stdout.strip(),
                       "manifest_sha256": sha256_file(
                           os.path.join(out_dir, "nulls_manifest.json")),
                       "specs": {k: v["spec_sha256"]
                                 for k, v in man["nulls"].items()}}
    receipt["built_fresh"] = builds

    # ---------- per-arm arc manifests ----------
    for edit, arm, tag in EDITS:
        spec_dir = os.path.join(wm, "specs", arm)
        adir = os.path.join(a3, "blind", arm)
        repair = json.load(open(os.path.join(adir, "repair_spec.json"),
                                encoding="utf-8"))
        for t in repair["tensors"]:
            if abs(float(t["scale"]) - REMOVAL_SCALE) > 1e-12:
                return fail("DIGEST_MISMATCH",
                            "%s repair scale %s != %s"
                            % (arm, t["scale"], REMOVAL_SCALE))
        man = {"edit": edit, "arm": arm, "tag": tag, "at": now(),
               "removal_scale": REMOVAL_SCALE,
               "columns_source": {
                   "path": os.path.join(adir, "repair_spec.json"),
                   "sha256": sha256_file(
                       os.path.join(adir, "repair_spec.json"))},
               "d_hat_source": {
                   "path": os.path.join(adir, "recovered.json"),
                   "sha256": sha256_file(
                       os.path.join(adir, "recovered.json"))},
               "nulls": {}}
        if arm == "arm-002":
            src_man = v12_manifest
            prov = "REUSED_V12 (digest-verified vs v1 ledger rows)"
        else:
            src_man = json.load(open(os.path.join(
                spec_dir, "nulls_manifest.json"), encoding="utf-8"))
            prov = "BUILT_FRESH (v12_nulls.py unmodified, seed %d)" % \
                SEED_NULLS
        for kind, fname in (("null1_gaussian", "null1_gaussian_spec.json"),
                            ("null2_shuffle", "null2_shuffle_spec.json"),
                            ("null4_quantnoise",
                             "null4_quantnoise_spec.json")):
            entry = src_man["nulls"][kind]
            local = os.path.join(spec_dir, fname)
            if arm == "arm-002":
                pass  # already copied above
            got = sha256_file(local)
            if got != entry["spec_sha256"]:
                return fail("DIGEST_MISMATCH",
                            "%s %s: %s != %s" % (arm, kind, got,
                                                 entry["spec_sha256"]))
            man["nulls"][kind] = {
                "spec_path": local, "spec_sha256": got,
                "provenance": prov, "scale": entry["scale"],
                "construction": entry["construction"],
                "per_layer": entry["per_layer"],
            }
        man["nulls"]["null3_unrelated_v2"] = {
            "spec_path": os.path.join(spec_dir, "null3v2_spec.json"),
            "status": "BUILT_AT_BATCH_TIME",
            "builder": "v1v2_null3v2.py (arc-owned) over FROZEN "
                       "a3_propose.py diff-of-means",
            "gate": {"rule": "|cos(null, d_hat)| <= 0.2 per layer {15,19}, "
                             "construction-time, receipted BEFORE any "
                             "certification; one re-draw (seed offset "
                             "%d), then GATE_EXHAUSTED row" % SEED3_OFFSET,
                     "threshold": 0.2,
                     "banks": receipt["fmt_banks"]},
        }
        if arm == "arm-002":
            man["confounded_positive_control"] = {
                "arm_type": "CONFOUNDED_POSITIVE_CONTROL",
                "note": "old null-3 shape (G0-slugify-vs-neutral "
                        "diff-of-means on the plant mirror); expected "
                        "maybe-certify; SEPARATE denominator; NEVER in the "
                        "null floor (PREREG-C addendum 2026-11-06b)",
                "spec_path": os.path.join(spec_dir,
                                          "null3_unrelated_spec.json"),
                "spec_sha256": REUSE_EXPECT["null3_unrelated_spec.json"],
                "provenance": "REUSED_V12 (v1-null-3 spec, digest-verified)",
                "scale": REMOVAL_SCALE,
                "per_layer": v12_manifest["nulls"]["null3_unrelated"][
                    "per_layer"],
                "recovered_slugify_sha256": sha256_file(
                    os.path.join(spec_dir, "recovered_slugify.json")),
            }
            man["v2_specs"] = {
                k: {"spec_path": os.path.join(spec_dir_002,
                                              "%s_spec.json" % k),
                    "spec_sha256": REUSE_EXPECT["%s_spec.json" % k],
                    "provenance": "REUSED_V12; V-2 batch = B3.json reused "
                                  "VERBATIM (reads wm-v12/specs + sidecars)"}
                for k in ("ablate", "restore", "relocate")}
        p = os.path.join(spec_dir, "arc_manifest.json")
        try:
            with open(p, "w", encoding="utf-8") as fh:
                json.dump(man, fh, indent=1)
        except OSError as exc:
            return fail("SPEC_UNWRITABLE", str(exc))
        receipt.setdefault("arc_manifests", {})[arm] = {
            "path": p, "sha256": sha256_file(p)}

    # ---------- batch files ----------
    def py(*argv):
        return [VENV_PY, "-I", "-B", *argv]

    T = lambda p: os.path.join(REPO, p)  # noqa: E731
    cells = T("tool/runs/cells_frozen_A3.json")
    batch_digests = {}
    for edit, arm, tag in EDITS:
        adir = os.path.join(a3, "blind", arm)
        mirror = os.path.join(wm, "mirrors", "v1v2-%s" % tag.lower())
        gdir = os.path.join(wm, "gen", tag)
        os.makedirs(gdir, exist_ok=True)
        side = os.path.join(wm, "gen", "sidecars", arm)
        spec_dir = os.path.join(wm, "specs", arm)
        gate_mirror = integrity[edit]["gate_mirror_shard_sha256"]
        gate_dirs = integrity[edit]["gate_direction_sha256"]

        def mk_mirror(rec_name):
            return {"step": "make_mirror", "argv": py(
                T("tool/runs/make_mirror.py"),
                "--base", BASE_MODEL, "--out", mirror,
                "--sidecar", os.path.join(side, "L15"),
                "--sidecar", os.path.join(side, "L19"),
                "--receipt", os.path.join(gdir, rec_name))}

        mirror_gate = {"after": "make_mirror",
                       "file": os.path.join(gdir, "mirror_receipt_A.json"),
                       "key": "mirror_shard_sha256", "expect": gate_mirror,
                       "code": "MIRROR_NONREPRODUCIBLE"}
        # ---- batch A ----
        steps_a = [
            {"step": "apply_delta_L15", "argv": py(
                T("tool/eval/apply_delta.py"), "--base", BASE_MODEL,
                "--spec", os.path.join(adir, "specs", "spec_L15.json"),
                "--out", os.path.join(side, "L15"))},
            {"step": "apply_delta_L19", "argv": py(
                T("tool/eval/apply_delta.py"), "--base", BASE_MODEL,
                "--spec", os.path.join(adir, "specs", "spec_L19.json"),
                "--out", os.path.join(side, "L19"))},
            mk_mirror("mirror_receipt_A.json"),
            {"step": "capture_loop_fresh", "argv": py(
                T("tool/eval/capture_activations.py"), "--model", mirror,
                "--prompts", T("tool/runs/prompts_localization_loop_A3.txt"),
                "--layers", "15,19",
                "--out", os.path.join(gdir, "cap_loop_fresh.json"))},
            {"step": "capture_neutral_fresh", "argv": py(
                T("tool/eval/capture_activations.py"), "--model", mirror,
                "--prompts",
                T("tool/runs/prompts_localization_neutral_A3.txt"),
                "--layers", "15,19",
                "--out", os.path.join(gdir, "cap_neutral_fresh.json"))},
            {"step": "propose_fresh", "argv": py(
                T("tool/runs/a3_propose.py"),
                "--cap-loop", os.path.join(gdir, "cap_loop_fresh.json"),
                "--cap-neutral", os.path.join(gdir, "cap_neutral_fresh.json"),
                "--out", os.path.join(gdir, "recovered_fresh.json"))},
            {"step": "battery_M_A", "argv": py(
                T("tool/runs/a3_battery.py"), "--model", mirror,
                "--cells", cells, "--groups", "G0,G1,G2",
                "--out", os.path.join(gdir, "battery_M_A.jsonl"))},
        ]
        for n in ("null1_gaussian", "null2_shuffle"):
            short = n.split("_")[0]
            steps_a.append({"step": "battery_%s" % short, "argv": py(
                T("tool/runs/a3_battery.py"), "--model", mirror,
                "--cells", cells, "--groups", "G0,G1,G2",
                "--repair", os.path.join(spec_dir, "%s_spec.json" % n),
                "--repair-out", os.path.join(gdir, "battery_%s.jsonl"
                                             % short),
                "--repair-receipt", os.path.join(
                    gdir, "repair_receipt_%s.json" % short))})
        gates_a = [mirror_gate] + [
            {"after": "propose_fresh",
             "file": os.path.join(gdir, "recovered_fresh.json"),
             "key": "layers.%s.direction_sha256" % L,
             "expect": gate_dirs[L],
             "code": "RECOVERY_NONREPRODUCIBLE"} for L in LAYERS]
        ba = {"batch": "%sA" % tag, "mirror_dir": mirror,
              "gates": gates_a, "steps": steps_a}
        # ---- batch B ----
        mirror_gate_b = dict(mirror_gate,
                             file=os.path.join(gdir,
                                               "mirror_receipt_B.json"))
        steps_b = [mk_mirror("mirror_receipt_B.json")]
        for k in (0, 1):
            for case in ("upper", "lower"):
                steps_b.append({
                    "step": "capture_fmt_%s_d%d" % (case, k),
                    "argv": py(
                        T("tool/eval/capture_activations.py"),
                        "--model", mirror,
                        "--prompts", banks["draws"]["d%d" % k]["files"][
                            case]["path"],
                        "--layers", "15,19",
                        "--out", os.path.join(
                            gdir, "cap_fmt_%s_d%d.json" % (case, k)))})
        steps_b.append({"step": "battery_M_B", "argv": py(
            T("tool/runs/a3_battery.py"), "--model", mirror,
            "--cells", cells, "--groups", "G0,G1,G2",
            "--out", os.path.join(gdir, "battery_M_B.jsonl"))})
        if arm == "arm-002":
            steps_b.append({"step": "battery_confounded", "argv": py(
                T("tool/runs/a3_battery.py"), "--model", mirror,
                "--cells", cells, "--groups", "G0,G1,G2",
                "--repair", os.path.join(spec_dir,
                                         "null3_unrelated_spec.json"),
                "--repair-out", os.path.join(gdir,
                                             "battery_confounded.jsonl"),
                "--repair-receipt", os.path.join(
                    gdir, "repair_receipt_confounded.json"))})
        steps_b.append({"step": "battery_null4", "argv": py(
            T("tool/runs/a3_battery.py"), "--model", mirror,
            "--cells", cells, "--groups", "G0,G1,G2",
            "--repair", os.path.join(spec_dir, "null4_quantnoise_spec.json"),
            "--repair-out", os.path.join(gdir, "battery_null4.jsonl"),
            "--repair-receipt", os.path.join(gdir,
                                             "repair_receipt_null4.json"))})
        steps_b.append({"step": "build_null3v2", "argv": py(
            os.path.join(HERE, "v1v2_null3v2.py"),
            "--cap-upper-d0", os.path.join(gdir, "cap_fmt_upper_d0.json"),
            "--cap-lower-d0", os.path.join(gdir, "cap_fmt_lower_d0.json"),
            "--cap-upper-d1", os.path.join(gdir, "cap_fmt_upper_d1.json"),
            "--cap-lower-d1", os.path.join(gdir, "cap_fmt_lower_d1.json"),
            "--d-hat", os.path.join(adir, "recovered.json"),
            "--repair-spec", os.path.join(adir, "repair_spec.json"),
            "--bank-record", banks_p,
            "--propose-tool", T("tool/runs/a3_propose.py"),
            "--out-spec", os.path.join(spec_dir, "null3v2_spec.json"),
            "--gate-receipt", os.path.join(gdir, "null3v2_gate.json"))})
        steps_b.append({"step": "battery_null3v2", "argv": py(
            T("tool/runs/a3_battery.py"), "--model", mirror,
            "--cells", cells, "--groups", "G0,G1,G2",
            "--repair", os.path.join(spec_dir, "null3v2_spec.json"),
            "--repair-out", os.path.join(gdir, "battery_null3v2.jsonl"),
            "--repair-receipt", os.path.join(
                gdir, "repair_receipt_null3v2.json"))})
        bb = {"batch": "%sB" % tag, "mirror_dir": mirror,
              "gates": [mirror_gate_b], "steps": steps_b}
        for b in (ba, bb):
            p = os.path.join(wm, "batches", "%s.json" % b["batch"])
            with open(p, "w", encoding="utf-8") as fh:
                json.dump(b, fh, indent=1)
            batch_digests[b["batch"]] = {"path": p, "sha256":
                                         sha256_file(p)}
    receipt["batches"] = batch_digests
    receipt["device_plan"] = {
        "lock_dir": os.path.join(tmp, LOCK_DIR_NAME),
        "law": "serial -j1; lock v3 (10s acquisition retries, 360 cap, "
               "wait_ms receipted, rmdir + 3s courtesy); per-batch device "
               "<= 20 min; ALL wall_ms rows wall_ms_claim=false (machine "
               "under heavy external load); power tagged per batch; "
               "POWER RULE: discharging => stop between mirrors, persist, "
               "POWER_BATTERY_STOP; mirrors swept every batch",
        "runner": "v12_batch.py REUSED UNMODIFIED (digest %s)"
                  % receipt["v12_helpers_sha256"]["tool/runs/"
                                                  "v12_batch.py"],
    }

    p = os.path.join(wm, "gen", "prep_receipt.json")
    with open(p, "w", encoding="utf-8") as fh:
        json.dump(receipt, fh, indent=1)
    print("PREP_OK %s" % p)
    print("prep_receipt_sha256 %s" % sha256_file(p))
    for name, d in batch_digests.items():
        print("batch %s %s" % (name, d["sha256"][:16]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
