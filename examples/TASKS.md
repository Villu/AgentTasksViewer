# Tasks

<!-- policy: One owner per file. Claim a task before editing its files by appending (@your-actor) to its checkbox line. -->
<!-- policy: Remove a task's whole block when it is done. History lives in git log, not in a checked box. -->

## P0

- [ ] Sessions survive a restart (@alex)
  - **ID**: session-persistence
  - **Details**: Sessions live in memory, so every deploy signs everyone out. The store needs to move behind an interface first, because two call sites reach into the dict directly and both assume it is synchronous.
  - **Files**: `src/auth/session.py`, `src/auth/middleware.py`, `tests/test_session.py`
  - **Acceptance**: A session survives a process restart, proven by restarting the process in the test rather than by reconstructing the store; the two direct readers go through the interface; a **named** test fails if expiry stops being honoured.
  - **Tags**: auth, reliability

## P1

- [ ] Rate limiting is per-process, so three processes allow triple
  - **ID**: shared-rate-limit
  - **Details**: The limiter counts in a local dict. With three workers the effective limit is three times what the config says, and the config is what the docs promise.
  - **Files**: `src/http/limiter.py`, `tests/test_limiter.py`
  - **Acceptance**: The budget is shared across processes and a test drives two of them concurrently; exceeding the limit refuses rather than delays; the refusal names the limit it hit.
  - **Blocked by**: session-persistence
  - **Note**: Blocked only for sequencing — it needs the same store this introduces, and building a second one is the thing to avoid.
  - **Tags**: http

- [ ] Nothing writes an audit row, so the audit log is empty
  - **ID**: audit-write-path
  - **Details**: `audit.record()` exists, is tested, and has no caller anywhere in `src/`. The table has been empty since it was created, and the dashboard reads it as "no incidents".
  - **Files**: `src/audit/writer.py`, `src/auth/middleware.py`, `tests/test_audit.py`
  - **Acceptance**: A request through the composed middleware writes an audit row, asserted by reading the row rather than by calling `record()` directly — an in-isolation test would pass today and does.
  - **Tags**: audit, security

## P2

- [ ] Publish the metrics endpoint
  - **ID**: metrics-endpoint
  - **Details**: Prometheus scrape target with the four counters already collected internally.
  - **Files**: `src/http/metrics.py`, `tests/test_metrics.py`
  - **Acceptance**: `/metrics` serves the four counters and a test asserts a counter moves when the event it counts happens.
  - **Blocked**: only the user can open the port on the load balancer
  - **Tags**: ops

- [ ] Session store needs an eviction policy
  - **ID**: session-eviction
  - **Details**: Unbounded growth once sessions persist. Needs a decision on TTL versus LRU before it is worth writing.
  - **Files**: `src/auth/session.py`, `docs/decisions/sessions.md`
  - **Acceptance**: The policy is written down with its argument, and the implementation matches what the document says; a test covers the boundary, not only the happy path.
  - **Note**: Shares `src/auth/session.py` with `session-persistence`, so only one of the two can be held at a time. `tasks-ready` will say so.
  - **Tags**: auth

- [x] Config was read from env vars in eleven places (@sam)
  - **ID**: config-loader
  - **Details**: One loader, validated once at startup, so a missing key fails the process instead of surfacing as `None` three hours later.
  - **Files**: `src/config.py`, `tests/test_config.py`
  - **Acceptance**: A missing required key refuses at startup and names the key; no module reads `os.environ` outside the loader, asserted by a test that greps the tree.
  - **Tags**: config

- [ ] Health check reports healthy while the queue is stalled
  - **ID**: healthcheck-liveness
  - **Details**: `/health` returns 200 if the process is up. It has never once gone red, including the afternoon the consumer was wedged and the queue grew to 40k.
  - **Files**: `src/http/health.py`, `tests/test_health.py`
  - **Blocked by**: config-loader
  - **Acceptance**: The check asks whether the queue is draining rather than whether the process exists; a stalled consumer turns it red and a test proves it by stalling one; a **skipped** cycle is distinct from a failed one, because "not started yet" and "stopped working" want different answers.
  - **Tags**: ops, reliability
