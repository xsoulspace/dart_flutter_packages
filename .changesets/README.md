# Pending release intents

One markdown file per release intent, consumed by the dart_changesets
assembler when the version PR is built. Format:

```markdown
---
'package_name': minor
---

What changed, as changelog prose.
```

Create one with `just changesets-add`. Consumed files are deleted when the
version PR is applied; see [PUBLISHING.md](../PUBLISHING.md) for the full
flow and ADR 0073 for the decision record.
