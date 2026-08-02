# Decisions — distrofetch

One entry per call that would be expensive to reverse. Newest first. Never edit a past
entry; supersede it with a new one and link back.

Not every choice belongs here. If reversing it is an afternoon's work, it is not a
decision, it is a preference.

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
