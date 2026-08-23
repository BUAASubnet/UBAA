# UBAA 2 Correctness Remediation Design

Status: approved for implementation on 2026-08-23.

This design supersedes `2026-08-19-readonly-route-diagnostics-design.md` where
that document assigns route resolution to the CLI or describes DNS-only campus
detection. The active authority remains `goal.md`, with live upstream evidence
first, then frozen `ubaa_old/`, then the pinned `examples/buaa-api/` reference.

## Scope And Chosen Approach

The remediation covers every finding from the post-goal audit: automatic route
selection, Core ownership, dual-session concurrency, captcha isolation, JSON
contracts, configuration persistence, user preflight, Classroom, SPOC, Judge,
source-parity records, and live verification. Schedule, exam, and grades retain
their current behavior unless the new facade or verification exposes a concrete
parity gap. Write operations, UI bindings, MCP, and server relay remain out of
scope.

Three implementation shapes were considered:

1. Patch each CLI command and feature in place. This is the smallest diff, but
   leaves route decisions in every host, keeps duplicated session ownership, and
   cannot satisfy the facade boundary.
2. Make the public Core client an aggregate facade over two private route
   clients. This centralizes policy, probing, sessions, feature state, and safe
   diagnostics while preserving the tested route-specific workers. This is the
   selected approach.
3. Rewrite the workspace around new crates and public APIs. This could produce a
   clean model, but would discard verified behavior and widen the regression
   surface without serving the current goal.

Schema version 1 is not a released compatibility surface. All CLI success,
failure, aggregate, captcha, and hidden diagnostic output will use the redacted
schema version 2 contract. Legacy v1 output code and schema alternatives will be
removed rather than maintained in parallel. Session and route-config on-disk
versions are separate contracts and retain their documented migrations.

## Aggregate Core Facade

The host-facing `UbaaClient` owns route configuration, a cached gateway probe,
Direct and WebVPN route clients, the dual-session coordinator, route-scoped
feature state, and opaque captcha mappings. Public user and read-only methods do
not accept `ConnectionMode`; they resolve the configured policy inside Core and
return the data with safe route diagnostics. A crate-private route client keeps
the existing request implementation. Explicit route selection remains available
only through a narrow diagnostic constructor used by live verification and
tests.

`apps/ubaa-cli` is limited to argument parsing, input acquisition, facade calls,
exit-code mapping, and human/JSON rendering. It does not load route policy,
invoke a network probe, resolve a feature route, inspect sessions, or import
upstream modules. `user show` resolves `route.default`; each of the six named
features resolves its own override before falling back to `route.default`.

Before any business request, the selected route must have an authenticated local
session. Missing authentication returns `authentication_required` with zero HTTP
requests. Fallback is permitted only for operations marked idempotent in the
route matrix and only for the documented network/timeout/502/503/504 failures.
Authentication, token creation, parse errors, 4xx responses, and explicit route
diagnostics never fall back.

## Gateway Reachability And Configuration

`auto` uses a `GatewayProbe` that tests TCP reachability of
`gw.buaa.edu.cn:80`. Name resolution and all address connection attempts share
one 500 ms deadline. The first established connection yields `Campus` and
selects Direct. Resolution failure, refusal, all-address failure, or deadline
expiry yields `OffCampus` and selects WebVPN. `Unknown` is retained only for an
injected probe's internal inability to execute; it uses the feature matrix's
documented safe default and remains visible in diagnostics.

The result is cached inside the facade for 60 seconds. Concurrent callers share
the same cache; explicit Direct or WebVPN diagnostics never probe. The probe
does not send HTTP, perform TLS, read credentials, use hard-coded addresses, or
record resolved addresses. This follows `examples/buaa-api/src/utils/net.rs`,
with the deliberate tightening that 500 ms is a total operation budget rather
than a budget per resolved address.

Route configuration remains strict and versioned. Loads reject symlinks and
non-regular files. Saves use an exclusively created, current-user-only temporary
file, flush before atomic replacement, and do not follow destination symlinks.
Temporary names are unique so concurrent writers cannot share a fixed
`config.toml.tmp` path.

## Atomic Dual Sessions And Logout

One `DualSessionCoordinator` loads the dual snapshot and revision under a single
file lock. Both route clients share that coordinator. A revision advances only
after this client successfully commits a compare-and-swap; it is never refreshed
from disk and adopted after a conflict. Consequently a stale client cannot
overwrite or delete a newer process's sessions.

A route login updates one slot while preserving the other slot from the
coordinator's owned snapshot, then commits the full dual snapshot with one CAS.
Authentication invalidation follows the same rule. Aggregate logout performs
both remote logout requests as best effort, clears both in-memory route states,
then clears both persistent slots with one CAS against the client's expected
revision. A conflict preserves the newer file and returns the existing safe,
retryable persistence error without snapshot data. Remote logout failure does
not prevent local cleanup, but persistence conflict is never hidden.

Route readiness is computed from the coordinator's current owned state, not a
construction-time list. Snapshot/revision loads, legacy migration, permissions,
and all writes remain within the existing session-file locking contract.

## Captcha Isolation

Raw upstream captcha identifiers, execution values, cookies, and image bytes
remain private to each route's authentication workflow. Each `prepare_login`
call creates a new opaque public challenge identifier mapped internally to one
route and that route's current challenge generation. Public identifiers for two
routes are distinct even when upstream identifiers match.

`login` validates the complete answer set before sending any credential POST.
Unknown, duplicate, expired, already-consumed, or wrong-generation identifiers
return `invalid_input`. An answer can be consumed only by its mapped route.
Missing answers leave those routes `captcha_required` while other routes continue
according to the documented partial-success contract. JSON exposes only route,
opaque challenge ID, and image availability; human mode may render the image in
memory but never persists it.

## Route-Scoped Feature State

Each private route client owns an `Arc<RouteFeatureState>` shared only with its
own read workers. Direct and WebVPN never share feature state. The state contains
the Classroom synchronization guard, SPOC authentication cache and mutex, and
Judge cache. Session replacement, authentication invalidation, relogin, and
logout clear the affected route's state; aggregate logout clears both routes.
There are no process-global business caches.

Classroom uses the exact frozen mobile WeChat user agent and request headers.
Session synchronization is serialized and cached once per successful route
session. A synchronization failure does not suppress the business query and is
retried next time. The query transport does not follow redirects; an SSO
redirect is classified as authentication expiry and clears the synchronized
flag. The response requires the frozen envelope fields `e`, `m`, `d`, and
`d.list`; only a structurally complete empty map is a successful empty result.

SPOC course metadata is optional enrichment. Assignment enumeration always uses
the frozen global encrypted pagination request with empty `kcid` and `yzwz`, once
per page rather than once per course. Token/role authentication is route-owned,
serialized, reused, and force-refreshed at most once after a recognized business
authentication error. CAS token extraction accepts the applicable response URL
or Location only when the frozen `/spocnew/cas` path matches; role parsing accepts
the frozen primitive and array shapes. Detail data is required, submission data
is optional, and score/time/status fall back to the list summary exactly as the
old implementation does. Raw HTML is converted internally to plain text and is
removed from public DTOs and JSON.

Judge list parsing accepts numeric `assignID` links except internal
`problemContent` and `judgeDetails` links, then deduplicates by assignment ID.
Detail parsing ports the frozen DOM semantics for nested tables, two- and
four-cell rows, per-problem status and score, partial completion, explicit and
derived totals, `HH:MM` time, entities, and script exclusion. Batch lookup groups
keys by course, fetches each course list once, limits concurrency by course, and
restores input order. The six-month cutoff clamps the day to the target month's
last day. Cache ownership and clearing follow the route-state rules above.

`examples/buaa-api` is explicitly non-equivalent for Classroom and Judge. Its
SPOC implementation is also non-equivalent for login, list endpoint, request
method, and pagination; only directly matching crypto, token, or DTO facts may
be cited. No missing field or error rule is borrowed by analogy.

## Errors And JSON Contract

All commands emit schema version 2. Single-route operations contain one
`resolvedRoute`; aggregate auth operations contain exactly
`resolvedRoutes: ["direct", "webvpn"]` and exactly two ordered route items.
The schema constrains array length, route order, item state, and the mutual
exclusion of single-route and aggregate metadata. Legacy `execution` fields and
raw challenge identifiers are never serialized.

Configuration, invalid captcha input, authentication absence, persistence
conflict, upstream authentication expiry, network failure, and parse drift keep
distinct stable error codes and exit categories. Error messages contain no
credentials, cookies, tokens, raw bodies, complete personal data, captcha image,
execution value, resolved IP address, or session snapshot.

## Source Parity And Verification

Before each production change, `docs/migration/source-parity.md` will contain a
separate operation row covering the mandated nine dimensions: bootstrap/service
URL, redirects/final URL, cookie/session scope, method and exact parameters,
headers/body encoding, crypto constants, DTO/parser fields, caching/concurrency,
and error/exit semantics. Non-equivalent or absent reference implementations are
recorded as such. Conflicts stop that operation until live evidence or the
applicable frozen local implementation resolves it in the decision log.

Every repair follows RED, focused GREEN, `just check-sensitive`, and `just check`
before its phase commit. Deterministic tests include:

- TCP success, failure, resolution failure, total timeout, cache expiry, and
  explicit-route no-probe behavior;
- zero-request user preflight and Core-owned feature/default policy selection;
- atomic snapshot/revision loading, stale-client conflicts, one-CAS dual logout,
  partial route login, and route-bound captcha generations;
- strict Classroom envelopes and synchronization lifecycle;
- global SPOC pagination, optional enrichment/submission, one-refresh auth,
  token/role variants, and absence of public HTML;
- complete Judge link/detail/date/batch/cache semantics;
- schema-v2 positive and negative examples and real CLI binary E2E output.

After deterministic gates pass, live verification runs auth and all six features
through explicit Direct, explicit WebVPN, and `auto`. The verifier validates safe
semantic invariants, not just exit status. SPOC evidence must prove that a valid
empty list came from the global assignment query. Judge evidence records only
non-sensitive stage counts and safe digests while investigating any route
difference; IDs, titles, bodies, and profile values are not persisted. Browser
tracing is used only if current upstream behavior contradicts both deterministic
evidence and frozen sources, and any resulting protocol decision is sanitized.

Passing deterministic checks does not imply live success. A route or feature
that cannot be verified is marked unverified with the exact safe failure stage;
the project is not declared complete until all hard gates in `goal.md` pass or a
documented current-upstream conflict makes a gate explicitly impossible.

## Delivery Order

Implementation proceeds in reviewable commits: contracts and RED tests; atomic
session/captcha repair; aggregate facade and TCP route selection; schema-v2 and
configuration hardening; route-owned state and Classroom; SPOC; Judge; source
parity and verifier improvements; deterministic gates; live matrix; final audit.
Frozen references, `.env.local`, session files, live bodies, and personal data
are excluded from every commit.
