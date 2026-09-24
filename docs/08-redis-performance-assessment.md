# Does UniStash Need Redis? — Performance Assessment

**Verdict: No — not now, and probably not for a long time.**
This document records the reasoning so the question doesn't have to be
relitigated, plus the concrete triggers that should reopen it.

---

## 1. TL;DR

| Question                               | Answer                                                                   |
| -------------------------------------- | ------------------------------------------------------------------------ |
| Would Redis make the API faster today? | Not meaningfully.                                                        |
| Is any current endpoint slow?          | No evidence of it.                                                       |
| What does the stack already use?       | PostgreSQL + in-process rate limiting + Pusher (external realtime/push). |
| When should Redis be reconsidered?     | See §5 triggers.                                                         |

The API's read paths are already indexed, cursor-paginated, single-round-trip
PostgreSQL queries. Redis cannot make an indexed `COUNT(*)` or a keyset-paginated
`SELECT ... ORDER BY created_at DESC LIMIT 20` on a campus-scale dataset
(thousands to low tens of thousands of rows) perceptibly faster — we'd be adding
a network hop to save single-digit milliseconds.

## 2. Where the response time actually goes

Measured against the architecture (see `docs/01-cm-trd.md`):

1. **Mobile network round-trip** — 20–200 ms of cellular latency dominates
   every request. Server-side work is noise by comparison.
2. **PostgreSQL queries** — all hot paths are:
   - listings browse/search: keyset-paginated, `search_vector` GIN index,
     images batched in one extra query (no N+1);
   - profile stats: three indexed `COUNT(*)` subqueries in one round-trip;
   - sales/saved-items: indexed on `(user_id, created_at DESC)`.
3. **External providers** — Pusher Channels (realtime) and Beams (push) do the
   fan-out work that people commonly deploy Redis (pub/sub) for — already
   outsourced and off-box.

The common Redis use cases simply don't apply at this stage:

| Redis use case           | UniStash status                                                                                       |
| ------------------------ | ----------------------------------------------------------------------------------------------------- |
| Caching hot reads        | Reads are indexed single-table queries; cache invalidation cost > query cost.                         |
| Pub/sub for realtime     | Handled by Pusher Channels.                                                                           |
| Session store            | Stateless JWTs; refresh tokens live in Postgres (they must survive restarts and be revocable anyway). |
| Rate limiting            | In-process sliding window (`PerEmailLimiter`) is sufficient for a single API instance.                |
| Queues / background jobs | `core::jobs` in-process timers suffice for reservation cleanup and token sweeps.                      |
| Distributed locks        | Single API instance; `SELECT ... FOR UPDATE` already covers state-machine races.                      |

## 3. The cost side of "add Redis"

Adding Redis to a solo-maintained, campus-scale product buys speed it doesn't
need and costs:

- **One more stateful service** to deploy, monitor, back up, and restart.
- **A second source of truth** for anything cached (stale-read bugs).
- **Serialization work** in application code that must be written, tested, and
  kept correct.
- **Failure modes**: cache stampedes on cold start, connection-pool exhaustion
  under mobile's bursty reconnect storms — new failure classes that Postgres
  alone doesn't have.
- **Security surface**: one more credential, one more patch cadence.

Rule of thumb: don't add infrastructure until a measurement demands it.

## 4. What to do instead (performance work with actual payoff)

1. **Verify with data, not vibes** — add `tracing` timing spans per repo call
   (already partially wired via `logging`) and watch p95 query times.
2. **Indexes** — the schema is young; every hot query currently has a supporting
   index. Re-check after data grows (`pg_stat_user_indexes` for unused ones).
3. **`COUNT(*)` on stats** — if `/auth/me/stats` ever shows up as slow (it
   won't at this scale), replace the saved-count subquery with an
   `inherited_stats` counter column maintained by save/unsave, or accept a
   `COUNT` estimate.
4. **HTTP caching** — listings browse responses are ideal `Cache-Control`
   candidates for a CDN (Cloudflare is already in the path for R2 assets).
5. **Payload size** — the biggest mobile-perceived win is often response
   trimming (e.g. saved-items returning hydrated summaries instead of N detail
   fetches — already on the roadmap).

## 5. Reconsider Redis when any of these triggers fire

| Trigger                                                                      | Redis's role                                               |
| ---------------------------------------------------------------------------- | ---------------------------------------------------------- |
| More than one API instance behind a load balancer                            | Shared rate limiting, session/token denylist cache.        |
| Realtime moves off Pusher (cost/self-host decision)                          | Pub/sub backbone replacing Channels.                       |
| Feed endpoint p95 > ~50 ms sustained at real load, measured                  | Read-through cache for the browse feed.                    |
| Background work outgrows in-process jobs (emails at scale, fan-out, digests) | Job queue (e.g. alongside Sidekiq-equivalent or `apalis`). |
| Multi-region deployment                                                      | Edge caches / replicated state coordination.               |

Any one of these justifies a scoped, single-purpose Redis (not "Redis for
everything"). Until then: Postgres is the database, Pusher is the message bus,
and the fastest request is the one whose latency is dominated by the client's
own network — which is exactly where UniStash is today.

---

_Assessment date: 2026-09-24 · Codebase state: 12 migrations, features =
auth, listings, chats, sales, saved-items, notifications, images, categories,
schools, admin._
