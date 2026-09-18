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
tasks-board                      # write ./tasks-board.html, once
tasks-board --serve              # re-render on change AND serve it, so it stays current
tasks-board --serve 9000         # the same on a port you choose (default 8787)
tasks-board --watch              # re-render on change without serving (see the warning below)
tasks-board --serve 8787 --out docs/board.html --title "Platform queue"
tasks-board --serve --ref origin/main    # render the queue as the remote has it
```

Then open the URL `--serve` prints — `http://127.0.0.1:8787/tasks-board.html`.
Leave the tab open and it reloads itself whenever the task file changes.

Both default to `./TASKS.md`, overridable with `--file` or `$TASKS_FILE`.

**Use `--ref` when more than one machine writes the queue.** Without it the board
renders *your working copy*, so a claim somebody else pushed is invisible until you
pull — and nothing on the page can tell you: it correctly reports that it matches
the render it was given, while that render is of a stale file. It is the same
mistake as the banner below, one level further out, and it is the more dangerous
one, because a coordinator assigns work from what the board shows.

```bash
tasks-board --serve --ref origin/main            # track what the fleet sees
tasks-board --serve --ref origin/main --file docs/TASKS.md
```

With `--ref`, `--file` is a path inside the repository rather than on disk, a
remote ref is fetched before every check, and change detection is the file's blob
sha instead of an mtime. The page then names what it rendered — *a view of
`origin/main:TASKS.md`* — so a board of somebody else's branch cannot be mistaken
for your own checkout. Without `--ref` nothing changes: it reads the working copy
and says *a view of the task file*.

**Prefer `--serve` over `--watch`.** A board opened as a `file://` URL cannot read
the stamp written beside it, so it cannot tell whether it is still the current
render. It will say so on the page rather than claim to be live — but it will not
update. `--serve` needs `python3` on `PATH` and serves only on `127.0.0.1`; without
one it falls back to `--watch` and says so.

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
Light and dark follow the system, and it works at phone width. A small inline script
keeps the open cards and the scroll position across a reload, wrapped in `try`/`catch`
so the board still renders where `sessionStorage` throws.

**The page verifies that it is current; it never asserts it.** Each render writes its
epoch to a `.stamp` file beside the HTML and bakes the same number into the page. The
page re-reads that stamp on an interval and reports what it found: `live, checked
15:42:57` when it matches, a reload when the stamp is newer, and `NOT refreshing`
naming the reason when it cannot read it at all. A one-shot render says `snapshot`
and counts up how long ago it was written, because it makes no claim to be current.

This replaced a meta refresh and an unconditional "live, refreshing every 5s" banner.
That banner was wrong wherever the refresh could not reach the file — a `file://` page
in an embedded viewer reloaded a snapshot of itself every five seconds and went on
printing "live" while the queue moved underneath it. The failure was invisible for the
worst possible reason: re-opening such a board *does* show fresh content, so every
manual check confirmed the banner. A view that cannot know whether it is current must
say that, not guess.

## Keeping the two in step

`tasks-ready` and `tasks-board.awk` each implement the three rules. That is a
duplication, and it is the kind that drifts. It is called out at the top of
`tasks-board.awk`: **if you change one, change the other in the same commit.** A
shared implementation would mean a library, a version and an install story, for
about forty lines of awk. Stated rather than hidden.

## The workflow these came from

The tools assume an arrangement, and are more useful inside it. One **coordinator**
in the main checkout, which claims no tasks and writes no feature code; one or more
**workers**, each in its own git worktree on its own branch. The coordinator assigns,
reviews every PR against the task's `**Acceptance**` before merging, and keeps the
queue and the protocol document current. Workers build, push back when the
coordinator is wrong, and report findings into the queue rather than into chat.

Claiming is `(@actor)` on the checkbox line, committed alone and pushed before the
work starts. Finishing is removing the whole block — history lives in `git log`, not
in a checked box, and a dependency counts as unmet while its id is still in the file.

**The `Acceptance` field is where the value is.** Not "implement X" but the
condition that would falsify it: *a test drives the composed path rather than
calling the unit*, *a failed or skipped cycle does not ping*, *a named test fails if
this guarantee is removed*. Clauses written that way are what make an agent find the
real problem instead of the obvious one, and they are worth more effort than the
description.

## Gotchas

Each of these cost somebody real time. They are why the tools check what they check.

**"Nobody else owns this file" means the whole file.** A file with no live claim can
still be listed by a task nobody has picked up, and the collision arrives when
somebody does — the worst possible moment. This is rule 3, and it is the single most
useful thing here.

**A merge invalidates tasks nobody is holding.** Nobody is watching an unclaimed
task, so its description quietly stops being true: a prerequisite that has since
landed, a mechanism described as present that was just removed. Re-read the blocks a
merge touched, not only the one you merged.

**A `Blocked` line outlives its cause.** The thing that unblocks it happens
elsewhere — a credential arrives, a date passes — and nothing prompts anyone to go
back. Sweep them periodically; two of ours had been resolved for hours while the
file still advertised them as blocked.

**An acceptance that demands a test, over a `Files` list naming no test file, is
unsatisfiable.** Three separate agents each hit this, created a test file, and then
asked whether they had overstepped. If a clause says "a named test", name the test
file.

**A guarantee nothing invokes is worse than no guarantee.** It is written, tested,
visible, and stops nothing — and unlike an absent check it answers "is this handled?"
with yes. Ask what calls it. The mirror costs more: a guard that fires on everything
*except* its target, which is what a check placed before the filter meant to scope it
does.

**A surviving mutation is a question, not a pass.** It may survive because the code
is right, because no input reaches it, or because the component swallowed the
exception and "nothing changed" held for the wrong reason. All three look identical
from outside.

**Two paths that share their core computation cannot check that computation.**
Rebuild-versus-incremental comparisons are the usual case: if both sides run the same
fold, a bug in the fold agrees with itself. Persistence in the middle does not help.

**A check can be vacuously true**, which is worse than no check because it prints
something reassuring. Ask what would have to be true for it to fail; if you cannot
construct that case, it is decoration.

**One measurement, one set, quoted once.** A figure repeated in three places is three
figures the moment anything changes, and the copy that drifts is whichever one you
are not currently editing.

**Status words lie in both directions.** We saw one tool report `lost` for a write
that was safely stored and for one that had been destroyed, and `missing` for a task
that never existed and for one already finished. When a status word is your evidence,
go and read the state it claims to describe.

**Clear context on a trigger, not on a feeling.** "Wait for a clean boundary" is how
a session reaches 96% and gets compacted mid-turn with the summary chosen for it.
Before clearing, rewrite the status note rather than appending to it, prefer telling
the next reader *what to re-derive* over a number that will be stale, and re-read it
as someone who has not had the conversation.

## Licence


MIT. See [LICENSE](LICENSE).
