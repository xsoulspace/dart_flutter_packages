# ADR 0068: File-state recovery through the existing provider and journal

- Status: Accepted implementation direction; qualification remains required
- Date: 2026-10-13
- North Star impact: applies — strengthens existing native storage recovery
- Decision maker: operator authorization to implement recovery fixes and extractions
- Extends: ADR 0062; preserves native writer ownership and legacy records

## Context

Actual native recovery restored deleted and updated 0600 text as 0644. A
foreign mode-only edit was also overwritten while rollback reported success.
The current journal describes content and presence; it cannot justify metadata
restoration. A host chmod after restoration would expose private bytes before
their permissions are restored and duplicate the recovery owner.

## Decision

Add an optional typed file-state capability to universal_storage_interface.
It observes content/presence and POSIX rwx mode, declares the intended state,
and restores a state through the existing native provider. Mandatory cloud and
memory provider methods are unchanged. The initial profile is posix-rwx-v1;
symlinks, nonregular files and special mode bits refuse. This profile makes no
ACL, owner/group, inode, timestamp, extended-attribute or power-loss claim.

Live-apply schema v3 records the provider profile and prior, intended post and
pending-pre permission modes. Present states require valid modes; absent states
have none. Mutation admission, settlement, discard and inverse preflight compare
presence, content hash and mode together. Missing/incompatible capabilities at
reopen refuse before effects. Never infer missing historical modes from current
files. Existing v1/v2 records retain their content-only contracts and existing
ambiguity refusals; they are not silently upgraded to metadata-qualified records.
Content-only providers retain their legacy recovery route. A metadata-aware
native provider refuses an old journal with missing historical modes before
inverse effects; current permissions cannot establish deleted prior metadata.

Filesystem restoration extends the existing durability journal. Create an
exclusive staging file with restrictive permissions before writing private
bytes, flush content, apply and verify the declared mode before publication,
record the prepared content/mode state, then replace the destination atomically
on a supported same-filesystem POSIX route. Remove delete-before-rename from
this qualified route. Recovery verifies both properties of a prepared staging
file or already-published target before acknowledging it. An unexplained mode
is a refusal, not permission to chmod a foreign target.

The existing live-apply lock and host writer exclusion remain authoritative.
This is not compare-and-swap against arbitrary external writers or atomic
visibility of a whole batch. Interrupted inverse recognizes only complete
recorded states, including both content and mode. No new rollback executor,
authority grant, scheduler or transaction store is introduced.

Retain bounded successful provider durability receipts in the existing v3
entry, in effect order with forward/inverse phase. Select only the existing
protocol, namespace, sequence, operation ID and checkpoint sequence from the
actual native result; the enclosing journal supplies run/path correlation.
Do not copy arbitrary provider metadata or fabricate a receipt for an effect
that threw, lacked metadata, or was merely recognized after restart. This is
post-effect audit evidence, not write-ahead authorization or proof of custody
origin. A crash before receipt persistence remains an explicit evidence gap.
Independent custody observation and actor exclusion remain required; a
parseable receipt alone grants no authority or oracle exemption.

## Qualification

Require actual deletion/update/Undo at 0600, 0644 and 0755; mode-only foreign
drift before rollback/finalization; complete multi-file preflight; restart under
a different umask; missing or wrong state adapter; malformed v3 and unchanged
legacy handling; staging/permission failure without a restored checkpoint;
process interruption before/after forward publication and during inverse
staging/publication/checkpointing. Existing content-only controls must continue
to pass. Process-kill tests do not establish hardware power-loss durability.

Interim host permission restrictions stay until their replacement path and
owning gates qualify. Coding-model, external-agent and product acceptance are
separate requirements under harness ADR 0091.
