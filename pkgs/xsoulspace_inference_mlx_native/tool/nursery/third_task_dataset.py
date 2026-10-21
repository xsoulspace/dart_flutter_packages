"""THIRD-TASK-4 — the DISSIMILAR third task for Line L (L-G7).

WHY THIS CORPUS EXISTS. `perm` and `veto` are BOTH permission requests: an
actor, an operation, a target path, a policy context. The 6 % foreign-label
leak measured on that pair (9/150 veto answers emitted the perm label
`abstain`) is therefore an UPPER BOUND for dissimilar pairs, and the
lower end was never measured. MTP-GATES.md Part 4 (L-G7) asks for a third
task with a DISJOINT label set, a majority class < 0.5 and every label
represented, so the leak can be measured where the tasks have nothing in
common.

THE TASK: "which family does this instrument belong to?" — a taxonomic
lookup over a musical performance.

    strings      violin, viola, cello, double bass, guitar, harp, lute
    woodwind     flute, clarinet, oboe, saxophone, bassoon, recorder
    brass        trumpet, trombone, french horn, tuba, cornet
    percussion   snare drum, timpani, cymbal, marimba, xylophone, tambourine

WHY THIS DOMAIN IS DISSIMILAR FROM THE OTHER TWO (and not merely
"different words"):

  * perm/veto are COMMANDS. The text names an actor, an operation, a target
    and a policy context, and the decision is "may this happen, and which
    veto fired". This task's texts are DECLARATIVE STATEMENTS about a
    performance. There is no actor, no operation, no target, no grant, no
    policy, and nothing that could be permitted or refused.
  * The decision axis is a TAXONOMY ("which family is this instrument in"),
    not a POLICY JUDGEMENT ("should this write be allowed"). A shared answer
    space over a policy task and a taxonomy task is exactly the stress test
    the leak metric needs.
  * The vocabulary is asserted DISJOINT from both corpora (see below), so a
    foreign-label answer on this task is unambiguously a leak and not an
    accidental word overlap.

THE FROZEN-CASE ASSERT (written BEFORE the generator loop — META-LESSONS 4:
"disjointness asserts on eval-adjacent corpora are not bureaucracy; the perm
corpus's assert caught 33 vocabulary collisions"). Two asserts, in this order:

  1. LABEL-SET DISJOINTNESS — the third task's labels must not intersect
     perm's or veto's. Hard assert BEFORE the loop: it is a property of the
     design, not of the data, so a violation is a bug, not a resample.
  2. VOCABULARY DISJOINTNESS — the third corpus's CONTENT words must not
     appear in the perm or veto corpora. A frame whose words collide is
     EXCLUDED (and the count reported); an instrument whose words collide is
     RESAMPED. A collision means the corpora share an answer-key word, which
     would make a leak reading ambiguous.

NON-DEGENERACY. The classes are cycled, so the majority class is ~0.25 (well
below 0.5) and every label is represented; the generator ASSERTS both rather
than assuming them. A degenerate corpus is worse than no corpus.

HONESTY BOUNDS.
  * The corpus teaches the taxonomy, not an answer key: the label is a
    property of the instrument named, computed by the lookup the generator
    uses.
  * The base model's ability to do this task is NOT claimed. If the base
    cannot do it, the arm can only report the leak, not an accuracy delta.
  * The task is deliberately LEARNABLE (each family has its own exclusive
    physical descriptor, so no row is ambiguous): an unlearnable third task
    would make both arms sit at chance and the gate vacuous.

The corpus is written under `bench/`, which is GITIGNORED: the tracked
artifact is THIS GENERATOR, exactly as for the veto corpus.

Usage:
  python tool/nursery/third_task_dataset.py \
      --out bench/nursery/data/third_task_dataset.jsonl
(deterministic: seed 0; re-running reproduces the file byte-for-byte)
"""

import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.dirname(os.path.dirname(HERE))
DATA = os.path.join(PKG, "bench", "nursery", "data")

THIRD_LABELS = ["strings", "woodwind", "brass", "percussion"]

# The other tasks' label sets. The assert below is written BEFORE the
# generator loop and is a hard failure: the disjointness of the label
# vocabularies is a property of the DESIGN.
OTHER_TASKS = {
    "perm": ["allow_once", "abstain"],
    "veto": ["no_grant", "destructive_op", "outside_workspace", "secret_path"],
}

# The instrument pools. Each family has its own instruments AND its own
# exclusive physical descriptor, so no row can be read two ways.
INSTRUMENTS = {
    "strings": [
        "violin",
        "viola",
        "cello",
        "guitar",
        "harp",
        "lute",
        "mandolin",
        "banjo",
    ],
    "woodwind": [
        "flute",
        "clarinet",
        "oboe",
        "saxophone",
        "bassoon",
        "recorder",
        "panpipes",
        "shawm",
    ],
    "brass": [
        "trumpet",
        "trombone",
        "french horn",
        "tuba",
        "cornet",
        "euphonium",
        "flugelhorn",
    ],
    "percussion": [
        "snare drum",
        "timpani",
        "cymbal",
        "marimba",
        "xylophone",
        "tambourine",
        "bass drum",
        "castanets",
    ],
}

DESCRIPTORS = {
    "strings": "with a bridge and a tailpiece",
    "woodwind": "with a slender bore and a single reed",
    "brass": "with a coiled tube and three valves",
    "percussion": "with a stretched membrane over a tuned shell",
}

# The sentence frames are SHARED across the families: the frame must never be
# a cue, or the task would be solved by the frame instead of the instrument.
# The frames are also the corpus's VARIETY: with the instrument pools they
# must yield enough DISTINCT texts for the corpus size, or the generator
# would have to repeat itself (and a corpus of repeated texts is a
# degenerate corpus wearing a disguise).
FRAMES = [
    "the ensemble featured {inst} {desc} in the second movement",
    "{desc}, the {inst} carried the melody",
    "a soloist played {inst} {desc} through the whole passage",
    "the programme opened with {inst} {desc}",
    "during the rehearsal, {inst} {desc} dominated the texture",
    "the quartet used {inst} {desc} for its closing number",
    "{inst} {desc} appeared in every chamber piece of the evening",
    "at {place}, {inst} {desc} joined the ensemble",
    "{place} heard {inst} {desc} in its opening programme",
    "the {place} programme paired {inst} {desc} with a quartet",
    "{inst} {desc} was the evening's centrepiece at {place}",
    "an evening at {place} ended with {inst} {desc}",
]

# The venues. Another axis of variety, and another axis of vocabulary
# collision (a venue name that shares a word with a permission corpus would
# be an answer-key collision).
PLACES = [
    "the town hall",
    "the old opera house",
    "a recording studio",
    "the city concert hall",
    "an open-air stage",
    "a rehearsal room",
    "the school auditorium",
    "a church in the hills",
    "the riverside pavilion",
    "a disused chapel",
]

# Generic English words. The vocabulary assert is about CONTENT words: a
# shared function word is not an answer-key collision.
STOPWORDS = set(
    """
    a an the and or of to in on at for by with from is are was were be been
    being it its this that these those there their them they he she his her
    him we us our you your i me my as if but not no so than then when while
    into over under out up down about after before every each all any some
    """.split()
)

WORD_RE = re.compile(r"[a-z]+")


def content_words(text):
    """The content words of a text (lowercased, alphabetic, stopwords out)."""
    return {w for w in WORD_RE.findall(text.lower()) if w not in STOPWORDS}


def assert_label_sets_disjoint(third_labels, other_tasks):
    """THE FROZEN-CASE ASSERT, part 1: the label vocabularies.

    Written BEFORE the generator loop, on purpose. A violation here is a
    design bug, not a data problem: it cannot be fixed by resampling, and
    it would make a cross-task prediction ambiguous (a foreign answer would
    be a lucky hit instead of a miss).
    """
    third = set(third_labels)
    for task, labels in other_tasks.items():
        clash = third & set(labels)
        if clash:
            raise SystemExit(
                f"the third task's labels are NOT disjoint from {task}'s: "
                f"{sorted(clash)}. Fix the design (this is a hard assert, "
                f"not a resample)."
            )
    print(
        "label-set disjointness: OK "
        f"({sorted(third)} vs { {t: sorted(v) for t, v in other_tasks.items()} })"
    )


def load_corpus_vocabulary(paths):
    """The content words of the eval-adjacent corpora (perm and veto).

    These are the corpora a leak would come FROM, and the corpora whose
    answer-key words must not appear here.
    """
    words = set()
    rows = 0
    for path in paths:
        if not os.path.exists(path):
            print(
                f"WARNING: corpus {path} is not present — the vocabulary "
                f"disjointness law is NOT binding for this run.",
                file=sys.stderr,
            )
            continue
        with open(path) as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                d = json.loads(line)
                rows += 1
                words |= content_words(d.get("text") or "")
    return words, rows


def generate(n_rows, seed, forbidden_words, other_label_texts):
    """The corpus. Deterministic given the seed.

    `forbidden_words` are the eval-adjacent corpora's content words: a row
    that contains one of them is RESAMPLED (the row would share an
    answer-key word with another corpus).

    A POOL whose own words collide is EXCLUDED wholesale rather than
    resampled away: the collision is systematic, so resampling rows that
    use that pool would spin forever. Every exclusion is COUNTED and
    reported — a silently dropped pool is a quiet hole in the corpus.
    """
    import random

    rng = random.Random(seed)
    usable_frames = []
    excluded_frames = []
    for f in FRAMES:
        if content_words(f.format(inst="", desc="", place="")) & forbidden_words:
            excluded_frames.append(f)
        else:
            usable_frames.append(f)
    if not usable_frames:
        raise SystemExit(
            "every sentence frame collides with the eval-adjacent corpora — "
            "the frames must be rewritten, not resampled away"
        )
    usable_places = []
    excluded_places = []
    for p in PLACES:
        if content_words(p) & forbidden_words:
            excluded_places.append(p)
        else:
            usable_places.append(p)
    if not usable_places:
        raise SystemExit(
            "every venue collides with the eval-adjacent corpora — the venue "
            "pool must be rewritten"
        )
    # The same for the family descriptors: a descriptor that collides would
    # make every row of that family collide.
    usable_desc = {}
    excluded_desc = {}
    for fam, d in DESCRIPTORS.items():
        if content_words(d) & forbidden_words:
            excluded_desc[fam] = d
        else:
            usable_desc[fam] = d
    if excluded_desc:
        print(
            "WARNING: family descriptors excluded for vocabulary collisions: "
            f"{excluded_desc}",
            file=sys.stderr,
        )
    for fam in THIRD_LABELS:
        if fam not in usable_desc:
            raise SystemExit(
                f"every descriptor for {fam!r} collides with the eval-adjacent "
                "corpora — the descriptors must be rewritten"
            )
    # And for the instruments themselves.
    usable_inst = {}
    excluded_inst = {}
    for fam, insts in INSTRUMENTS.items():
        keep = [i for i in insts if not (content_words(i) & forbidden_words)]
        dropped = [i for i in insts if i not in keep]
        if dropped:
            excluded_inst[fam] = dropped
        if not keep:
            raise SystemExit(
                f"every instrument for {fam!r} collides with the eval-adjacent "
                "corpora — the instrument pool must be rewritten"
            )
        usable_inst[fam] = keep
    if excluded_inst:
        print(
            f"WARNING: instruments excluded for vocabulary collisions: {excluded_inst}",
            file=sys.stderr,
        )

    rows = []
    seen = set()
    attempts = 0
    collisions = 0
    while len(rows) < n_rows:
        attempts += 1
        if attempts > n_rows * 400:
            raise SystemExit(
                "generator could not diversify past the vocabulary-disjointness "
                "law — the pools are too small"
            )
        # The classes are cycled, so they are balanced BY CONSTRUCTION.
        label = THIRD_LABELS[len(rows) % len(THIRD_LABELS)]
        inst = rng.choice(usable_inst[label])
        frame = rng.choice(usable_frames)
        desc = usable_desc[label]
        place = rng.choice(usable_places) if "{place}" in frame else ""
        text = frame.format(inst=inst, desc=desc, place=place)
        # The drift guard: the row must land as intended.
        if classify(inst) != label:
            continue
        # The frozen-case law, per row: resample on a hit.
        if content_words(text) & forbidden_words:
            collisions += 1
            continue
        if text in seen:
            continue
        seen.add(text)
        rows.append({"id": "third-%05d" % len(rows), "kind": label, "text": text})
    return rows, {
        "attempts": attempts,
        "resampled_on_vocabulary_collision": collisions,
        "frames_excluded": excluded_frames,
        "descriptors_excluded": excluded_desc,
        "instruments_excluded": excluded_inst,
        "places_excluded": excluded_places,
        "distinct_texts": len(seen),
    }


def classify(instrument):
    """The family of an instrument, by lookup. A deterministic function."""
    for fam, insts in INSTRUMENTS.items():
        if instrument in insts:
            return fam
    return None


def assert_non_degenerate(rows, labels):
    """THE NON-DEGENERACY ASSERT (K'-G3's bar, which L-G7 adopts).

    A degenerate corpus is worse than no corpus: it cannot show anything.
    """
    dist = {}
    for r in rows:
        dist[r["kind"]] = dist.get(r["kind"], 0) + 1
    n = max(1, len(rows))
    majority = max(dist.values()) / n
    missing = [l for l in labels if dist.get(l, 0) == 0]
    if missing:
        raise SystemExit(f"labels with no examples: {missing} — degenerate corpus")
    if majority >= 0.5:
        raise SystemExit(
            f"the majority class is {majority:.4f} (>= 0.5) — degenerate corpus"
        )
    return dist, majority


def file_digest(path):
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--out", default=os.path.join(DATA, "third_task_dataset.jsonl"))
    ap.add_argument("--rows", type=int, default=900)
    ap.add_argument("--seed", type=int, default=0)
    args = ap.parse_args(argv)

    # ---- THE FROZEN-CASE ASSERTS, BEFORE the generator loop ----
    assert_label_sets_disjoint(THIRD_LABELS, OTHER_TASKS)
    corpus_paths = [
        os.path.join(DATA, "perm_corpus_clause.jsonl"),
        os.path.join(DATA, "veto_branch_dataset.jsonl"),
    ]
    forbidden, corpus_rows = load_corpus_vocabulary(corpus_paths)
    print(
        f"vocabulary disjointness: {len(forbidden)} content words in the "
        f"eval-adjacent corpora ({corpus_rows} rows) are forbidden here"
    )

    rows, gen_meta = generate(args.rows, args.seed, forbidden, OTHER_TASKS)
    dist, majority = assert_non_degenerate(rows, THIRD_LABELS)

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w") as fh:
        for r in rows:
            fh.write(json.dumps(r) + "\n")

    # The manifest: the SAME shape as the veto corpus's manifest, plus the
    # corpus sha256 (the veto manifest predates that field).
    manifest = {
        "generator": "third_task_dataset.v1",
        "rows": len(rows),
        "seed": args.seed,
        "labels": THIRD_LABELS,
        "distribution": dist,
        "majority_accuracy": majority,
        "frozen_case_disjointness": {
            "pairs_checked": corpus_rows,
            "triples_checked": len(forbidden),
            "emitted": "resample on hit",
        },
        "note": (
            "The third, semantically DISSIMILAR task for L-G7: a musical "
            "instrument family (a taxonomy lookup), not a permission request "
            "(a policy judgement). The label set is disjoint from perm's and "
            "veto's, and the corpus's content words are disjoint from both "
            "corpora, so a foreign-label answer here is unambiguous. The "
            "base model's ability to do this task is NOT claimed."
        ),
        "sha256": file_digest(args.out),
    }
    with open(args.out + ".manifest.json", "w") as fh:
        json.dump(manifest, fh, indent=2)
    print(json.dumps(manifest, indent=2))
    print(
        f"generator notes: attempts {gen_meta['attempts']}, resampled on "
        f"vocabulary collision {gen_meta['resampled_on_vocabulary_collision']}, "
        f"distinct texts {gen_meta['distinct_texts']}, frames excluded "
        f"{gen_meta['frames_excluded']}, descriptors excluded "
        f"{gen_meta['descriptors_excluded']}, instruments excluded "
        f"{gen_meta['instruments_excluded']}, places excluded "
        f"{gen_meta['places_excluded']}"
    )
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
