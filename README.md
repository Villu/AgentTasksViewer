# AgentTasksViewer

Two small tools for a task queue that lives in a markdown file — the arrangement
several coding agents can share without a database between them.

- **`tasks-ready`** — what can be started right now, and why everything else cannot.
- **`tasks-board`** — the same queue as a self-contained HTML page, with every task
  expandable to its full text, and a `--watch` mode that keeps an open tab current.

No database, no daemon, no server, no dependencies beyond `bash` and `awk`. The
markdown file is the only source of truth and both tools are views of it.

## Why a file and not a tracker

This came out of running a coordinator plus worker agents against one repository,
where the queue was a markdown file and claims were kept in an append-only event
log with its own CLI. The log was removed after a night of measurement: **33 claims,
and not one task was ever claimed by two agents.** It arbitrated nothing, because
assignment settled ownership before any claim was written. What it did produce was
ten distinct ways for a claim to fail while the terminal looked fine — a push
reporting success having sent nothing, refusals exiting zero, one status word
meaning two opposite things, state splitting between the log and the file in both
directions, and a CI gate that turned out to be advisory so its green proved nothing.

The lesson was not that tracking is bad. It was that **a second store drifts from
the first, and then you have two answers and no way to say which is wrong.** The one
capability worth keeping from the tooling was the query — "what is startable?" —
which does not need a store at all. That is `tasks-ready`. `tasks-board` is the same
answer for human eyes.

So: generated, never authoritative. Delete the HTML and regenerate it; nothing is
lost, because nothing lived there.

## Install

```bash
git clone https://github.com/Villu/AgentTasksViewer.git
cd AgentTasksViewer && chmod +x tasks-ready tasks-board
```

Put them on your `PATH`, or copy `tasks-ready`, `tasks-board` and `tasks-board.awk`
into your repo's `ops/` or `scripts/`. `tasks-board` looks for `tasks-board.awk`
beside itself.

Requires `bash` and any POSIX `awk` (gawk, mawk and BusyBox awk all work). Tested on
Linux, macOS, Git Bash and WSL.

## Use

```bash
tasks-ready                      # what can start now
tasks-ready --all                # and what cannot, with the reason for each
tasks-board                      # write ./tasks-board.html
tasks-board --watch              # re-render on every change; the page refreshes itself
tasks-board --watch 2 --out docs/board.html --title "Platform queue"
```

Both default to `./TASKS.md`, overridable with `--file` or `$TASKS_FILE`.

Gitignore the HTML. A committed snapshot is a second copy that ages.

## The three rules

A task is **ready** when all three hold, and the third is the one people skip:

1. **Nobody has claimed it** — no `(@actor)` on its checkbox line.
2. **Nothing blocks it** — no `**Blocked**`, and every id in `**Blocked by**` has
   gone from the file. Removing a task's block is how the queue records that it is
   done, so a dependency that is still present is a dependency that is still open.
   No extra state, and nothing to keep in sync.
3. **Its files are free** — no path in its `**Files**` appears in the `**Files**` of
   a task somebody already holds.

Rule 3 is why this exists. "Nobody else owns this file" means *the whole file*, not
just the tasks in progress — a file with no live claim can still be spoken for by a
task nobody has picked up, and the collision then arrives at the worst moment. It is
one `grep` per path, which is exactly the check a person skips and a script does not.

## The format

Ordinary markdown. `##` headings set priority; each task is a checkbox line followed
by indented `- **Field**: value` lines.

```markdown
## P1

- [ ] Nothing writes an audit row, so the audit log is empty (@alex)
  - **ID**: audit-write-path
  - **Details**: `audit.record()` exists, is tested, and has no caller in `src/`.
  - **Files**: `src/audit/writer.py`, `tests/test_audit.py`
  - **Acceptance**: A request through the composed middleware writes a row,
    asserted by reading the row rather than by calling `record()` directly.
  - **Blocked by**: session-persistence
  - **Blocked**: only the user can open the port on the load balancer
  - **Note**: anything worth carrying to whoever picks this up
  - **Tags**: audit, security
```

| field | used for |
|---|---|
| `**ID**` | the handle; referenced by `**Blocked by**` |
| `**Files**` | ownership. Backticked paths, and the basis of rule 3 |
| `**Blocked by**` | comma-separated ids. Unmet while the id is still in the file |
| `**Blocked**` | prose reason, for what no task id can express — a person, a date, a decision |
| `**Details**`, `**Acceptance**`, `**Note**` | shown when a card is expanded; repeatable |
| `**Tags**` | shown on the card |
| `(@actor)` | on the checkbox line: this task is held |

Only the checkbox line and `**ID**` are required. Everything else is optional, and
unknown fields are ignored rather than rejected, so the file stays yours.

Priorities are any `## P<n>`. `P0` sorts first.

Try it:

```bash
tasks-ready --file examples/TASKS.md --all
tasks-board --file examples/TASKS.md --out /tmp/board.html --title "Example queue"
```

## The board

Counts by state, a stacked bar per priority, and one card per task. Clicking a card
expands it to the full `Details`, `Files`, `Acceptance` and `Notes`, with backticks
and bold rendered — the whole block a worker would read, without opening the file.

It is one HTML file with no external requests: no CDN, no fonts, no analytics.
Light and dark follow the system, and it works at phone width. Under `--watch` the
page carries a meta refresh; a small inline script keeps the open cards and the
scroll position across it, wrapped in `try`/`catch` so the board still renders where
`sessionStorage` throws.

## Keeping the two in step

`tasks-ready` and `tasks-board.awk` each implement the three rules. That is a
duplication, and it is the kind that drifts. It is called out at the top of
`tasks-board.awk`: **if you change one, change the other in the same commit.** A
shared implementation would mean a library, a version and an install story, for
about forty lines of awk. Stated rather than hidden.

## Licence

MIT. See [LICENSE](LICENSE).
