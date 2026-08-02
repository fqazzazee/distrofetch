# Decisions — distrofetch

One entry per call that would be expensive to reverse. Newest first. Never edit a past
entry; supersede it with a new one and link back.

Not every choice belongs here. If reversing it is an afternoon's work, it is not a
decision, it is a preference.

---

## 2026-08-01 — The animation is opt-in, default duration 0

**Status:** accepted

**Context:** Resolves the first open question in SPEC.md. The rain is the reason the tool
exists, but the place a fetch tool actually runs is a shell startup file, once per new
terminal.

**Decision:** `--duration` defaults to `0`, which skips the animation. `distrofetch -d 2`
gets the full effect.

**Alternatives:** Defaulting to 2 seconds, which shows off the feature and matches what
someone expects after reading the README. Rejected because a two-second delay on every
new shell is the kind of thing people fix by uninstalling rather than by reading `--help`.
Also considered a `--rain` flag as a friendlier alias for `-d 2`; left out because one way
to set the duration is enough until someone asks.

**Consequences:** The headline feature is invisible unless the user reads the help or the
README, so both now lead with `-d 2`. `--no-rain` is now the default behavior rather than
an override — kept because it is explicit and costs one line, but it is dead weight if a
future version grows a config file that could turn rain on persistently.

Note the implementation constraint this creates: a duration of `0` has to skip
`render_rain` entirely rather than call it with `0`, because that function clears the
screen on the way out.

---

## 2026-08-01 — Bash rather than Go

**Status:** accepted

**Context:** Set during scaffolding. Go was considered first, and would have given a
single static binary with no coreutils dependency and trivial cross-compilation for
releases.

**Decision:** Implement in Bash, targeting 5.0+.

**Alternatives:** Go. Rejected because the tool's appeal is that it is short enough to
read before running and works on a fresh box with nothing installed — a compiled binary
inverts both of those. The cost is real: no static typing, no test framework beyond
bats, and string handling that has to be written carefully to survive `set -euo pipefail`.

**Consequences:** Distribution is a tarball plus `make install`, not a binary release.
Correctness across distros has to be proven by running on them, which is why the smoke
matrix exists rather than being optional. Moving to Go later means rewriting everything
except the SPEC.

---

## 2026-08-01 — Pinned Bash 5.0 as the floor

**Status:** accepted

**Context:** Set during scaffolding. Arch, Debian 12, and Fedora all ship Bash 5.2.
The only meaningful reason to target 4.x would be macOS's system bash 3.2.

**Decision:** Target Bash 5.0+. CI runs on the ubuntu-latest bash.

**Alternatives:** Bash 4.4, which would widen support to older enterprise distros and
macOS. Rejected because macOS is an explicit non-goal — the probes read `/proc`, which
Darwin does not have, so bash compatibility would not make it work anyway.

**Consequences:** RHEL 7 and anything older than Debian 10 are out. Features from bash
5.1+ (`ulimit -R`, the `SRANDOM` variable) are off the table until this is superseded.

---

## 2026-08-01 — Detection split from rendering

**Status:** accepted

**Context:** A three-hundred-line fetch tool does not need a module system. This split
was made anyway.

**Decision:** `lib/detect.sh` holds probes that print one line and never exit;
`lib/render.sh` holds everything that touches the terminal.

**Alternatives:** One file. Rejected because the probes are the part that breaks per
distro and therefore the part that needs testing, and testing them through the renderer
means every test needs a terminal.

**Consequences:** Adding a fact means touching four places (probe, renderer, bats test,
smoke assertion) instead of one. That is the price of the probes being independently
testable, and it is written into AGENTS.md so it does not get half-done.

---

## 2026-08-01 — Minimal CI, but the distro smoke matrix stays

**Status:** accepted

**Context:** Set during scaffolding. Hardened CI — CodeQL, Dependabot, dependency
review, secret scanning — was offered and declined.

**Decision:** Lint, format, and test on push and PR. Plus the Arch/Debian/Fedora smoke
matrix, which is not part of "minimal" but was kept deliberately.

**Alternatives:** Fully minimal. Rejected because this tool's entire failure mode is
behaving differently on a distro the author does not run — the smoke matrix is not
ceremony here, it is the only test that covers the actual risk. CodeQL was dropped
partly on preference and partly because it has no Bash analyzer, so it would have cost
runtime and found nothing. Secret scanning was dropped because the project handles no
credentials.

**Consequences:** Dependency vulnerabilities are not tracked automatically — acceptable
while there are no dependencies, and this entry gets superseded the moment there are.

---

## Template

## YYYY-MM-DD — <one-line decision>

**Status:** proposed | accepted | superseded by <link>

**Context:** What forced the choice. Constraints that were real at the time.

**Decision:** What was chosen.

**Alternatives:** What was rejected, and the specific reason — not "worse", but what
about it was worse.

**Consequences:** What this now commits us to, and what it costs to undo.
