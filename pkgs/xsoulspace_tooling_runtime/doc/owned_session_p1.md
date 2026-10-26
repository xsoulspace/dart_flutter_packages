# Owned session protocol p1

Reference leader: `tool/owned_session_p1_leader.pl` (Perl today; same argv and
channel contract will move to **oka** `oka_process` without changes). Host
admission policy (deadlines, `runBounded`, harness lifecycle) stays in
`xsoulspace_tooling_runtime` until callers switch transports.

## Launcher argv

After the host picks a system Perl (or future compiled helper), argv is:

```text
<leader> --protocol 1 --mode owned|single --marker <nonce> [--control <sockpath>]
  [--graceful <hook>] [--graceful-timeout <seconds>]
  -- <target> <target-argv…>
```

- `--protocol 1` — required; any other value is refused.
- `--mode owned` — session leader with PGID anchor and control socket.
- `--mode single` — no separate leader; exec in the session-leader PID (no
  `--control`; handshake is stderr-only).
- `--marker <nonce>` — authenticates the first control line and stderr bootstrap.
- `--control <sockpath>` — required for `owned`; host listens on a `0700` temp
  directory Unix socket.
- `--graceful <hook>` — optional executable run **before** `term` forwards
  SIGTERM (not before `kill`). Hook receives the marker as argv1 and must see
  `BOUNDED_SESSION_MARKER` equal to the marker (identity check). Runs inside
  the observation budget (`--graceful-timeout`, default **2** seconds). Status
  lines `graceful:ok`, `graceful:fail:<waitstatus>`, or `graceful:timeout` are
  advisory only — never settlement evidence. On hang or failure the leader
  still escalates on schedule (`term` → group TERM+CONT, then host `kill`).
- `--` — separates leader flags from the admitted target argv vector.

Unknown flags are ignored (forward-compatible).

## Stderr bootstrap (owned)

First line (exact):

```text
<marker>:ready:<sid>:p1:<impl>
```

`<impl>` is `perl` for the reference script. `<sid>` is the session id from
`setsid()`.

Target stderr follows unchanged after bootstrap. Exec failure before `started`:

```text
<marker>:error:<stage>:<detail>
```

Never exit **127** as the contract outcome for exec failure (the leader exits
with a non-zero status after emitting the error line).

## Stderr bootstrap (single)

```text
<marker>:ready:<sid>
<marker>:started
```

## Control channel (owned)

1. Leader connects to `--control`, writes `<marker>\n`, flushes.
2. Host must reject lines before authentication.
3. Leader → host status lines (newline-terminated UTF-8):
   - `started` — target exec succeeded.
   - `exit:<waitstatus>` — main target reaped (`wait` status integer, not exit
     code).
   - `term-forwarded` — `kill(0, SIGTERM)` then `kill(0, SIGCONT)` on the
     leader's process group.
   - `killed-group` — `kill(0, SIGKILL)` on the group.
   - `settled` — response to host `settle`.
   - `unsettled:<reason>` — observation or host-death guard.
   - `graceful:ok` | `graceful:fail:<n>` | `graceful:timeout` — optional hook
     outcome (not settlement).
4. Host → leader commands:
   - `term` — optional graceful hook, then group TERM+CONT.
   - `kill` — group SIGKILL via leader (`kill(0, 9)`); host must not
     `SIGKILL` the leader directly while the channel is healthy.
   - `settle` — leader acknowledges `settled` and may exit cleanly.

**EOF** on the control socket (host died): leader kills the group, emits
`unsettled:host-eof` when possible, exits non-zero.

Before re-raising a signal-encoded exit, the leader restores the default
handler for that signal and reports the explicit wait status on the channel.

## File descriptors

| FD | Leader (owned) | Target |
|----|----------------|--------|
| stdin | inherited from host | inherited at fork, then replaced by exec |
| stdout | inherited | inherited |
| stderr | bootstrap then target | target only after exec |
| control | Unix stream socket | — |

Close-on-exec pipe detects target exec failure before `started`.

## Signal rules

- Group signals use `kill(0, sig)` from the leader (same PGID).
- `term` command: optional graceful hook, then SIGTERM to group, then SIGCONT
  (unstop TERM-ignoring members).
- `kill` command: SIGKILL to group through the leader only.
- Leader `SIGTERM` handler forwards TERM+CONT to the group (orphan safety).
- Host `ps` enumeration uses a bounded budget (2s); missing `ps` is
  `unsettled`, not silent death certification. No stale-snapshot per-pid
  `killPid` fallback.

**Windows** is out of scope for this contract revision (macOS and Linux only).

## Graceful hook (optional)

Configured with `--graceful` / `--graceful-timeout`. Invoked only on `term`,
before group TERM+CONT. Must validate `BOUNDED_SESSION_MARKER` (and argv marker).
Timeout and failures produce `graceful:*` lines only; escalation timing is
unchanged.
