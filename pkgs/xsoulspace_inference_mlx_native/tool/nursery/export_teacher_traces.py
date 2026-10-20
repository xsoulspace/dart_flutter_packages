"""Export verified teacher traces from a ZCode session database.

Why this exists: an adapter is only as good as its verification. The
session's own tool outcomes show the bias this script is built to correct —
`sess_46ea6b00` recorded 982 tool calls with 15 non-ok (1.5%). That is a
SUCCESS trace. A student trained on it learns the teacher's habits on tasks
it already solved, and learns nothing about repair, which is exactly the
capability a small model lacks.

So this exporter emits three kinds, and the `correction` kind is the one
worth training on:

  success     a tool call completed and (where checkable) exited 0
  failure     a tool call failed — kept, never dropped
  correction  a failure followed by a later success on the same tool in the
              same turn: the (broken -> fixed) pair

`verified` is a mechanical claim, not a judgement: exit_code == 0 for shell
tools, status == completed for the rest. Nothing here claims the teacher was
RIGHT — only that the tool did not error. A downstream trainer must still
gate on the repo's own checks (analyze/test) before treating a row as truth.

Usage:
  python tool/nursery/export_teacher_traces.py \
      --db ~/.zcode/cli/db/db.sqlite --session sess_... --out traces.jsonl
"""

import argparse
import json
import os
import sqlite3
import sys


def rows(conn, sql, args=()):
    cur = conn.execute(sql, args)
    cols = [c[0] for c in cur.description]
    for r in cur:
        yield dict(zip(cols, r))


def load_tools(conn, session):
    return list(
        rows(
            conn,
            """
        select tool_call_id, turn_id, tool_name, status, exit_code,
               duration_ms, output_bytes, stderr_bytes, started_at
        from tool_usage where session_id = ? order by started_at
    """,
            (session,),
        )
    )


def load_tool_inputs(conn, session):
    """The assistant's tool-call arguments, keyed by tool_call_id."""
    out = {}
    for m in rows(
        conn,
        """
        select id, data from message
        where session_id = ? and json_extract(data, '$.role') = 'assistant'
        order by sequence
    """,
        (session,),
    ):
        try:
            d = json.loads(m["data"])
        except Exception:
            continue
        for part in d.get("parts", []) or []:
            if part.get("type") not in ("tool", "tool-call", "tool_call"):
                continue
            cid = part.get("toolCallId") or part.get("id")
            if cid:
                out[cid] = part.get("input") or part.get("args") or {}
    return out


def classify(tools):
    """Group per turn and label success / failure / correction."""
    by_turn = {}
    for t in tools:
        by_turn.setdefault(t["turn_id"], []).append(t)

    records = []
    for turn, items in by_turn.items():
        seen_failure = {}
        for t in items:
            ok = (t["status"] == "completed") and (
                t["exit_code"] in (0, None) or t["exit_code"] == 0
            )
            name = t["tool_name"]
            if ok:
                kind = "correction" if name in seen_failure else "success"
                seen_failure.pop(name, None)
            else:
                kind = "failure"
                seen_failure[name] = t["tool_call_id"]
            records.append(
                {
                    "id": t["tool_call_id"],
                    "session": None,  # filled by caller
                    "turn": turn,
                    "kind": kind,
                    "tool": name,
                    "status": t["status"],
                    "exit_code": t["exit_code"],
                    "duration_ms": t["duration_ms"],
                    "stderr_bytes": t["stderr_bytes"],
                    "verified": bool(ok),
                    "verifier": "exit_code==0"
                    if t["exit_code"] is not None
                    else "status==completed",
                }
            )
    return records


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--db", default=os.path.expanduser("~/.zcode/cli/db/db.sqlite"))
    ap.add_argument("--session", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument(
        "--include-inputs",
        action="store_true",
        help="attach the tool-call arguments (larger, more useful for training)",
    )
    args = ap.parse_args(argv)

    conn = sqlite3.connect(f"file:{args.db}?mode=ro", uri=True)
    tools = load_tools(conn, args.session)
    inputs = load_tool_inputs(conn, args.session) if args.include_inputs else {}
    recs = classify(tools)
    for r in recs:
        r["session"] = args.session
        if args.include_inputs:
            r["input"] = inputs.get(r["id"], {})

    counts = {}
    for r in recs:
        counts[r["kind"]] = counts.get(r["kind"], 0) + 1
    with open(args.out, "w") as fh:
        for r in recs:
            fh.write(json.dumps(r, sort_keys=True) + "\n")
    print(
        json.dumps(
            {
                "session": args.session,
                "records": len(recs),
                "counts": counts,
                "correction_rate": counts.get("correction", 0) / max(1, len(recs)),
                "out": os.path.abspath(args.out),
            },
            indent=2,
        )
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
