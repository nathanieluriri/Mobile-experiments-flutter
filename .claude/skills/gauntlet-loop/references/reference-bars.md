# Reference bars

A bar names a real, inspectable thing the critic can compare against. Pick the closest row,
then make it specific to the work ("Linear's empty states", not "Linear"). If nothing fits,
ask the user for one rather than inventing a vague one.

| Domain | Default bar | What the critic compares |
| --- | --- | --- |
| Mobile UI (Flutter) | The platform's first-party apps (iOS Notes, Google Keep) for the same screen type | Spacing rhythm, touch targets (48dp min), motion, empty/error/loading states, dark mode |
| Reading / document UI | Apple Books and Readwise Reader | Typography, margins, page turns, selection, zoom, perceived load time |
| Web dashboard | Vercel and Linear dashboards | Information density, empty states, keyboard access, latency feel |
| CLI tool | `gh` and `ripgrep` | Help text, error messages, exit codes, defaults, speed |
| Library / API | The best-known library in the same niche | Naming, error types, docs examples that run, edge-case behavior |
| Parser / file format | A reference implementation (e.g. pdf.js, Poppler for PDF) | Output on a shared corpus of real files, including malformed ones |
| Data pipeline | Idempotent reruns with row-count reconciliation | Reruns, partial failure, schema drift, backfill |
| Docs / README | Stripe docs | A newcomer completes the task from the doc alone, every snippet runs |
| Tests | Mutation testing mindset | Would a plausible bug in the code make a test fail |
| Performance | A measured number from a named device or baseline | Frame times, cold start, memory, against the stated target |

## Making a bar usable

- **Name the instance.** "Apple Books' page-turn and margin behavior on iPhone" beats
  "Apple Books".
- **Say what is out of scope.** A bar about typography does not make a missing sync feature
  an issue.
- **Keep it checkable with the chosen evidence.** If the evidence is screenshots, the bar
  must be visible in screenshots.
