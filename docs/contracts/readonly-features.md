# Read-Only Feature Contract

The CLI exposes only the facade methods below. Host code never imports `upstream` or builds a campus URL. Every result contains stable DTO data and the resolved route; raw HTML, encrypted parameters, token values, Cookies, and response bodies remain internal.

| Feature | CLI | Facade | Frozen request evidence |
|---|---|---|---|
| Schedule | `schedule terms`, `weeks`, `current`, `today` | `schedule_terms`, `schedule_weeks`, `schedule_week`, `schedule_today` | `schoolCalendars.do`, `getTermWeeks.do`, `getMyScheduleDetail.do`, `teachingSchedule/detail.do`; `Schedule.kt` |
| Exam | `exam list --term` | `exam_arrangement` | `student/exams.do`; `Exam.kt` |
| Grades | `grades list --term` | `grades` | `buaascore/wap/default/index`, activation GET then `xq`/`year` form POST; `Grade.kt` |
| Classroom | `classroom search --campus --date` | `classroom_search` | SSO sync URL then `buaafreeclass/.../search1?xqid=&floorid=&date=`; `Classroom.kt` |
| SPOC | `spoc assignments`, `spoc assignment show --id` | `spoc_assignments`, `spoc_assignment` | current-term, course and assignment/detail endpoints; `Spoc.kt` |
| Judge | `judge assignments`, assignment `show`/`details` | `judge_assignments`, `judge_assignment`, `judge_assignment_details` | SSO service, course/assignment HTML links and detail pages; `Judge.kt` |

Schedule term values and week serials are selected from the upstream response. Grades reject terms that do not match `yyyy-yyyy-semester`. Classroom dates must use `yyyy-mm-dd`; `UBAA_VERIFY_CAMPUS_ID` and `UBAA_VERIFY_DATE` are non-secret live-verifier overrides. Empty lists and empty classroom maps are valid parsed results; an unsupported undergraduate portal or missing account capability is a real, nonzero live failure.

The implementation ports the frozen read paths, including SPOC encrypted pagination/token/role setup, detail/submission status and HTML normalization, plus Judge course selection, detail parsing, six-month cutoff and route/session-scoped caches. Deterministic fixtures and Mock transports establish request shape; only the live matrix can establish current upstream availability. No submission, upload, reservation, attendance, grading, or other write operation is exposed.
