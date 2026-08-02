# distrofetch — Specification

> Status: draft · Last updated: 2026-08-01
>
> Sections marked `<!-- assumed -->` were guessed during scaffolding. Confirm or fix them
> before starting Phase 2.

## Problem

System information tools are either heavy (neofetch is ~10k lines of Bash with a config
file, image protocols, and hundreds of distro logos) or plain (`uname -a` and `free -h`,
run separately). Both are fine. Neither is fun to look at, and the heavy one is slow
enough on a cold cache that you notice.

distrofetch prints the facts you actually want about a Linux machine, introduced by a
matrix-style rain of glyphs, in a script short enough to audit before running.

## Intended users

<!-- assumed -->
Linux users who post terminal screenshots, run `fetch` in their shell rc, or want a
quick read of an unfamiliar box — plus anyone who lands on a minimal container or a
fresh install and wants the specs without installing a toolchain first.

## Required behavior

1. Print user@hostname, OS, kernel, architecture, uptime, package count, shell, CPU
   model with logical core count, and memory used/total.
2. Every probe returns exactly one line; a probe that cannot determine its fact returns
   the literal string `unknown` rather than failing or printing nothing.
3. Animate falling glyphs before the report, for a duration the user controls.
4. Detect that stdout is not a terminal and skip the animation and cursor control
   automatically, so piped and redirected output contains no escape sequences.
5. Disable all color on request, producing plain ASCII output.
6. Exit `0` on success and `2` on a usage error, writing usage errors to stderr.
7. Select the package-count backend from what is present on the system: pacman, then
   dpkg, then rpm.
8. Restore the cursor and reset the terminal if interrupted mid-animation.
9. Run from a source checkout and from an installed prefix without configuration.

## UX

```
distrofetch [-n|--no-rain] [-c|--no-color] [-d|--duration N] [-v|--version] [-h|--help]
```

Report format — a two-line header, then one aligned `Label: value` per fact:

```
user@host
────────────────────────────────
OS:        Fedora Linux 44 (Workstation Edition)
Kernel:    Linux 7.1.5-201.fc44.x86_64
...
```

Labels render in green, values in bright green, the rule in dim green. With `--no-color`
the same layout renders with no escape sequences at all.

## Architecture

Three files. The split between detection and rendering is the only structural decision
here, and it exists so the probes can be tested without a terminal and the animation can
be skipped without touching detection.

### Components

| Component | Responsibility |
|---|---|
| `bin/distrofetch` | Argument parsing, library path resolution, orchestration |
| `lib/detect.sh` | Host probes. One line of stdout each, never exits, never writes |
| `lib/render.sh` | Palette, glyph animation, report layout |
| `Makefile` | lint / fmt / test / dist / install — the same targets CI runs |
| `tests/distrofetch.bats` | CLI contract plus probe shape assertions |

### Data flow

`main` parses flags → `render_init` fixes the palette → `render_rain` runs if stdout is
a terminal and rain is enabled → `render_report` calls each `detect_*` probe and formats
the result. Detection is pull-based and lazy; nothing is cached, because the process
lives for under a second.

## Security and privacy

The threat model is modest but not empty: this is a script people are invited to
`curl | sudo make install`, and it reads system inventory.

- **Trust boundaries:** the local filesystem (`/etc/os-release`, `/proc`) and the package
  manager database. All are already readable by the invoking user; distrofetch requires
  no elevated privilege to run and must never ask for one.
- **Data handled and its sensitivity:** hostname, username, distro, kernel version,
  installed package count, and hardware model. Individually mundane, collectively a
  fingerprint — and kernel plus package data tells an attacker exactly which CVEs apply.
  This matters because the output is designed to be screenshotted and posted publicly.
- **Authentication / authorization:** none. The tool reads only what the caller can
  already read.
- **Secrets and how they are supplied:** none. There is no configuration file, no
  environment secret, and no credential of any kind.
- **What an attacker would go for:** the install path. `make install` writes to a PREFIX
  the user chooses, and a release tarball is the supply chain — hence checksums on every
  release artifact and a tag/version guard in the release workflow. Second: command
  injection through a probe. Probes must never `eval`, and any value read from `/proc` or
  a package manager is data, never code.

Non-obvious consequence of the above: **`/etc/os-release` is sourced**, which executes
it. It is root-owned on every supported distro, so a compromised copy already implies a
compromised system — but this is the one place distrofetch runs code it did not ship,
and any future probe that sources a file needs the same justification written down.

## Pinned versions

Changing anything in this table is a decision, and gets recorded in `docs/DECISIONS.md`.

| Thing | Version | Why this one |
|---|---|---|
| Bash | 5.0+ | <!-- assumed --> Arch, Debian 12, and Fedora all ship 5.2. Going lower buys only macOS's bash 3.2, and macOS is a non-goal |
| shfmt | 3.10.0 | Pinned so a formatting release cannot turn CI red on an unchanged tree |
| shellcheck | ubuntu-latest default | Tracks the runner image; a new warning class is worth knowing about |
| bats | Ubuntu package | Test assertions here are plain `[[ ]]`, so the version barely matters |

Supported platforms: Linux on x86_64. Arch, Debian stable, and Fedora are smoke-tested
on every push. <!-- assumed --> arm64 is expected to work but is not tested.

## Non-goals

- **macOS and BSD.** The probes read `/proc`. Supporting Darwin means a second detection
  implementation against `sysctl` and IOKit, not a compatibility shim.
- **ASCII distro logos.** The glyph rain is the visual identity. Logos are what makes
  neofetch large.
- **A configuration file.** Flags only. If a fact is worth showing, it is worth showing
  by default.
- **Images in the terminal.** No sixel, no kitty graphics protocol, no w3m.
- **GPU, disk, theme, icon, or WM/DE detection.** Every one of these is a pile of
  vendor-specific special cases, and they are where fetch tools go to become unmaintainable.
- **Non-Linux package managers**, Nix, and Homebrew. <!-- assumed -->
- **Running as root or requiring elevated privilege** for any probe.

## Acceptance criteria

- [ ] `make lint`, `make fmt-check`, and `make test` pass on a clean checkout
- [ ] `distrofetch --no-color | grep -c ''` produces the report with zero escape bytes
- [ ] The smoke-test matrix passes on Arch, Debian, and Fedora with no field reporting
      `unknown`, and each distro selects its own package backend
- [ ] `make install PREFIX=$(mktemp -d)` then running the installed copy from outside the
      source tree works
- [ ] Ctrl-C during the animation restores the cursor and leaves the terminal usable
- [ ] `make dist` produces a tarball plus a checksum that `sha256sum -c` verifies
- [ ] Total script size stays under 500 lines across `bin/` and `lib/`

## Open questions

- Should the rain duration default to 2 seconds, or to 0 with the animation opt-in? Two
  seconds is a long time for something in a shell rc file. <!-- assumed -->
- Is a package count worth the three code paths it costs? It is the only probe that
  differs per distro, and therefore the only reason the smoke matrix earns its runtime.
- arm64: claim support and test it under QEMU, or stay silent about it?
