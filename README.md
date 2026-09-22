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
tasks-ready --ref origin/main    # the same, asked of the queue the fleet shares
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

**Use `--ref` when more than one machine writes the queue.** Both tools take it.
Without it they read *your working copy*, so a claim somebody else pushed is
invisible until you pull — and neither the page nor the listing can tell: each
correctly reports what it was given, while what it was given is a stale file. It
is the same mistake as the banner below, one level further out, and it is the more
dangerous one, because work gets assigned from what these two show.

```bash
tasks-ready --ref origin/main                    # ask the queue the fleet shares
tasks-board --serve --ref origin/main            # track what the fleet sees
tasks-board --serve --ref origin/main --file docs/TASKS.md
```

On `tasks-ready` it matters more than on the board, because it is the command run
*before assigning work*. Answering from a checkout that is a few commits behind
offers a task that is already finished, already claimed, or waiting on a PR — and
it does so silently. That is not hypothetical: a coordinator woke to a cleared
context, ran the recovery recipe, and was handed a task whose PR was green and
waiting for review, because the local `main` was three commits back. The script
was not wrong about anything; it read a directory and said what was in it.

`./TASKS.md` is the part that looks unambiguous and is not. Every worktree has
one, so the path names a different file depending on where the shell happens to
be standing. Hence the first line of every listing says what was read — either
`queue: origin/main:TASKS.md` or `queue: TASKS.md — your working copy, not the
remote`.

With `--ref`, `tasks-ready` fetches the remote first and then **fails** if the ref
or the file cannot be read. There is no falling back to the working copy: a
fallback would answer a different question in the most expensive direction, which
is the thing being fixed. If the fetch fails but the ref still resolves locally,
it says so on stderr *and* in that first line — `— FETCH FAILED, may be behind` —
and answers anyway, because offline is a reason to be told you might be behind,
not a reason to get nothing. A flag whose failure mode is "stop using the flag"
would not be a safety flag.

Because that refusal is the first thing a new setup meets, it names what it
tried rather than only what failed:

```
$ tasks-ready --ref origin/main
no such git ref: origin/main
  this repository has no remote called 'origin'
  remotes it does have: upstream
  to read this checkout on purpose instead, pass --working-copy
```

**`--working-copy` is the opt-out**, and it exists so a wrapper can default
`--ref` on. The last of the two wins, so a script may put `--ref origin/main`
ahead of the caller's arguments and the caller can still say no. One explicit
token, not an inferred absence — "drop `--ref`" is a rule somebody has to have
been told, and the people who most need the remote are the ones who have not.

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
   gone from the file or been checked off. Deleting a task's block, or ticking its
   box, is how the queue records that it is done, so a dependency still sitting
   there unticked is a dependency that is still open. No extra state, and nothing
   to keep in sync.
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
| `**Blocked by**` | comma-separated ids. Unmet while the id is still in the file and unticked |
| `**Blocked**` | prose reason, for what no task id can express — a person, a date, a decision |
| `**Details**`, `**Acceptance**`, `**Note**` | shown when a card is expanded; repeatable |
| `**Tags**` | shown on the card |
| `(@actor)` | on the checkbox line: this task is held |
| `- [x]` | this task is done. Listed at the bottom of the board, and out of everything else |

Only the checkbox line and `**ID**` are required. Everything else is optional, and
unknown fields are ignored rather than rejected, so the file stays yours.

**A field is its marker at the start of a line, never the marker anywhere in one.**
So you can write about the format inside the queue — `- **Note**: for example
**Blocked by**: other-task is how you write it` is a Note, not a dependency. There
is no escaping in this format, so putting a marker in prose is the only way to
mention a field, and it has to be safe.

Priorities are any `## P<n>`, from `P0` to `P9`, and `P0` sorts first.

**Two ways to finish a task, and they mean the same thing.** Delete the block, or
tick its box to `- [x]`. Deleting is the default and the reason there is no state
to keep in sync — history lives in `git log`. Ticking keeps the block visible at
the bottom of the board, which is worth it when the next person needs to see that
something was done rather than never planned. Either way a done task stops
counting: it holds none of its `**Files**`, and a `**Blocked by**` naming it is
satisfied. That has to hold both ways round, or ticking a box would be worse than
deleting the block — the task would go on blocking its dependents with nothing
saying why.

Try it:

```bash
tasks-ready --file examples/TASKS.md --all
tasks-board --file examples/TASKS.md --out /tmp/board.html --title "Example queue"
```

## The board

Counts by state, a stacked bar per priority, and one card per task. Clicking a card
expands it to the full `Details`, `Files`, `Acceptance` and `Notes`, with backticks
and bold rendered — the whole block a worker would read, without opening the file.

Sections run **In progress, Ready to start, contested, Blocked, Completed**. In
progress is first because the coordinator's first question is who is on what, and
completed is last because it is the only section nobody acts on. Clicking a section
heading folds that section's task list away, and clicking again brings it back —
which is how you get a long queue down to the part you are working on. It does not
touch the cards themselves: expanding a card is what shows its `Details` and
`Acceptance`, and one gesture cannot sensibly mean both. Which sections you folded
survives a reload, keyed by section rather than by position, so a task moving from
ready to held does not hand your folded state to a different section.

Cards are numbered down the page. That is only a way to say "look at 7" out loud —
the numbers shift as tasks change state, and `**ID**` is the handle that does not.
The counter covers the sections read from the task file; **closed rows are not
numbered**, because they come from the log and already carry an id and a sha that
do not move. A number there would have been an index into a historical record
that re-counted itself whenever an unrelated live task was finished.

Completed tasks are left out of the four counts and the priority bars. Those exist
to answer what to do next, and a finished task is not a candidate; a "done" tile
would only ever grow.

### Seeing what got finished, when finishing means deleting

Deleting a task's whole block is the recommended way to finish one, and it leaves
a queue of only live work with nothing to look back at. `--closed` adds a section
built from the git log instead of from the file:

```bash
tasks-board --closed                       # the 20 most recent, from `Close <id>: ...`
tasks-board --closed 50                    # more of them
tasks-board --closed-match "Done "         # a different commit convention
```

It reads commits that touch the task file whose subject starts with the prefix,
and shows the id, the text, the date and the sha, newest first. `--ref` applies
here too: with it the section is the history of that ref.

Closes that arrived on a branch and landed in a merge are included. That needs
`--full-history`, because `git log -- <path>` prunes one side of a merge by
default, silently omitting the branch-side closes *and* reporting a total that
agrees with the omission.

It only bites where the history actually contains merge commits. A repository
that rebases or squashes its pull requests has a linear `main` and was never
affected — which is most of them, and is worth knowing before you go looking for
missing rows. The flag is there because linearity is usually a convention rather
than a property: one merge made the other way and closes start disappearing, with
a count that agrees.

**It is off unless you ask for it, and that is the point.** `Close <id>:` is a
convention some repositories have and this tool does not own. A board that assumed
it would show an empty "Completed" section to everyone who spells it differently,
with nothing to say why — so the prefix is configurable, the default is
documented, and when nothing matches the section says which prefix it looked for
rather than just showing nothing.

**It never claims to be the whole list.** The heading reads `Closed recently (20
of 63)` when it is truncated and `(25)` when it is not, with a line under it
saying so. A section headed "Completed" that silently shows a third of them is a
view asserting something it has not checked, which is the mistake the freshness
banner already taught this tool once.

**It cannot take the board down.** Outside a git repository, on a ref that does
not resolve, or when `git log` refuses for any reason, the section stays and names
the reason; the queue above it is rendered from the task file and is unaffected.

The theme button beside the title cycles **System, Light, Dark**, and the choice
is remembered across sessions. System is the default and stays reachable, so one
click on a laptop that happened to be in dark mode does not pin you to it. The
board applies a stored choice before the first paint, because a page that reloads
itself whenever the queue moves would otherwise flash the other theme each time.

It is one HTML file with no external requests: no CDN, no fonts, no analytics.
It works at phone width. Small inline scripts keep the open cards, the folded
sections and the scroll position across a reload, each wrapped in `try`/`catch` so
the board still renders where storage throws.

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
