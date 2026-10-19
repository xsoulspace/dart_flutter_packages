"""Run the TRAIN-GATES.md audit on a nursery candidate and stamp a verdict.

Each gate runs only when its inputs are given; GATE-2 and GATE-4 are
runnable pre-training (traces from any forward; the store exists at birth),
GATE-1/GATE-3 need a trained model's activations and predictions. Targets
come from a rung config file (JSON) — never defaults — per TRAIN-GATES.md:

  rung.json = {
    "gate1_target": 0.60,            # provisional until TRAIN-GATES says final
    "gate3_target": 0.90,
    "gate4": {"back_room_gb": 10.0, "bytes_per_token_mb": 25.0}
  }

Usage:
  python run_gates.py --config rung.json --store <store dir> \
      [--routes r.jsonl] [--activations a.jsonl] \
      [--predictions p.jsonl --labels l.jsonl] [--out gates.json]
"""

import argparse
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from common import stamp                                    # noqa: E402
import gate1_pole_legibility as gate1                       # noqa: E402
import gate2_route_persistence as gate2                     # noqa: E402
import gate3_label_agreement as gate3                       # noqa: E402
import gate4_payload as gate4                               # noqa: E402


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--config", required=True, help="rung config JSON")
    ap.add_argument("--store", help="packed store dir (GATE-4)")
    ap.add_argument("--routes", help="routes.jsonl trace (GATE-2)")
    ap.add_argument("--activations", help="pole activation rows (GATE-1)")
    ap.add_argument("--predictions", help="predicted labels (GATE-3)")
    ap.add_argument("--labels", help="teacher labels (GATE-3)")
    ap.add_argument("--out", help="write the stamped verdict JSON here")
    args = ap.parse_args(argv)

    with open(args.config) as fh:
        config = json.load(fh)
    # The rung file (e.g. rung0.json) nests targets under "gates"; accept
    # both that shape and the flat legacy one.
    targets = config.get("gates", config)
    gates, inputs = [], {}

    if args.store:
        inputs["store_manifest"] = os.path.join(args.store, "manifest.json")
        manifest_path = inputs["store_manifest"]
        g4cfg = targets["gate4"]
        verdict = gate4.run(manifest_path, g4cfg["back_room_gb"],
                            g4cfg["bytes_per_token_mb"])
        gates.append(verdict)
    if args.routes:
        inputs["routes"] = args.routes
        gates.append(gate2.run(args.routes))
    if args.activations:
        inputs["activations"] = args.activations
        gates.append(gate1.run(args.activations, targets["gate1_target"]))
    if args.predictions:
        inputs["predictions"] = args.predictions
        if args.labels:
            inputs["labels"] = args.labels
        gates.append(gate3.run(args.predictions, args.labels,
                               targets["gate3_target"]))

    if not gates:
        ap.error("nothing to audit: pass --store and/or --routes and/or "
                 "--activations and/or --predictions")
    stamp(gates, inputs, args.out)
    return 0 if all(g["passed"] for g in gates) else 1


if __name__ == "__main__":
    sys.exit(main())
