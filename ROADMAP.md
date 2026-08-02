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
- [ ] Branch protection on `main` requiring the CI checks

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

## Phase 2 — The animation is worth watching

Phase 1 makes it correct. This makes it the reason someone installs it over `uname -a`.

**Goal:** the rain reads as the film effect, not as random characters, and it costs
nothing on a machine where it is unwanted.

**Exit condition:** glyphs fall in coherent columns with a bright leading character and a
fading tail; the animation runs at a stable frame rate in a 200-column terminal without
pegging a core; `--no-rain` and non-TTY output are provably escape-free.

- [x] Column-based trails with a lit head and a decaying tail, replacing scattered glyphs
- [x] Degrade to ASCII when the locale cannot render half-width katakana
- [x] Measure it: 2 seconds of rain costs ~0.24s CPU at 80 columns and ~0.73s at 200 —
      roughly 12% and 36% of one core, measured with `times` under a pty
- [x] Run on the alternate screen buffer so the animation does not destroy scrollback
- [x] Wordmark banner and a frame around the report, `--no-art` to suppress
- [x] Values resolve out of noise after the rain instead of appearing all at once
- [ ] Frame budget instead of a fixed `sleep 0.045`, so wide terminals do not stutter
- [ ] Handle `SIGWINCH` mid-animation
- [ ] Font fallback: a UTF-8 locale does not prove the font has katakana. A terminal
      without it shows tofu, and nothing here detects that

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
- `--json` output, which would make it scriptable and is a different tool's job
- Alpine and musl support, which means auditing every coreutils flag used
- Theming beyond the matrix palette

## Archive

<!-- Completed phases move here with the date they exited. Keeps the top of the file about
     what is happening now. -->
