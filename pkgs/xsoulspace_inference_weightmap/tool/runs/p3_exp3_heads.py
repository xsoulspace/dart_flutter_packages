#!/usr/bin/env python3
"""p3_exp3_heads.py — PREREG-D §P-3 exp3 (language) corpus-rebuild check,
claimed-heads parse, and analytic induction-head DETECTOR VALIDATION.

Scope (frozen by task charter 2026-11-05): training the three char-level
transformers is OUT OF SCOPE; the detector is validated on a SYNTHETIC 2-layer
toy transformer constructed in-script (planted induction head must be found,
control heads must not) — detector validation, not model reading. The published
L4H6 blocks.npz weights are deliberately NOT fetched and NOT read; that gap is
recorded NAMED EXP3_NET_SCORING_OUT_OF_SCOPE.

============================ FROZEN RULES (freeze-it-in-code) ================
Written before any run (2026-11-05).

R-A MANIFEST INTEGRITY ("digest-check the manifest first"):
  A1 required files present, else NAMED MANIFEST_MISSING (refusal).
  A2 files.tsv header == the 9 columns their rebuild script reads
     (order, kind, package, version, path, sha256, normalized_chars,
      normalized_sha256, corpus_offset), else MANIFEST_DRIFT(header).
  A3 count of kind=="file" rows == stats.json "python"."parts", else
     MANIFEST_DRIFT(row_count).
  A4 corpus_sha256.txt parses to exactly 2 entries name->64-hex-digest
     (python.txt, python_heldout.txt), else MANIFEST_DRIFT(corpus_digests).
  Manifest-file sha256s recorded in the receipt line.

R-B REBUILD ATTEMPT (real mode only; into $TMPDIR, never the repo tree):
  Run THEIR scripts/rebuild_from_manifest.py as a subprocess (absolute paths,
  python -I, cwd outside the artifacts dir) with the wm-mlx venv site-packages
  as lookup root. Independently recompute sha256 of the rebuilt
  python.txt / python_heldout.txt and compare with corpus_sha256.txt.
  Any digest != published  ->  status MANIFEST_DRIFT with reason
  REBUILD_DIGEST_MISMATCH and the structural cause recorded (pinned
  torch==2.5.1+cu124 is linux-only; ast.unparse parity requires CPython
  3.10.12; host interpreter differs) -> exp3 disposition QUALITATIVE
  (PREREG-D: "Manifest digest drift -> exp3 downgrades to qualitative with
  NAMED reason"). Both digests OK -> corpus_rebuilt=true.

R-C CLAIMED-HEADS PARSE (their run-log ground truth):
  A head is a CLAIMED copying/induction head iff heads.json induct > 0.2.
  Cutoff frozen from THEIR published README ("Copying (induction) heads are
  the heads with induct > 0.2 ... every other head scores at most 0.019").
  claimed_heads_parsed = total across the three nets; the noise-floor max
  (largest induct <= 0.2) is recorded to evidence separation.

R-D ANALYTIC INDUCTION-HEAD DETECTOR (function over a weight dict; no model
  execution, no training). Weight-dict convention:
    W_E (d,V) embeddings; W_U (V,d) unembed; W_P (T,d) position embeddings;
    layers: list of {"heads": [{"W_q"(dh,d), "W_k"(dh,d), "W_v"(dh,d),
                                "W_o"(d,dh)}]}.
  Scores per head h:
    prev_token_score(h) = fraction of positions t in 1..T-1 where
      argmax_{s<t} S[t,s] == t-1, with S = W_P W_q^T W_k W_P^T  (QK circuit
      over positions; the previous-token signature).
    copy_score(h) = diag_score(W_U W_o W_v W_E), the OV circuit's identity-copy
      strength, diag_score(M) = sqrt(V)*trace(M)/||M||_F  (equals V for a
      perfect c*I copy circuit, ~1 for random).
    comp_score(h,g) = diag_score(W_E^T W_q_h^T W_k_h W_o_g W_v_g W_E) — the QK
      COMPOSITION signature: query token x matches the token y that head g
      wrote at a position; induction requires x==y (diagonal), i.e. "attend
      where the previous token equals me".
  Decision (frozen): g is ELIGIBLE iff prev_token_score(g) >= TAU_PREV=0.75.
  Head h in layer L>=1 is an INDUCTION head iff
    max over eligible g in layers < L of comp_score(h,g) >= TAU_IND=4.0
    AND copy_score(h) >= TAU_IND.
  Layer-0 heads are never induction (no earlier layer to compose with).
  TAU_IND=4.0 sits far above the random-matrix baseline (~1) and far below
  the perfect-circuit value (V); the toy controls measure the baseline
  empirically and their scores are recorded in the receipt.

R-E SYNTHETIC TOY VALIDATION (fixed construction, numpy, seeded):
  V=d=32, T=16, dh=32, W_E=W_U=I, W_P rows = unit vectors e_t.
  L0H0 PLANTED previous-token head: W_q=I, W_k = shift matrix (S[t,s]=1 iff
    s=t-1), W_v=W_o=I  -> prev_token_score must be 1.0, copy_score = V.
  L0H1 control: iid gaussian (seed 0) / sqrt(d).
  L0H2 same-token head: W_q=W_k=W_v=W_o=I (QK peaks at s=t, not t-1) ->
    prev_token_score must be < TAU_PREV (ineligible composition source).
  L1H0 PLANTED induction head: W_q=W_k=W_v=W_o=I -> comp with L0H0 = V
    (diagonal), copy = V -> must be FOUND.
  L1H1 control: iid gaussian (seed 1) / sqrt(d) -> must NOT be found.
  L1H2 anti-composition control: W_q=I, W_k = exchange matrix J (anti-
    diagonal), W_v=W_o=I (copy-capable, wrong composition) -> must NOT be
    found.
  detector_validated = ALL checks pass:
    planted found; controls not found; L0H0 prev-token flagged; L0H2 and
    L0H1 not prev-token eligible; no layer-0 head flagged induction.
===============================================================================

NAMED refusals: ARTIFACTS_DIR_MISSING, MANIFEST_MISSING, HEADS_PARSE_ERROR,
REBUILD_TIMEOUT, REBUILD_LAUNCH_ERROR, VENV_MISSING, OUT_WRITE_ERROR.
Statuses (verdicts, not defects): MANIFEST_DRIFT (with reason),
EXP3_NET_SCORING_OUT_OF_SCOPE.

Usage:
  p3_exp3_heads.py [--artifacts DIR] [--out FILE] [--rebuild-out DIR]
                   [--site-packages DIR]... [--rebuild-timeout S] [--dry-run]
  --dry-run: stdlib-only plan + manifest presence gate; NO numpy, NO network,
             NO subprocess, NO writes; exit 0 plan JSON or exit 1 NAMED.
Interpreter: any python3; REAL mode re-execs under
~/.local/share/wm-mlx/bin/python (poll <= 600 s, then NAMED VENV_MISSING).
Rebuild artifacts and outputs go to $TMPDIR only (probe scratch law).
"""

import argparse
import csv
import hashlib
import json
import os
import re
import subprocess
import sys
import time

EXPECTED_TSV_HEADER = ["order", "kind", "package", "version", "path", "sha256",
                       "normalized_chars", "normalized_sha256", "corpus_offset"]
TAU_IND = 4.0
TAU_PREV = 0.75
CLAIMED_INDUCT_CUTOFF = 0.2  # frozen from THEIR README (see R-C)

FROZEN_RULE = (
    "R-A manifest integrity (header/row-count/digest-file shape); "
    "R-B rebuild via THEIR script into $TMPDIR, digests vs corpus_sha256.txt, "
    "mismatch -> MANIFEST_DRIFT -> exp3 QUALITATIVE per PREREG-D; "
    "R-C claimed head iff heads.json induct > 0.2 (their README cutoff); "
    "R-D detector: prev_token QK signature + diagonal QK-composition through "
    "eligible prev-token heads + OV copy; TAU_IND=4.0, TAU_PREV=0.75; "
    "R-E seeded synthetic 2-layer toy: planted induction found, controls not."
)


def die(code, msg):
    sys.stderr.write(f"{code}: {msg}\n")
    sys.exit(1)


def ensure_numpy(poll_s=600, interval_s=10):
    try:
        import numpy as np  # noqa: PLC0415
        return np
    except ImportError:
        pass
    venv = os.path.expanduser("~/.local/share/wm-mlx/bin/python")
    if os.environ.get("WM_P3_REEXEC") == "1":
        die("VENV_MISSING",
            f"re-exec under {venv} already done but numpy import still fails "
            f"(interpreter: {sys.executable})")
    deadline = time.time() + poll_s
    while True:
        if os.path.exists(venv) and os.access(venv, os.X_OK):
            os.environ["WM_P3_REEXEC"] = "1"
            os.execv(venv, [venv, os.path.abspath(__file__), *sys.argv[1:]])
        if time.time() > deadline:
            die("VENV_MISSING",
                f"numpy absent under {sys.executable} and {venv} absent after "
                f"{poll_s}s poll")
        time.sleep(interval_s)


def venv_python():
    v = os.path.expanduser("~/.local/share/wm-mlx/bin/python")
    return v if os.path.exists(v) and os.access(v, os.X_OK) else sys.executable


def p3_paths(artifacts):
    pd = os.path.join(artifacts, "exp3_language", "python_dataset")
    return {
        "files_tsv": os.path.join(pd, "files.tsv"),
        "corpus_sha256": os.path.join(pd, "corpus_sha256.txt"),
        "packages": os.path.join(pd, "packages.txt"),
        "rebuild_py": os.path.join(pd, "rebuild_from_manifest.py"),
        "stats": os.path.join(pd, "stats.json"),
        "data_py": os.path.join(pd, "scripts", "tinylm", "data.py"),
        "data_big_py": os.path.join(pd, "scripts", "tinylm2", "data_big.py"),
        "heads": os.path.join(artifacts, "exp3_language", "eval", "heads.json"),
    }


def gate(artifacts):
    if not os.path.isdir(artifacts):
        die("ARTIFACTS_DIR_MISSING", artifacts)
    paths = p3_paths(artifacts)
    missing = [p for p in paths.values() if not os.path.exists(p)]
    if missing:
        die("MANIFEST_MISSING", "missing: " + ", ".join(sorted(missing)))
    return paths


def sha256_file(path, chunk=1 << 20):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        while True:
            b = fh.read(chunk)
            if not b:
                break
            h.update(b)
    return h.hexdigest()


# ---------------------------------------------------------------- R-A manifest
def manifest_check(paths):
    """Returns (ok: bool, record: dict). Any failure reason is a
    MANIFEST_DRIFT sub-reason; ok=False downgrades exp3 to qualitative."""
    rec = {"digests": {k: sha256_file(p) for k, p in paths.items()
                       if k != "heads"}}
    problems = []
    # A2 header
    with open(paths["files_tsv"], newline="") as fh:
        header = next(csv.reader(fh, delimiter="\t"))
    rec["tsv_header_ok"] = header == EXPECTED_TSV_HEADER
    if not rec["tsv_header_ok"]:
        problems.append(f"header_mismatch:{header}")
    # A3 row counts vs stats.json parts
    n_file = n_unid = n_other = 0
    with open(paths["files_tsv"], newline="") as fh:
        for row in csv.DictReader(fh, delimiter="\t"):
            k = row.get("kind")
            if k == "file":
                n_file += 1
            elif k == "unidentified":
                n_unid += 1
            else:
                n_other += 1
    try:
        stats = json.load(open(paths["stats"]))
        parts = stats["python"]["parts"]
    except (OSError, json.JSONDecodeError, KeyError) as e:
        parts = None
        problems.append(f"stats_unreadable:{e}")
    rec["rows"] = {"file": n_file, "unidentified": n_unid, "other": n_other,
                   "stats_parts": parts}
    rec["row_count_ok"] = parts is not None and n_file == parts
    if not rec["row_count_ok"]:
        problems.append(f"row_count:file_rows={n_file}!=stats_parts={parts}")
    # A4 corpus_sha256.txt shape
    want = {}
    for line in open(paths["corpus_sha256"]):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        fields = line.split()
        if len(fields) == 2 and re.fullmatch(r"[0-9a-f]{64}", fields[0]):
            want[fields[1]] = fields[0]
    rec["corpus_digests_expected"] = want
    rec["corpus_digest_file_ok"] = set(want) == {"python.txt",
                                                 "python_heldout.txt"}
    if not rec["corpus_digest_file_ok"]:
        problems.append(f"corpus_sha256_entries:{sorted(want)}")
    rec["ok"] = not problems
    rec["problems"] = problems
    return rec


# ------------------------------------------------------------------ R-B rebuild
def rebuild_attempt(paths, rebuild_out, site_roots, timeout_s, log_path):
    """Runs THEIR rebuild_from_manifest.py as a subprocess into $TMPDIR.
    Returns a record dict; never raises for expected failures."""
    rec = {"rebuild_out": rebuild_out, "site_roots": site_roots,
           "interpreter": venv_python(),
           "interpreter_version": None, "timeout_s": timeout_s}
    os.makedirs(rebuild_out, exist_ok=True)
    cmd = [rec["interpreter"], "-I", paths["rebuild_py"], rebuild_out,
           *site_roots]
    rec["cmd"] = cmd
    try:
        with open(log_path, "w") as log:
            proc = subprocess.run(cmd, stdout=log, stderr=subprocess.STDOUT,
                                  cwd=rebuild_out, timeout=timeout_s)
        rec["exit_code"] = proc.returncode
    except subprocess.TimeoutExpired:
        rec["status"] = "REBUILD_TIMEOUT"
        return rec
    except OSError as e:
        rec["status"] = "REBUILD_LAUNCH_ERROR"
        rec["detail"] = str(e)
        return rec
    ver = subprocess.run([rec["interpreter"], "-c",
                          "import sys;print(sys.version.split()[0])"],
                         capture_output=True, text=True)
    rec["interpreter_version"] = ver.stdout.strip()
    # independent digest comparison (R-B)
    rebuilt = {}
    for name, want in [("python.txt", None), ("python_heldout.txt", None)]:
        p = os.path.join(rebuild_out, name)
        rebuilt[name] = {"exists": os.path.exists(p),
                         "sha256": sha256_file(p) if os.path.exists(p) else None}
    expected = manifest_expected_digests(paths)
    ok = all(rebuilt[n]["exists"] and rebuilt[n]["sha256"] == expected.get(n)
             for n in expected)
    rec["rebuilt"] = rebuilt
    rec["digest_match"] = ok
    # tail of their stdout for the found/missing/bad counts
    try:
        tail = open(log_path).readlines()
        rec["their_summary"] = [l.rstrip() for l in tail
                                if ("sha256" in l or "files found" in l)]
        rec["their_missing_lines"] = sum(1 for l in open(log_path)
                                         if l.startswith("missing or different:"))
        rec["their_processed_differently_lines"] = sum(
            1 for l in open(log_path) if l.startswith("processed text differs"))
    except OSError:
        pass
    rec["status"] = "digest_ok" if ok else "REBUILD_DIGEST_MISMATCH"
    return rec


def manifest_expected_digests(paths):
    want = {}
    for line in open(paths["corpus_sha256"]):
        line = line.strip()
        if line and not line.startswith("#"):
            h, name = line.split()
            want[name] = h
    return want


# --------------------------------------------------------- R-C claimed heads
def parse_claimed_heads(paths):
    try:
        heads = json.load(open(paths["heads"]))
    except (OSError, json.JSONDecodeError) as e:
        die("HEADS_PARSE_ERROR", f"{paths['heads']}: {e}")
    claimed, floor = [], 0.0
    per_net = {}
    for net, hh in heads.items():
        names = []
        for head, m in hh.items():
            ind = float(m.get("induct", 0.0))
            if ind > CLAIMED_INDUCT_CUTOFF:
                claimed.append({"net": net, "head": head, "induct": ind})
                names.append(head)
            else:
                floor = max(floor, ind)
        per_net[net] = names
    return {"rule": f"induct > {CLAIMED_INDUCT_CUTOFF} (their README cutoff)",
            "claimed": claimed, "claimed_heads_parsed": len(claimed),
            "per_net": per_net, "noise_floor_max_induct": floor,
            "nets": len(heads), "heads_total": sum(len(h) for h in heads.values())}


# --------------------------------------------- R-D analytic detector (numpy)
def diag_score(np, m):
    """sqrt(V)*trace/||.||_F: V for perfect c*I (c>0), ~1 for random."""
    fro = float(np.linalg.norm(m))
    if fro == 0.0:
        return 0.0
    v = m.shape[0]
    return float(np.trace(m)) * (v ** 0.5) / fro


def detect_heads(np, w):
    """Analytic induction-head detector over a weight dict (R-D). Pure weight
    algebra: no forward passes, no data, no training."""
    we, wu, wp = w["W_E"], w["W_U"], w["W_P"]  # (d,V), (V,d), (T,d)
    layers = w["layers"]
    t = wp.shape[0]
    scores = []
    for li, layer in enumerate(layers):
        for hi, h in enumerate(layer["heads"]):
            a = h["W_q"].T @ h["W_k"]                    # (d,d) QK circuit
            s = wp @ a @ wp.T                            # (T,T) position QK
            prev_hits = 0
            for tt in range(1, t):
                if int(np.argmax(s[tt, :tt])) == tt - 1:
                    prev_hits += 1
            prev = prev_hits / (t - 1)
            ov = wu @ h["W_o"] @ h["W_v"] @ we           # (V,V) OV circuit
            copy = diag_score(np, ov)
            scores.append({"layer": li, "head": hi, "prev_token_score": prev,
                           "copy_score": copy, "comp_scores": {},
                           "induction": False, "best_g": None})
    # composition: only through ELIGIBLE prev-token heads in earlier layers
    for rec_h in scores:
        if rec_h["layer"] == 0:
            continue
        h = layers[rec_h["layer"]]["heads"][rec_h["head"]]
        best, best_g = 0.0, None
        for rec_g in scores:
            if rec_g["layer"] >= rec_h["layer"]:
                continue
            if rec_g["prev_token_score"] < TAU_PREV:
                continue  # ineligible composition source
            g = layers[rec_g["layer"]]["heads"][rec_g["head"]]
            c = we.T @ h["W_q"].T @ h["W_k"] @ g["W_o"] @ g["W_v"] @ we
            sc = diag_score(np, c)
            rec_h["comp_scores"][f"L{rec_g['layer']}H{rec_g['head']}"] = sc
            if sc > best:
                best, best_g = sc, f"L{rec_g['layer']}H{rec_g['head']}"
        rec_h["comp_best"] = best
        rec_h["best_g"] = best_g
        rec_h["induction"] = bool(best >= TAU_IND and rec_h["copy_score"] >= TAU_IND)
    return scores


# ------------------------------------------------- R-E synthetic toy (numpy)
def build_toy(np):
    """Fixed seeded construction per R-E. Returns (weights, expectations)."""
    v = d = 32
    t = 16
    rng = np.random.default_rng(0)
    i = np.eye(d)
    wp = np.zeros((t, d))
    wp[np.arange(t), np.arange(t)] = 1.0
    shift = np.zeros((d, d))  # S[t,s]=1 iff s=t-1 on the position block
    for tt in range(1, t):
        shift[tt, tt - 1] = 1.0
    same = np.zeros((d, d))   # identity on the position block (peaks at s=t)
    same[np.arange(t), np.arange(t)] = 1.0
    anti = np.zeros((d, d))   # exchange (anti-diagonal) on the position block
    for tt in range(t):
        anti[tt, t - 1 - tt] = 1.0

    def head(wq, wk, wv=None, wo=None):
        return {"W_q": wq, "W_k": wk,
                "W_v": i if wv is None else wv,
                "W_o": i if wo is None else wo}

    def rand_head(seed):
        r = np.random.default_rng(seed)
        s = d ** 0.5
        return head(r.standard_normal((d, d)) / s, r.standard_normal((d, d)) / s,
                    r.standard_normal((d, d)) / s, r.standard_normal((d, d)) / s)

    l0 = {"heads": [head(i, shift),                    # L0H0 planted prev-token
                    rand_head(0),                      # L0H1 random control
                    head(i, same)]}                    # L0H2 same-token
    l1 = {"heads": [head(i, i),                        # L1H0 planted induction
                    rand_head(1),                      # L1H1 random control
                    head(i, anti)]}                    # L1H2 anti-composition
    w = {"W_E": i.copy(), "W_U": i.copy(), "W_P": wp, "layers": [l0, l1]}
    _ = rng  # (rng reserved; construction is exact-matrix, seeded controls only)
    return w


def validate_detector(np):
    w = build_toy(np)
    scores = detect_heads(np, w)
    at = {(r["layer"], r["head"]): r for r in scores}
    checks = {
        "planted_induction_L1H0_found": at[(1, 0)]["induction"],
        "planted_induction_L1H0_composes_through_L0H0":
            at[(1, 0)]["best_g"] == "L0H0",
        "control_L1H1_random_not_found": not at[(1, 1)]["induction"],
        "control_L1H2_anti_composition_not_found": not at[(1, 2)]["induction"],
        "prev_token_L0H0_flagged": (at[(0, 0)]["prev_token_score"] >= TAU_PREV
                                    and at[(0, 0)]["copy_score"] >= TAU_IND),
        "prev_token_L0H0_not_induction": not at[(0, 0)]["induction"],
        "same_token_L0H2_not_prev_eligible":
            at[(0, 2)]["prev_token_score"] < TAU_PREV,
        "random_L0H1_not_prev_eligible":
            at[(0, 1)]["prev_token_score"] < TAU_PREV,
        "no_layer0_induction": not any(r["induction"] for r in scores
                                       if r["layer"] == 0),
    }
    return {"detector_validated": all(checks.values()), "checks": checks,
            "toy_scores": [{k: r[k] for k in
                            ("layer", "head", "prev_token_score", "copy_score",
                             "comp_scores", "induction", "best_g")}
                           for r in scores],
            "taus": {"TAU_IND": TAU_IND, "TAU_PREV": TAU_PREV}}


# --------------------------------------------------------------------- driver
def write_out(out_path, lines):
    try:
        os.makedirs(os.path.dirname(os.path.abspath(out_path)), exist_ok=True)
        with open(out_path, "w") as fh:
            for ln in lines:
                fh.write(json.dumps(ln) + "\n")
    except OSError as e:
        die("OUT_WRITE_ERROR", f"{out_path}: {e}")
    for ln in lines:
        print(json.dumps(ln))


def real_run(np, artifacts, out_path, rebuild_out, site_roots, timeout_s):
    paths = gate(artifacts)
    lines = []
    # R-A
    man = manifest_check(paths)
    lines.append({"kind": "manifest", "bench": "exp3_language",
                  "integrity_ok": man["ok"], "problems": man["problems"],
                  "digests": man["digests"], "rows": man["rows"],
                  "corpus_digests_expected": man["corpus_digests_expected"]})
    # R-B
    if man["ok"]:
        log_path = os.path.join(rebuild_out, "rebuild_stdout.log")
        reb = rebuild_attempt(paths, rebuild_out, site_roots, timeout_s, log_path)
    else:
        reb = {"status": "SKIPPED_MANIFEST_INCONSISTENT",
               "detail": "rebuild not attempted; manifest failed R-A"}
    lines.append({"kind": "rebuild", "bench": "exp3_language", **reb})
    drift = (not man["ok"]) or reb.get("status") != "digest_ok"
    drift_reason = None
    if not man["ok"]:
        drift_reason = "MANIFEST_INCONSISTENT:" + ";".join(man["problems"])
    elif reb.get("status") == "REBUILD_DIGEST_MISMATCH":
        drift_reason = ("REBUILD_DIGEST_MISMATCH: rebuilt corpus sha256 != "
                        "corpus_sha256.txt; structural cause: pinned package "
                        "set unavailable on this platform (torch==2.5.1+cu124 "
                        "linux-only) and ast.unparse parity requires CPython "
                        "3.10.12 (host: "
                        f"{reb.get('interpreter_version')})")
    elif reb.get("status") in ("REBUILD_TIMEOUT", "REBUILD_LAUNCH_ERROR",
                               "SKIPPED_MANIFEST_INCONSISTENT"):
        drift_reason = reb.get("status")
    # R-C
    claimed = parse_claimed_heads(paths)
    lines.append({"kind": "claimed_heads", "bench": "exp3_language", **claimed})
    # R-D + R-E
    det = validate_detector(np)
    lines.append({"kind": "detector_validation", "bench": "exp3_language",
                  "scope": "synthetic toy only; published blocks.npz NOT read",
                  **det})
    # disposition
    disposition = ("QUALITATIVE:MANIFEST_DRIFT(" + drift_reason + ")"
                   if drift else "QUANTITATIVE:corpus_rebuilt")
    lines.append({
        "kind": "summary", "arm": "P-3", "bench": "exp3_language",
        "corpus_status": "rebuilt_digest_ok" if not drift else "MANIFEST_DRIFT",
        "drift_reason": drift_reason,
        "disposition": disposition,
        "detector_validated": det["detector_validated"],
        "claimed_heads_parsed": claimed["claimed_heads_parsed"],
        "claimed_heads": [f'{c["net"]}:{c["head"]}' for c in claimed["claimed"]],
        "named_gaps": ["EXP3_NET_SCORING_OUT_OF_SCOPE: detector not run on the "
                       "published L4H6 blocks.npz (weights not fetched; task "
                       "scope = detector validation on synthetic toy; "
                       "training out of scope). PREREG-D P/R@k=4 vs run-log "
                       "heads therefore NOT scored this run."],
        "frozen_rule_sha256": hashlib.sha256(FROZEN_RULE.encode()).hexdigest(),
        "frozen_rule": FROZEN_RULE,
    })
    write_out(out_path, lines)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--artifacts",
                    default=os.path.join(os.environ.get("TMPDIR", "/tmp"),
                                         "p3-artifacts"))
    ap.add_argument("--out",
                    default=os.path.join(os.environ.get("TMPDIR", "/tmp"),
                                         "p3-results", "exp3.jsonl"))
    ap.add_argument("--rebuild-out",
                    default=os.path.join(os.environ.get("TMPDIR", "/tmp"),
                                         "p3-exp3-rebuild"))
    ap.add_argument("--site-packages", action="append", default=None)
    ap.add_argument("--rebuild-timeout", type=int, default=900)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    if args.dry_run:
        paths = gate(args.artifacts)  # NAMED MANIFEST_MISSING when absent
        print(json.dumps({
            "mode": "dry-run",
            "script": "p3_exp3_heads.py",
            "network": False,
            "numpy_imported": False,
            "subprocess_run": False,
            "writes": [],
            "manifest_files_present": {k: os.path.exists(p)
                                       for k, p in paths.items()},
            "frozen_rule": FROZEN_RULE,
            "frozen_rule_sha256":
                hashlib.sha256(FROZEN_RULE.encode()).hexdigest(),
            "plan": {
                "phases": ["R-A_manifest_integrity", "R-B_rebuild_attempt",
                           "R-C_claimed_heads_parse",
                           "R-D/R-E_detector_synthetic_validation"],
                "rebuild_out": args.rebuild_out,
                "site_roots_default": "wm-mlx venv site-packages",
                "claimed_cutoff": CLAIMED_INDUCT_CUTOFF,
                "taus": {"TAU_IND": TAU_IND, "TAU_PREV": TAU_PREV},
                "out": args.out,
            },
        }))
        return

    np = ensure_numpy()
    import glob as _glob
    roots = args.site_packages
    if not roots:
        roots = sorted(_glob.glob(os.path.expanduser(
            "~/.local/share/wm-mlx/lib/python3*/site-packages")))
        if not roots:
            die("VENV_MISSING", "no wm-mlx site-packages found for rebuild roots")
    real_run(np, args.artifacts, args.out, args.rebuild_out, roots,
             args.rebuild_timeout)


if __name__ == "__main__":
    main()
