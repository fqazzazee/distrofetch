# distrofetch — Roadmap

Phases, in order. Each has an **exit condition** specific enough to argue about. A phase
is not done because the tasks are checked off; it is done because the exit condition holds.

Current phase: **Phase 0**

---

## Phase 0 — Scaffolding

Harness before features. Nothing here is a feature.

**Exit condition:** lint, format check, and the bats suite run green in CI on push and
on PRs; the distro smoke matrix passes on Arch, Debian, and Fedora against an installed
copy; `make dist` produces a verifiable tarball.

- [x] Repo, CI, and lint config in place
- [x] Test runner wired up, suite passing locally
- [x] `make install` and `make dist` produce real artifacts
- [ ] Smoke test green on all three distros
- [x] Branch protection on `main` requiring the CI checks

---

## Phase 1 — The report is correct everywhere

The probes are the product. A fetch tool that prints `unknown` on someone's machine is
worse than one that does not exist, because they already had `uname`.

**Goal:** every field populated correctly on the three tested distros, on bare metal,
in a VM, and in a container.

**Exit condition:** the smoke matrix asserts no field equals `unknown` — already wired —
and the same holds by hand on a VM and a Raspberry Pi. CPU detection handles the aarch64
`/proc/cpuinfo` layout, which has no `model name` field at all.

- [ ] Verify each probe against a container, a VM, and bare metal
- [ ] aarch64 CPU detection (`Model` / `Hardware` fields, or `/sys` fallback)
- [ ] Decide whether container-namespaced CPU and memory limits should be reported as
      the limit or the host value — and say so in SPEC.md either way
- [ ] Fixture-based probe tests: feed known `/proc` files in, assert exact output

---

## Phase 2 — The dashboard tells you something you did not know

**Goal:** the output answers questions `uname -a` and `free -h` cannot — how long this
release is supported, what this silicon actually is, what is in the memory slots.

**Exit condition:** every panel populated on the three tested distros; module detail
correct against real hardware under `sudo` on at least two machines with different
firmware; no panel border out of column at any terminal width.

- [x] Five-panel dashboard with a responsive two- and one-column layout
- [x] Per-distro ASCII logos with `ID_LIKE` fallback and a generic default
- [x] Release date and end-of-support status, live `SUPPORT_END=` beating the table
- [x] CPU microarchitecture, launch year, and process node from family/model
- [x] Core counts from `/sys/devices/system/cpu/present`, with offline cores noted
- [x] Cache, clock, and instruction-set extensions
- [x] SMBIOS type-17 parser for module size, type, speed, and manufacturer
- [x] CPU generation, its launch year, and distance from the newest known generation
- [x] Intel and AMD vendor marks in the processor panel, dropping out when narrow
- [x] Column-alignment tests across seven terminal widths
- [ ] **Verify the SMBIOS parser against real hardware.** It passes against synthetic
      fixtures covering both size units, the extended-size escape, empty slots, and
      absent strings — but has never seen a real firmware table, because the tables are
      mode 0400 and the developer machine cannot be tested without root
- [ ] Fedora and Arch release dates in the distribution table; they show `unknown` today
- [ ] Confirm `cpu-generations.tsv` has the newest generation before each release; a
      missing row silently under-reports every "N generations behind"
- [ ] A `Data as of:` staleness warning when the tables are more than a year old
- [ ] Decide whether `dmidecode` should be preferred when present *and* root

---

## Phase 2b — The animation, if anyone wants it

Deprioritised: the maintainer's position is that the animation is not the point. The
rain works and is tested; these are the open threads if it ever becomes interesting
again.

- [x] Column-based trails with a lit head and a decaying tail
- [x] Degrade to ASCII when the locale cannot render half-width katakana
- [x] Run on the alternate screen buffer so scrollback survives
- [x] Measured: 2 seconds costs ~0.24s CPU at 80 columns, ~0.73s at 200
- [ ] Frame budget instead of a fixed `sleep 0.045`
- [ ] Handle `SIGWINCH` mid-animation
- [ ] Font fallback: a UTF-8 locale does not prove the font has katakana

---

## Phase 3 — Ship it

**Goal:** someone on a distro I do not run can install a verified copy in one command.

**Exit condition:** `v0.1.0` tagged, release workflow green, tarball and checksum
attached; install instructions verified by someone who is not me.

- [ ] Tag `v0.1.0` and confirm the release workflow end to end
- [ ] AUR package
- [ ] COPR build for Fedora
- [ ] `install.sh` that verifies the checksum before extracting

---

## Later

<!-- Ideas that are not phases yet. No exit conditions, no commitment. Things get promoted
     out of here, never worked on in place. -->

- arm64 smoke tests under QEMU — roughly 10x slower, so only once arm64 is claimed
- More logos, contributed. The budget is the rule: ASCII, 20 rows, 30 columns
- GPU detection, which is where fetch tools go to become unmaintainable — still a
  non-goal, noted here because it is the most-requested thing this dashboard lacks
- `--json` output, which would make it scriptable and is a different tool's job
- Alpine and musl support, which means auditing every coreutils flag used
- Theming beyond the matrix palette

## Archive

<!-- Completed phases move here with the date they exited. Keeps the top of the file about
     what is happening now. -->
