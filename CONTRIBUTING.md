# Contributing to distrofetch

## Before you write code

Open an issue for anything beyond a typo fix. A rejected PR wastes more of your time than
a rejected issue. Check `ROADMAP.md` too — work that belongs to a later phase will be asked
to wait, and the non-goals in `SPEC.md` list things that have already been declined
(distro logos, config files, GPU detection, macOS).

The most useful contribution is not a feature. It is a report from a distro or a machine
that is not in the smoke matrix, with the output of `distrofetch --no-color` attached.

## Setup

```bash
git clone https://github.com/fqazzazee/distrofetch.git
cd distrofetch
make check-tools    # tells you what to install: shellcheck, shfmt, bats
make test
```

Install the three tools with your package manager:

```bash
sudo pacman -S shellcheck shfmt bash-bats      # Arch
sudo apt install shellcheck shfmt bats         # Debian
sudo dnf install ShellCheck shfmt bats         # Fedora
```

If the tests do not pass on a clean checkout, that is a bug — please report it.

## Pull requests

- One concern per PR. Two unrelated fixes are two PRs.
- Tests come with the change.
- Run `make lint`, `make fmt-check`, and `make test` before pushing.
- Describe what changes for a user, not what changed in the code — the diff already says
  that.
- Match the existing style. Do not reformat files you did not otherwise touch.

Every check on the PR must be green before review, including all three smoke jobs. If a
check is flaky, say so rather than re-running it until it passes.

## Adding a probe

A new fact in the report touches four places, and all four are required:

1. A `detect_*` function in `lib/detect.sh`. It prints **exactly one line**, never exits,
   and returns the literal `unknown` when it cannot determine the fact.
2. A `_field` call in `render_report` in `lib/render.sh`.
3. The probe name in the shape test in `tests/distrofetch.bats`.
4. The label in the field list in `.github/workflows/smoke-distros.yaml`.

Skip the fourth and the smoke matrix will pass while your probe is broken on two distros.

Probes must stay read-only, unprivileged, and offline. No `eval`, and nothing read from
`/proc` or a package manager gets passed to a shell.

## Style

shfmt with `-i 2 -ci -bn` is the arbiter; `make fmt` will rewrite files for you. Beyond
that: quote your expansions, prefer `printf` to `echo`, and remember every function runs
under `set -euo pipefail`.

## Reporting bugs

Include the version, the distro and architecture, your bash version, what you ran, what
happened, and what you expected. The bug report template asks for the full
`distrofetch --no-color` output — it is usually enough to identify which probe failed.

Security issues do not go in the issue tracker — see [`SECURITY.md`](SECURITY.md).
