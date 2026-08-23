# Decision Log

## 2026-08-17: Execute the authentication contract from frozen evidence

The active design is `goal.md`. The old and example repositories match their required HEAD and origins and are clean. No protocol conflict has been identified during the initial inventory. Unknown upstream behavior will not be guessed; it will be recorded here with evidence before a decision.

## 2026-08-17: Preserve verified HTTP redirect compatibility

Fixed SSO and User Center entry points remain HTTPS and TLS verification remains enabled. Redirect resolution continues to accept both `http://` and `https://` only for the authentication host allow-list. This follows `ubaa_old/shared/src/commonMain/kotlin/cn/edu/ubaa/api/local/LocalConnectionAuth.kt::resolveRedirectUrl`, which explicitly recognizes both schemes, and the frozen WebVPN URL codec/tests that preserve HTTP protocol segments. Rejecting HTTP would be an unevidenced protocol change. Secure-cookie filtering still prevents Secure cookies from being sent over HTTP.

The scheme and host checks are both mandatory. Non-HTTP schemes such as `ftp` are rejected even when their host is otherwise allowed, and WebVPN conversion never encodes them.

## 2026-08-17: Keep the public facade concrete and runtime private

Hosts consume the non-generic `UbaaClient`; injected transport and session ports are boxed inside private `ClientRuntime`. Authentication and User Center workflows live in `auth` and `features/user`, while `facade` delegates stable DTO operations. `upstream` is crate-private, and the CLI uses `UbaaClient::open` rather than inspecting `FileSessionStore`. This keeps host APIs independent of upstream and storage implementation types without removing deterministic port injection.

## 2026-08-17: Add bounded buffering and locked session replacement

Authentication/User Center response bodies are capped at 8 MiB and persisted session JSON at 1 MiB. These are conservative UBAA 2 memory/file safety budgets, not upstream protocol facts. Session operations reject symlink/non-regular targets, open final files without following links, restore owner-only Unix permissions, use a sidecar OS lock and unique exclusive temporary files, synchronize writes, and preserve the existing `session.json` schema.

The sidecar lock also stores a synchronized monotonic revision. A runtime loads the snapshot and revision atomically, then compare-exchanges every save, invalidation, mode-mismatch clear, and logout clear. The revision is advanced and synchronized before replacing or deleting `session.json`; a crash may cause a conservative conflict but cannot authorize a stale writer. This prevents snapshot-equality ABA and ensures an old process cannot recreate a cleared session or delete a newer one. Windows inherits the selected directory ACL; explicit owner-only ACL enforcement remains a release audit item.

## 2026-08-17: Preserve JSON captcha non-interactivity

JSON login still returns `captcha_required` with exit 4 before credential submission and without image data. The local live verifier handles that result by starting a fresh human CLI in the same controlling terminal, feeding only the environment password through a private FIFO, polling `/dev/tty` only while that CLI is alive, suppressing human profile stdout, and resuming redacted JSON checks. It disables terminal echo for the complete captcha interaction, restores the original terminal state on every exit path, closes and removes the FIFO, and terminates/waits the child on HUP/INT/TERM with a bounded KILL fallback. This also handles the evidenced case where the fresh preparation no longer requires captcha. No cross-process challenge persistence was invented.

## 2026-08-17: Preserve remote-first logout while protecting local revisions

Both `LocalConnectionAuth.kt::logout` and the remote-backed `AuthApi.kt::logout` attempt remote logout before clearing local state. UBAA 2 preserves that evidenced order and always clears the current client's in-memory Cookie/login state. The persisted clear is revision-conditional so a stale process cannot delete a newer local session. Frozen code and current live evidence do not define whether a stale process's remote logout can invalidate a concurrently created upstream session, so future long-lived hosts must serialize logout for a shared account rather than inventing a remote concurrency guarantee.

## 2026-08-17: Require locked dependency resolution in deterministic gates

`just check`, macOS/Windows CI, the live verifier, and documented user commands use `--locked` for every Cargo command that resolves dependencies. `just check` first runs `cargo metadata --locked --no-deps --format-version 1`; a cross-platform binary test uses the Git index to scan tracked Markdown, `justfile`, workflow, and shell command sources so later edits cannot silently remove the lock contract. `cargo fmt` is exempt because it does not resolve the dependency graph.

## 2026-08-19: Historical Judge auto WebVPN route (superseded 2026-08-23)

The frozen `LocalJudgeApi` and its tests establish the Judge SSO service URL, route-local business pages, course selection, and isolated worker clients. At that time live verification showed Judge Direct unavailable while the explicit WebVPN route completed list/detail parsing with exit 0, so the route matrix temporarily forced `auto` to WebVPN for all network states. This was a deterministic feature exception, not a fallback replay. Later WebVPN/auto attempts also returned upstream timeouts or changed responses; those observations remain historical rerun conditions. Fresh campus evidence and the superseding 2026-08-23 decision below removed the stale override.

## 2026-08-19: Require AAS service activation before schedule reads

The frozen local schedule implementation probes `byxt.buaa.edu.cn/.../currentUser.do` and classifies an SSO page as authentication-required. The pinned `examples/buaa-api/src/api/aas/core.rs` proves that the same AAS protocol has a service-specific CAS bootstrap URL ending in `.../homeapp/index.do?contextPath=/jwapp` and requires the final URL to start with that AAS landing page. Live `.env.local` verification initially returned an SSO-shaped response for the probe, so terms/weeks could not begin even though generic SSO and User Center authentication succeeded. Core now performs the proven AAS activation only after that probe condition, verifies the route-local final URL, then probes again. Direct and WebVPN schedule terms/weeks/current/today subsequently passed; no generic SSO bypass or cross-route cookie replay was added.

## 2026-08-19: Preserve form content type for schedule/grade POSTs

The old local implementations use Ktor `FormDataContent` for the weekly schedule and grade query forms. The Rust helper serialized the same fields but omitted `Content-Type: application/x-www-form-urlencoded`. A TDD request-contract test observed the missing header, and the minimal fix was applied in the shared form helper. The first real schedule-current response had only safe structural error keys (`code`, `logId`, `msg`), and after the header fix the full schedule auto/Direct/WebVPN verifier passed. The pinned AAS example uses a POST query payload rather than this local form helper; it is not used to override the local endpoint's observed form contract.

## 2026-08-19: Do not merge non-equivalent example protocols

The pinned `buaa-api` App module exposes a mini-program exam page and no local `buaascore` grades operation; its Class module exposes iClass course/check-in endpoints and no free-classroom query; its tree has no Judge module. The frozen local implementation has separate grades, free-classroom, and Judge protocols. These are documented as non-equivalent in `docs/migration/source-parity.md`; their URLs, headers, DTOs, encryption, or errors must not be borrowed by analogy. This is a deliberate evidence boundary, not an implementation omission.

## 2026-08-19: Choose a stable Judge detail sample in the live verifier

The verifier contract requires one real Judge detail when the list is non-empty; it does not require the last list item. Three required/diagnostic auto attempts selected `.data[-1]` and returned `Judge assignment was not found` at the separate detail CLI process, while an evidence probe selecting `.data[0]` completed list plus detail with exit 0. The list and detail are separate processes and the upstream list can change between them, so the verifier now selects the first returned item and has a shell regression test. This changes only verifier sampling, not Core Judge lookup or its old-reference semantics; stale-ID results remain nonzero rather than being hidden.

## 2026-08-23: Revalidate Judge Direct in the campus network

The previous Judge `auto -> WebVPN` override was introduced after an explicit Direct attempt returned `upstream_unavailable`. With the test account on the campus network, later live checks returned exit 0 on Direct (reported 65 assignments) and WebVPN (reported 17 assignments), while the other five features also returned exit 0 on both explicit routes. The old implementation supports route-local Judge requests and does not require WebVPN, so the stale feature override was removed. This decision did not explain the 65/17 difference and did not prove the old detail parser semantics; the remediation decision below therefore reclassifies these values as historical observations rather than completed parity evidence.

## 2026-08-23: Use a bounded TCP gateway probe

The accepted product signal is a TCP connection attempt to `gw.buaa.edu.cn:80`, following the concrete target, port and 500ms duration in pinned `examples/buaa-api/src/utils/net.rs`. The entire operation, including hostname resolution and all resolved-address attempts, has one 500ms budget. Any successful connection is `Campus`; ordinary resolution failure, no addresses, refusal, unreachable network or deadline exhaustion is `OffCampus`. Only an internal probe implementation failure or deliberately injected diagnostic failure is `Unknown`. Results are process-local and cached for 60 seconds. The probe sends no HTTP/TLS request, reads no credential and hard-codes no IP address/range.

This supersedes the earlier resolver-only authority. The total-budget and `Unknown` boundary are explicit UBAA 2 product constraints because the example applies 500ms per address and returns only Boolean; they are not presented as frozen upstream behavior.

## 2026-08-23: Move ordinary route selection into the aggregate Core facade

The earlier host-owned diagnostic design is superseded. The ordinary `UbaaClient` facade owns strict config loading, the cached gateway probe, route resolution/readiness checks, two private route runtimes, the shared dual-session coordinator and route-owned feature state. CLI and future hosts only parse input, call facade methods and render the facade's safe diagnostics. Explicit `ConnectionMode` remains available only through a clearly separate diagnostic/test path.

One coordinator owns the loaded dual snapshot and revision. It never adopts a revision written by another process in order to retry a mutation. Aggregate logout performs both best-effort remote calls, clears this process, and attempts one dual compare-exchange; a conflict preserves the complete newer persisted snapshot.

## 2026-08-23: Preserve route CAS semantics inside the dual coordinator

The two route runtimes share one file revision but retain independent route-local logical revisions. A route adapter rejects an outdated logical revision before building a candidate, so two same-route writers that loaded the same state cannot both succeed. A valid sibling-route mutation may advance the file revision without making the other route's logical revision stale; the coordinator then merges that route's replacement into its client-owned full snapshot and performs one file CAS. Aggregate logout advances both route-local revisions and the file revision through one full-snapshot clear, including when this client originally loaded no slots.

An external file CAS conflict is terminal for that coordinator instance. It clears the coordinator snapshot and both route runtimes/auth workflows, stops any not-yet-started sibling request, preserves the complete external snapshot, and returns the stable retryable conflict. Later calls on that instance keep returning the conflict without network I/O; recovery requires opening a new facade. This prevents a stale process from silently adopting the external revision or continuing with sibling Cookies after one route has lost ownership.

A file CAS error is treated as equally terminal because the crash-safe store intentionally advances and synchronizes its revision before replacing or deleting `session.json`. An error may therefore mean that revision ownership was lost even when the body operation did not complete. The coordinator clears its client-owned snapshot and the facade clears all in-memory Cookies/workflows before returning; it never assumes that an `Err` happened before the revision write. A Unix permission fault-injection test covers this post-revision/body-write failure boundary.

Remote logout remains an unconditional best-effort request on each owned route, matching both frozen logout implementations and the aggregate contract. An absent local slot suppresses Cookie attachment but does not suppress the Direct or WebVPN logout attempt. Deterministic CLI tests route these requests through a local rejecting proxy, so the repository gate never depends on the real upstream.

Receiving SSO prepare-page Cookies does not establish a local authenticated session. Only an `authenticated_at` value restored from a persisted route slot or produced after successful User Center status validation authorizes user/business preflight. This keeps `prepare_login` state usable for credential submission while ensuring status, profile and all read-only features make zero requests between prepare and completed login. Any persistence-port error while committing that validated state clears the runtime Cookie jar, timestamps and pending workflow before the error escapes, including for injected non-file stores.

## 2026-08-23: Make CLI schema v2 the only output contract

All ordinary commands, hidden diagnostics, argument failures, authentication results and read-only results emit only schema version 2. The unshipped schema-v1 CLI branch is removed rather than maintained as compatibility surface. This does not change `config.toml` on-disk format version `1` or the versioned `session.json` migration reader; those are independent disk formats.

## 2026-08-23: Reopen SPOC and Judge live conclusions

Frozen `LocalSpocApi.kt` treats course metadata as optional and always calls the encrypted global `queryListByPage` operation with `kcid=""`. Pinned `buaa-api` instead calls per-course `queryXsZyList`, so its list/auth flow is non-equivalent; only matching AES constants, token facts and the detail endpoint may supplement the old source. The prior three-route empty result is unverified until the corrected global empty-`kcid` request is observed. It cannot be called a valid empty list merely because the command exited 0.

Pinned `buaa-api` has no Judge module. Frozen `LocalJudgeApi.kt` filters `problemContent`/`judgeDetails` assignment links and parses nested problem tables, scores, `PARTIAL` state and fallback counts. The current historical exit-0 detail checks did not assert all those semantics. Direct reported 65 items while WebVPN reported 17; the difference is unresolved and must be investigated after parser/cache parity without persisting IDs, titles or raw bodies. Neither route is permanently preferred from this observation.
