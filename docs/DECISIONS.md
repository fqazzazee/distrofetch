# Decisions — distrofetch

One entry per call that would be expensive to reverse. Newest first. Never edit a past
entry; supersede it with a new one and link back.

Not every choice belongs here. If reversing it is an afternoon's work, it is not a
decision, it is a preference.

---

## 2026-08-02 — Per-distro ASCII logos, reversing a non-goal

**Status:** accepted — supersedes the "no ASCII distro logos" non-goal in SPEC.md

**Context:** SPEC.md listed per-distro logos as a non-goal, on the grounds that a logo
library is what makes neofetch large. The maintainer asked for them directly, having
seen that reasoning in the PR that introduced the wordmark.

**Decision:** Bundle roughly twenty ASCII logos in `lib/logos/`, pick one from `ID=`,
fall back through `ID_LIKE` to a parent distro, and fall back finally to a generic
penguin. `--logo` forces one, `--no-logo` drops the column. The `DISTROFETCH` wordmark
this replaces is deleted.

**Alternatives:** Keeping the wordmark alongside the logo — rejected as visual noise
once there are five panels and a logo competing for the top of the screen. Sixel or
kitty graphics — rejected and recorded as a standing non-goal; ASCII is also what keeps
the logo column the same width in every locale.

**Consequences:** The project now carries artwork, which is a maintenance category it
did not have: every new distribution is a request, and every logo is a width and height
budget rather than a drawing. The rule that keeps this from becoming neofetch is that a
logo is one ASCII file with no per-distro rendering code — the alias table in
`hwdata_logo_name` is the only place a distribution name may appear in logic, and it
maps names to *existing* files rather than adding behaviour.

---

## 2026-08-02 — Bundled reference tables, with the live source always winning

**Status:** accepted

**Context:** Release dates, end-of-support dates, and CPU microarchitecture names are not
on the machine. Reporting them means shipping data, and shipped data goes stale.

**Decision:** Two tab-separated tables under `lib/data/`, each carrying a `Data as of:`
date and a refresh source. A live source always beats the table: `SUPPORT_END=` from
`/etc/os-release` is authoritative where the distro ships it, and the table is not
consulted for support status at all in that case. A lookup miss prints `unknown`.

**Alternatives:** Querying endoflife.date at runtime — rejected outright; "no network
calls" is a promise in the README and the reason this is safe to run on a box you do not
trust. Deriving support windows from a policy rule per distro (Ubuntu LTS is five years,
Fedora is thirteen months) — rejected because the exceptions are the interesting cases,
and a rule that is right most of the time is a rule nobody checks.

**Consequences:** Someone has to refresh two files, and nothing enforces it. That is why
a miss prints `unknown` rather than falling back to arithmetic: the failure mode is a
visible gap rather than a confident wrong answer. Fedora and Arch currently have no
release dates in the table and show `Released: unknown`, which is the mechanism working
as designed and also the first thing to fix.

---

## 2026-08-02 — Memory module detail is progressive, not privileged

**Status:** accepted

**Context:** Per-module manufacturer, type, and speed live in SMBIOS type 17. The kernel
exposes the raw structures at mode 0400, and `dmidecode` needs the same access. SPEC.md
has "running as root or requiring elevated privilege" as a non-goal, and "no runtime
dependencies beyond coreutils" as a promise.

**Decision:** Parse SMBIOS type 17 in Bash with `od`, from
`/sys/firmware/dmi/entries/17-*/raw`. Show module detail when the structures are
readable; when they are not, print the reason and the command that would work. Never
re-exec, never prompt, never fail.

**Alternatives:** Shelling out to `dmidecode` — rejected: it is not installed by default
on Debian or Arch, and adding a runtime dependency for one panel breaks a promise that is
in the README. Requiring root — rejected as a non-goal, and because a fetch tool that
asks for root is a fetch tool that gets it. Printing `unknown` — rejected because it
reads as a failed probe rather than a permission boundary, and would send people
debugging their firmware.

**Consequences:** The parser reads attacker-influenced binary data, so it is written to
treat every field as data and is tested against synthetic fixtures rather than against
one machine. The serial number at offset 0x18 is never read at all — not read and
discarded, but skipped — so no future formatting change can leak it. Undoing this means
either accepting a dependency or dropping the panel.

---

## 2026-08-02 — The dashboard replaces the boxed report

**Status:** accepted — supersedes "The banner and frame are on by default"

**Context:** The maintainer asked for a full-screen dashboard and said the animation was
not what they cared about. The previous layout was a single box with eight fields.

**Decision:** Five panels — system, distribution, processor, memory, machine — laid out
in two columns when the terminal is at least 108 usable columns, one column below that,
and the plain list below 56. Memory takes the full width in the two-column layout. The
value-reveal animation is deleted; the rain is kept behind `-d`.

**Alternatives:** Keeping the reveal and animating panel values — rejected: it was built
to redraw a fixed eight-line block, a five-panel grid would need a full-screen diff, and
the maintainer had just said animations were not the point. Making the dashboard opt-in
behind a flag — rejected, since it is now the product.

**Consequences:** Output went from ~18 lines to ~26, and its shape depends on terminal
width in a way it did not before. `--no-art` is now load-bearing rather than a
convenience: it is the documented interface for anything parsing this, and the smoke
tests assert no part of the dashboard leaks into it. Panel alignment became a class of
bug that needs its own tests, because a sheared grid reads as a broken program.

---

## 2026-08-01 — The banner and frame are on by default; the animation stays opt-in

**Status:** accepted

**Context:** The tool looked like `uname -a` with colors. The visual identity was entirely
in the rain, and the rain is off by default — so the thing people actually see was the
plain part. Two ways to fix that: turn the rain on by default, or make the still frame
worth looking at.

**Decision:** A `DISTROFETCH` wordmark and a box frame print every time, because they cost
no wall-clock time. The rain and the value reveal stay behind `-d`. `--no-art` turns the
static art off.

**Alternatives:** Defaulting `-d` to 2 seconds. Rejected for the same reason as the
[previous decision](#2026-08-01--the-animation-is-opt-in-default-duration-0) — a delay in
a shell startup file is uninstalled, not configured. Also considered a neofetch-style
per-distro logo panel, rejected as an explicit non-goal: the wordmark is five constant
rows and does not grow when a new distro ships.

**Consequences:** Default output went from 10 lines to 18, and its shape changed for
anything already parsing it — this is pre-1.0, but `--no-art` exists so the change is
recoverable without a revert. Frame width is now computed from the widest field, so a
long CPU model widens the box; below the frame's width the art turns itself off, which
means output shape now depends on `COLUMNS`. Adding a field means checking the alignment
tests, not just the probe tests.

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
