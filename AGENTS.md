# AGENTS.md — distrofetch

Matrix-styled system information for Linux — a single Bash script that prints what the
machine is, introduced by a rain of glyphs.

Read `SPEC.md` before proposing anything architectural. Read `ROADMAP.md` before proposing
anything at all — work that belongs to a later phase does not get done early.

## Stack

- **Language:** Bash 5.0+ — pinned, see SPEC.md
- **Package manager:** none. No runtime dependencies beyond coreutils, and that is a
  feature, not an oversight
- **Tests:** bats
- **Lint / format:** shellcheck, and shfmt with `-i 2 -ci -bn`

Do not upgrade a pinned version as a side effect of another change. Version bumps are their
own PR with their own reason.

## Commands

```bash
make lint         # shellcheck
make fmt-check    # shfmt, non-destructive
make test         # bats
make smoke        # run the real entry point against this machine
```

Run these locally before pushing. CI confirms; it does not discover — every CI job calls
the same make target you just ran.

## Working here

- One concern per PR. If the diff needs a section header, split it.
- Tests land with the change, not after it.
- Match the surrounding code — its naming, its comment density, its idioms. New code
  should be hard to pick out of a diff by style alone.
- Comments explain why. What is already in the code.

## Shape of this codebase

- `lib/detect.sh` holds probes; `lib/render.sh` holds output. The split is load-bearing:
  it is what lets the probes be tested without a terminal.
- **Every probe prints exactly one line and never exits.** A fact that cannot be
  determined comes back as the literal `unknown`. This is why the renderer has no error
  handling, and breaking it breaks the renderer silently.
- Anything printed to a terminal must have a non-TTY path. Check `[ -t 1 ]`, do not
  assume.
- Four libraries: `detect.sh` probes the machine, `dmi.sh` reads DMI and SMBIOS,
  `hwdata.sh` looks up what the machine cannot know about itself, `render.sh` draws.
- New fact means: a probe in `detect.sh`, a row in the relevant `_df_build_*` panel, a
  line in `render_plain`, a case in the bats shape test, and a label in the smoke
  workflow's field list. All five, or the smoke test passes while the feature is missing.
- The report is drawn twice from the same data: once as panels, once plain. Anything
  that changes a line's visible width has to go through `_df_panel`, which is told the
  width separately because `${#}` counts ANSI escapes and multibyte characters wrong.
- **`${#str}` counts bytes outside a UTF-8 locale.** Never measure a rendered line. The
  frame is built by repetition so its width is known; logos are ASCII so theirs can be
  measured; values must be ASCII for the same reason — an em dash in a value silently
  shifts a panel edge in the C locale.
- `[ test ] && assign` as the last statement of a function returns 1 when the test is
  false, and under `set -euo pipefail` that kills the caller. Use `if`. This has bitten
  this codebase three times.
- Bundled tables in `lib/data/` are snapshots. A live source always wins; a miss prints
  `unknown`. Never fill a gap with arithmetic or a policy rule — a visible gap is a bug
  report, a confident wrong date is not.
- The SMBIOS parser reads firmware-controlled binary data. Bounds-check every offset,
  treat every field as data, and never read offset 0x18 (the module serial).

## Do not

- Add a dependency without saying what it replaces and what it costs. The bar here is
  high — "no runtime dependencies" is in the README as a promise.
- Silence a linter with an inline disable unless the reason is in a comment on the same
  line.
- Reformat files you did not otherwise change.
- Use `eval`, or pass any value read from `/proc` or a package manager to a shell. Probe
  output is data, never code.
- Add a probe that requires root, writes to the filesystem, or makes a network call.
  Read-only and unprivileged is the whole security posture — see SPEC.md.
- Source a file the project does not ship without writing down why. `/etc/os-release` is
  the one exception and it is justified in SPEC.md.

## Commits

Author as Fadi Q <fadi.qazzazee@gmail.com>. No commit message convention is enforced;
write a subject line that says what changed for a user.
