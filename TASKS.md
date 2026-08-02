# distrofetch — Tasks

Current phase only. See `ROADMAP.md` for the phase and its exit condition.

**Phase:** Phase 0 — Scaffolding

## Now

<!-- One item. What is actually being worked on. -->

- [ ] Push to GitHub and confirm the CI and smoke-distro workflows are green on the
      first run

## Next

<!-- Ready to start, ordered. If a task is not small enough to describe in a line, split
     it. -->

- [ ] Turn on branch protection for `main`: require the shellcheck, shfmt, and bats
      checks plus all three smoke jobs
- [ ] Enable private vulnerability reporting in repo settings — SECURITY.md links to it
- [ ] Enable Discussions, or drop the link from `.github/ISSUE_TEMPLATE/config.yml`
- [ ] Resolve the three open questions in SPEC.md, starting with the default rain
      duration
- [ ] Verify `make install PREFIX=~/.local` and run the installed copy from `/`

## Blocked

<!-- What is blocking it, and what would unblock it. A blocked task with no named blocker
     is not blocked, it is avoided. -->

- [ ] Confirm the smoke matrix finds no `unknown` fields — *blocked on:* the first
      workflow run, which needs the repo pushed

## Done this phase

<!-- Cleared when the phase exits. -->

- [x] Scaffold the repo from the baseline recipes
- [x] Working entry point, detection and rendering split into `lib/`
- [x] bats suite covering the CLI contract and probe shape
- [x] `make` targets shared by CI and local development
