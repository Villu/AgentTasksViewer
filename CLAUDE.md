# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Three files. Two CLI views of a markdown task queue, plus the awk that renders one
of them. No build, no package manager, no dependencies beyond `bash` and `awk`.

| file | role |
|---|---|
| `tasks-ready` | bash + a single inline awk program. Prints what can start now, and with `--all` why everything else cannot. |
| `tasks-board` | bash driver only: argument parsing, `--ref` resolution, change detection, the watch loop, the http server. Renders nothing itself. |
| `tasks-board.awk` | the whole HTML renderer — CSS, markup and every inline script are `print` statements in its `END` block (bar the theme preamble, printed into `<head>`). Found via `dirname $0` from `tasks-board`. |

`examples/TASKS.md` is the fixture: six live tasks covering all four live states,
plus one `- [x]` task that a live task depends on.

## Commands

```bash
./tasks-ready --file examples/TASKS.md --all
```

```bash
./tasks-board --file examples/TASKS.md --out /tmp/board.html --title "Example queue"
```

```bash
./tasks-board --serve --file examples/TASKS.md --out /tmp/board.html
```

There is no test suite, no linter and no CI. Verification is running both tools
against `examples/TASKS.md` and checking that they agree: `tasks-ready`'s READY
count must equal the board's `ready` tile, and its NOT READY reasons must match
the card subtitles. The example file covers all five states, including one `- [x]`
task that another task names in `**Blocked by**` — that pair is what proves a done
dependency counts as met.

It does not cover `P4+`, unknown fields, or a done task whose `**Files**` a live
task also claims. Write a throwaway fixture in the scratchpad for those; the last
one is the regression that matters, because a done task must hold nothing.

`--serve` needs a working `python3`/`py`/`python`. Pick a port nothing else is on:
on Windows a second `http.server` binds the same port without error and the older
listener keeps answering, so a stale server from another session looks exactly
like your board failing to render.

## The one invariant

The three-rule readiness check is implemented **twice**: in the `END` block of the
inline awk inside `tasks-ready`, and in the `END` block of `tasks-board.awk`.
Both build the same `held[path] -> id` map from claimed tasks' `**Files**`, and
both resolve `**Blocked by**` by asking whether the id is still `in byid` and not
done.

**If you change one, change the other in the same commit.** This is stated at the
top of `tasks-board.awk` and in the README, and it is the only thing in the repo
that cannot be recovered by regenerating something.

The `- [x]` done state is part of that shared contract, not presentation. A done
task **holds none of its `**Files**`** and **satisfies a `**Blocked by**` naming
it**, in both implementations. Break either half and ticking a box becomes worse
than deleting the block: the task keeps blocking its dependents and keeps owning
its files, with nothing on the board saying why.

Two priority loops used to disagree — `tasks-board.awk` iterated `P0..P3` while
`tasks-ready` went to `P9`, so a `P4` task was counted in the stat tiles and then
dropped from the cards. Both now go to `P9`. A fixture with `P4` and `P7` is the
cheapest way to catch a reintroduction.

## `--ref` on both tools

Both read a git ref instead of the working copy, and in both `--file` becomes
repo-relative under it. They differ where their jobs differ, and the difference is
deliberate — do not "unify" it:

- **`tasks-board` swallows fetch failures** and renders the last ref it can reach.
  A board that stops updating because the network blinked is worse than one
  showing a slightly old queue, and the page names its ref either way.
- **`tasks-ready` refuses.** An unresolvable ref or a missing file at that ref is
  an error with a non-zero exit, and it never falls back to the working copy — a
  one-shot answer used to assign work must not quietly answer a different
  question. A fetch that fails while the ref still resolves is the one middle
  case: stderr warning, `— FETCH FAILED, may be behind` appended to the source
  line, exit 0.

Resolve the ref **before** complaining about a failed fetch. A typo'd ref also
fails to fetch, and warning about staleness first puts a true statement about the
wrong thing above the real error.

`--working-copy` is the opt-out, and **the last of `--ref`/`--working-copy` wins**
— not an error on conflict. That is what lets a wrapper put `--ref origin/main`
ahead of the caller's arguments while the caller can still override it. Keep it
that way; trader's `ops/ready.sh` is built on it.

`tasks-ready`'s ref refusal names the remote and branch it tried, says whether
that remote is configured at all, lists the ones that are, and points at
`--working-copy`. It is the first thing a fresh clone meets, and "no such git ref"
alone cannot be told apart from a broken queue by someone who has just arrived.

Every `tasks-ready` run prints `queue: <source>` as its first line. Anything
parsing that output sees it, so treat it as part of the interface.

## Telling the consumer

`~/projects/trader` vendors `tasks-board` and `tasks-board.awk` (and, once its
`revendor-ready-sh` task lands, `tasks-ready`). Its coordinator asked for one
standing notification, and it is the right one to honour: **if `tasks-board.awk`
and `tasks-ready` ever stop agreeing on the three rules, say so immediately
rather than at a release.** Everything else batches until they next ask.

Two things they rely on that are easy to break without noticing: the `queue:`
first line, and renaming an extension-less file — `tasks-ready` and `tasks-board`
have no extension, so `.gitattributes` pins them by name, and a rename silently
un-pins the copy in any repo that vendors them. Treat a rename as breaking.

## How the parsers work

Both are line-oriented awk over the markdown, with no lookahead:

- `/^## P[0-9]/` sets the current priority; `/^- \[[ x]\] /` increments `n` and
  opens a new task. Every `- **Field**:` rule after that writes into index `n`.
  There is no block terminator — a field line belongs to whatever checkbox came
  last, so a stray field before the first task writes to index 0.
- `**ID**` is taken as `$NF` (last whitespace-separated field), so an id cannot
  contain a space. It populates `byid[id] = n`.
- `**Files**` paths are extracted by repeatedly matching `` /`[^`]+`/ `` — only
  backticked paths count for rule 3. A path written without backticks is invisible
  to ownership checking.
- Rule 2 is `(t in byid) && !fin[byid[t]]`: a dependency is unmet while its block
  is still in the file *and* still unticked. Deleting the block and ticking it are
  the two ways to record that it finished.
- `fin[n]` is `substr(line, 4, 1) == "x"` — the character inside the brackets of
  `- [x] `. It is read off the already-`strip()`ped line, so a CRLF file is fine.
- **Every field pattern is anchored**: `/^[ \t]*-?[ \t]*\*\*Field\*\*:/`, and the
  `sub()` that strips the prefix uses the same anchor rather than a greedy `^.*`.
  The format has no escaping, so the only way to write *about* a field is to put
  its marker in a line — and documenting the format inside the queue is a normal
  thing to do. Unanchored, `- **Note**: for example **Blocked by**: other-task`
  was read as a dependency, and the greedy strip took the value after the *last*
  marker, so a Note silently replaced a real `**Blocked by**` and the task was
  offered as ready with its blocker open. Do not "simplify" the anchors away, and
  do not fix a recurrence by adding a shadowing rule for whichever field was
  quoted — that fixes the instance, the anchor fixes the class.
- The same swallow reached two more fields, and the `**ID**` one is worth stating
  precisely because the obvious version of it is **not** what happens. A quoted
  `**ID**:` renames the task in listings, but `byid` *accumulates* — the real id
  was already inserted by the genuine line — so a dependency naming it still
  resolves and is still correctly withheld. The damage is a **key collision**:
  when the swallowed text matches *another* task's id, `byid[that id]` is
  repointed at the wrong block, and everything read through it answers from the
  wrong task. With the hijacking block `- [x]`, `fin[byid[dep]]` is then true and
  a dependency on a real, open task counts as met. Demonstrated by trader's
  worker; verified here at `0330c32`, where the dependent is offered while its
  blocker is open.
- A `**Blocked**` prose reason that mentions the other marker — `- **Blocked**:
  waiting on a rewrite of the **Blocked by**: convention` — was consumed by the
  `Blocked by` rule, so `blk` was never set and the prose became a dangling
  dependency that resolved to nothing. The task was offered as ready with a
  human-written block silently discarded, and it needs no `**Note**` at all: just
  writing about the convention in a reason. Probably the likeliest way in.
- Rule order is no longer load-bearing. `/\*\*Blocked by\*\*:/` used to have to
  precede `/\*\*Blocked\*\*:/`, because unanchored the latter also matched a
  "Blocked by" line; anchored, `**Blocked**:` cannot match `**Blocked by**:` at
  all. The order is kept because it reads well, not because anything rests on it.
  The board's apparent immunity to the Note case was the same accident — Details,
  Acceptance and Note are declared above `Blocked by` and took the line first,
  while `Tags` is declared below and did not.

`tasks-ready` reduces to ready / not-ready-with-a-reason, and leaves done tasks
out of both lists with a `N tasks, M completed` trailer. `tasks-board.awk`
produces five named states — `ready`, `held`, `blocked`, `contested`, `done` —
which are also the CSS class names and the `--<state>` colour variables, so a new
state needs a colour in all three theme blocks or its label renders uncoloured.

Section order on the board is `held ready contested blocked done`, set by two
parallel `split()` calls — the state keys and the human labels — which must stay
in the same order. `cnt["done"]` is assigned after the state loop rather than
accumulated in it, because done tasks `continue` before the counting line so they
stay out of the stat tiles and the priority bars.

## `--closed` reads a second source

Every other section on the board comes from the task file. `--closed` comes from
the **git log** — commits touching the task file whose subject starts with
`--closed-match` (default `Close `). It is the only place the tool reads a repo
convention, so three rules hold it in check, and all three are load-bearing:

1. **Opt-in.** No `--closed`, no section, no git call. The convention belongs to
   the consuming repository; defaulting it on would show an empty section to
   everyone who spells finishing differently.
2. **It states its own truncation.** `(20 of 63)` in the heading and a note under
   the rows. A "Completed" heading over a truncated list asserts something it has
   not checked — the same family as the liveness banner this tool already fixed.
3. **It fails soft.** `collect_closed` never exits non-zero: no repo, an
   unresolvable rev, or a `git log` that refuses sets `CLOSED_WHY`, and the
   section renders that reason instead of rows. The queue above comes from the
   file and must still render.

The prefix is matched with `git log -F --grep` (literal, since it is user text)
and then re-checked against the *subject* in awk, because `--grep` matches
anywhere in the message. Rows are split by hand on the first two tabs rather than
with `split()`, since a subject may contain one.

**`--full-history` is load-bearing — do not drop it as noise.** `git log -- <path>`
simplifies history by default: at a merge it follows one parent and prunes the
other, so a close that arrived on a branch and landed in a merge disappears from
the output. The total is computed from the same list, so it agrees with the
omission — a wrong answer that looks self-consistent. Shipped without it for one
commit; caught by a fixture with a merge, not by reading.

Its reach is narrower than it first looks, and the distinction is worth keeping
straight: it fires only where the history *contains merge commits*. A repo that
rebases or squashes its PRs has a linear `main` and is immune, however much
merging it does — trader is one, which I got wrong when I first described this.
The flag earns its place anyway, because that linearity is a convention somebody
wrote down rather than a property of the repository: it protects against the rule
changing, not against today.

Ordering is `git log`'s default, which is reverse chronological by **commit**
date, and the row shows `%cs`, which is also the commit date — sort key and
displayed value are the same field on purpose. Do not add a client-side sort:
it would be a second implementation of an ordering the log already has, and the
two would drift the moment one of them learned about author dates.

Closed rows are `div.card.closed`, not `<details>` — there is nothing to expand,
and a card that opens to nothing is worse than a row. The storage script only
looks at `details.card`, so they are skipped by it automatically.

**Closed rows carry no row number, and `num` must not advance over them.** It
counts rows read from the task file. Numbering both sources made a closed row's
number a function of how many live tasks sat above it, so finishing an unrelated
task renumbered the whole history — observed as a list that started at 28 one
hour and 27 the next. These rows already have an id and a short sha, both stable;
adding a number that moves invites the one use it cannot support, which is
writing it down and referring back. Restoring the number "for consistency" is the
tempting wrong fix.

## The page's three scripts

They are separate on purpose, and each one's failure has to be survivable by the
others:

1. **Section folding.** A heading toggles `.shut` on its `<section>`, which hides
   that section's `.cards` wrapper. It does **not** open or close the cards: a
   card's `<details>` is what reveals `Details` and `Acceptance`, and one gesture
   cannot mean both "collapse this section" and "expand everything in it". Kept
   out of the storage script so a `sessionStorage` throw cannot leave a heading
   that looks clickable and does nothing.
2. **Storage.** Restores open cards (`board-open`) and folded sections
   (`board-shut`), then saves on change. Folded sections are keyed by state name
   from `data-sec`, not by index — sections appear and disappear as tasks change
   state, so an index would restore the wrong one. It installs `sec.saveShut` for
   script 1 to call, which is why script 1 null-checks it.
3. **Freshness.** See below.

The theme control is a fourth, smaller piece, split across two places: a tiny
script **in `<head>`** that applies a stored `data-theme` before the first paint,
and the button's cycle handler at the end. Keep the head script first — the board
reloads itself whenever the queue changes, and applying the theme after body
render flashes the other theme on every one of those reloads. It cycles
system → light → dark, and `system` is represented by *removing* the attribute so
the `prefers-color-scheme` block takes over. It uses `localStorage` where
everything else uses `sessionStorage`, deliberately: a theme should outlive the
tab, a scroll position should not.

## Constraints on the awk

Target is **POSIX awk** (mawk, BusyBox awk), not gawk, even though gawk is what is
usually installed. No `gensub`, no capture groups in `gsub`, no `length(array)`,
no `asort`. The hand-rolled `md()` in `tasks-board.awk` — which toggles `**`
into `<strong>` and backticks into `<code>` by walking the string — exists for
exactly this reason; do not "simplify" it into a `gensub`.

`esc()` runs before `md()`, always. The generated page has no external requests:
no CDN, no fonts, no analytics. Keep it that way.

## The freshness contract

This is the part that is easy to break invisibly.

Each render writes one epoch to **both** the page (`-v epoch=`) and a sidecar
`$OUT.stamp`. The page fetches the stamp on an interval and compares: equal means
current, **newer means reload**. If the stamp were ever written a second later
than the number baked into the page, every page would read itself as superseded
and reload forever. One `ts` variable in `render()` feeds both — keep it that way.

That `ts` is declared `local` deliberately. The watch loop holds the *source's*
version in `now`/`last`; a global assignment in `render()` would put an epoch into
`last` and make every subsequent interval compare a version against an epoch, and
re-render forever. The bug only shows after the first real change, so a quiet
watch looks correct.

`refresh=0` means a one-shot render: the page says `snapshot` and counts up, and
makes no liveness claim. A `file://` page cannot fetch its sibling stamp, so it
reports `NOT refreshing` and names the reason. **A view that cannot verify it is
current must say so — never assert liveness.** Both of those behaviours replaced
bugs (see `git log`), so do not reintroduce an unconditional banner.

## `--ref` mode

`--ref origin/main` reads the file from a git ref instead of the working copy.
It changes three things at once: `--file` becomes **repo-relative**, change
detection becomes the blob sha instead of an mtime, and a remote ref is fetched
before every check. Fetch failures are swallowed on purpose. The page's `source`
string changes to name the ref, so a board of someone else's branch cannot be
mistaken for your checkout.

`python_cmd()` tries `python3`, `py`, `python` and **runs** each candidate rather
than using `command -v`, because on Windows `command -v python` finds the
Microsoft Store stub, which exits 49 without being python.

## Repo conventions

- The generated HTML and `*.html.stamp` are gitignored and must never be
  committed — a committed snapshot is the second source of truth this repo exists
  to avoid.
- `.gitattributes` pins `tasks-ready`, `tasks-board` and `*.awk` to LF. Do not let
  an editor write CRLF into them; both awk programs also `strip()` `\r` from input
  so CRLF *task files* are fine.
- Commit subjects here are a full sentence naming the failure, not a conventional-commit
  prefix — "The board rendered your working copy while the queue lived on the remote".
  Bodies explain how it was found and why the fix is shaped the way it is. Match that.
- The README is the user-facing document and carries the design argument. If a
  flag, field or state changes, the README's flag list, field table and
  "three rules" section change with it.
