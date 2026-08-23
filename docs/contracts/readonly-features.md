# Read-Only Feature Contract

The CLI exposes only the aggregate Core facade methods below. Host code never imports `upstream`, builds a campus URL, probes the gateway or selects a route. Every result contains stable DTO data and safe route diagnostics produced by Core; raw HTML, encrypted parameters, token values, Cookies, and response bodies remain internal.

| Feature | CLI | Facade | Frozen request evidence |
|---|---|---|---|
| Schedule | `schedule terms`, `weeks`, `current`, `today` | `schedule_terms`, `schedule_weeks`, `schedule_week`, `schedule_today` | `schoolCalendars.do`, `getTermWeeks.do`, `getMyScheduleDetail.do`, `teachingSchedule/detail.do`; `Schedule.kt` |
| Exam | `exam list --term` | `exam_arrangement` | `student/exams.do`; `Exam.kt` |
| Grades | `grades list --term` | `grades` | `buaascore/wap/default/index`, activation GET then `xq`/`year` form POST; `Grade.kt` |
| Classroom | `classroom search --campus --date` | `classroom_search` | SSO sync URL then `buaafreeclass/.../search1?xqid=&floorid=&date=`; `Classroom.kt` |
| SPOC | `spoc assignments`, `spoc assignment show --id` | `spoc_assignments`, `spoc_assignment` | current-term; optional course metadata; global encrypted `queryListByPage` with `kcid=""`; detail and optional submission endpoints; `Spoc.kt` |
| Judge | `judge assignments`, assignment `show`/`details` | `judge_assignments`, `judge_assignment`, `judge_assignment_details` | SSO service, course/assignment HTML links and detail pages; `Judge.kt` |

Schedule term values and week serials are selected from the upstream response. Grades reject terms that do not match `yyyy-yyyy-semester`. Classroom dates must use `yyyy-mm-dd`; `UBAA_VERIFY_CAMPUS_ID` and `UBAA_VERIFY_DATE` are non-secret live-verifier overrides. Empty lists and empty classroom maps are valid only after the authoritative operation was actually requested and its required wrapper parsed; an unsupported undergraduate portal or missing account capability is a real, nonzero live failure.

The target ports the frozen read paths, including the undergraduate AAS-specific CAS activation required by `examples/buaa-api/src/api/aas/core.rs`, the local schedule form encoding, SPOC encrypted global pagination/token/role setup, one forced token refresh after a business authentication failure, Asia/Shanghai time normalization, optional submission fallback and HTML-to-plain-text normalization, plus Judge course selection, complete detail/problem parsing, six-month cutoff and route/client-scoped caches cleared with the session. SPOC HTML is never a public DTO field. Deterministic fixtures and Mock transports establish request shape; only a post-remediation live matrix can establish current upstream availability. The source-by-source audit is in `docs/migration/source-parity.md`; different protocols in `buaa-api` (such as App grades/exams, iClass classroom, per-course SPOC lists, or absent Judge support) are not substituted for local APIs. No submission, upload, reservation, attendance, grading, or other write operation is exposed.
