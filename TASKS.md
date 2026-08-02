# distrofetch — Tasks

Current phase only. See `ROADMAP.md` for the phase and its exit condition.

**Phase:** Phase 2 — The dashboard tells you something you did not know

## Now

<!-- One item. What is actually being worked on. -->

- [ ] Verify the SMBIOS type-17 parser against real firmware: `sudo distrofetch` on at
      least two machines with different vendors, and compare against `sudo dmidecode -t 17`

## Next

<!-- Ready to start, ordered. If a task is not small enough to describe in a line, split
     it. -->

- [ ] Add Fedora and Arch release dates to `lib/data/distro-releases.tsv`; both report
      `Released: unknown` today
- [ ] Confirm `cpu-generations.tsv` is current before release — a missing newest row
      makes every "N generations behind" under-report
- [ ] Warn when a bundled table's `Data as of:` date is more than a year old
- [ ] Decide whether `dmidecode` should be preferred when present *and* running as root
- [ ] Enable private vulnerability reporting in repo settings — SECURITY.md links to it
- [ ] Enable Discussions, or drop the link from `.github/ISSUE_TEMPLATE/config.yml`
- [ ] `gh repo edit --delete-branch-on-merge`; branches are being deleted by hand
- [ ] Resolve the open questions in SPEC.md, starting with whether the CPU table should
      grow a model-string layer

## Done this phase

- [x] Five-panel responsive dashboard, alignment-tested at seven widths
- [x] Per-distro ASCII logos with `ID_LIKE` fallback
- [x] Distribution release date and support status
- [x] CPU microarchitecture, launch year, process node, cache, clock, features
- [x] SMBIOS type-17 parser with synthetic fixtures
- [x] CPU generation, launch year, and distance from the newest known generation
- [x] Intel/AMD vendor marks in the processor panel
- [x] Branch protection on `main` requiring all six checks

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
