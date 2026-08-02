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
3. Animate falling glyphs before the report, for a duration the user controls. The
   animation is opt-in: the default duration is `0`, which skips it entirely. A duration
   of `0` must bypass the animation code rather than run it for zero seconds, since it
   clears the screen on exit.
4. Render the rain as columns, not scatter: each column is one stream with its own
   position, speed, and trail length, a white leading glyph, and a tail that fades
   through the green ramp before being erased. Scattered characters are not the effect.
5. Run the animation on the alternate screen buffer and return to the normal buffer
   before printing the report, so nothing the user had on screen is destroyed.
6. Print a wordmark banner and a box frame around the report by default. `--no-art`
   suppresses both, and they are suppressed automatically when the terminal is narrower
   than the frame — wrapping every line is worse than not drawing it.
7. Resolve the report's values out of random glyphs when the animation ran, redrawing
   the field block in place. This is the settle, and it only happens on the path that
   already required a terminal.
8. Fall back to an ASCII glyph set outside a UTF-8 locale. `${var:i:1}` slices bytes
   rather than characters there, which turns half-width katakana into mojibake.
9. Detect that stdout is not a terminal and disable the animation, the cursor control,
   **and color** automatically, so piped and redirected output contains no escape
   sequences. Skipping only the animation is not enough — color alone still writes
   escapes into the file.
10. Resolve color from `--color=WHEN`, where `WHEN` is `always`, `never`, or `auto`, and
    `auto` is the automatic behavior in 9. `--no-color` is an alias for `never`. Reject
    any other value with a usage error that names the three valid ones.
11. Gate the animation on a real terminal independently of color. `--color=always` forces
    escapes into a pipe by request; it must never force cursor positioning or a screen
    clear into one.
12. Exit `0` on success and `2` on a usage error, writing usage errors to stderr.
13. Select the package-count backend from what is present on the system: pacman, then
    dpkg, then rpm.
14. Restore the cursor, leave the alternate screen, and reset the palette if interrupted
    mid-animation.
15. Run from a source checkout and from an installed prefix without configuration.

## UX

```
distrofetch [-d|--duration N] [-n|--no-rain] [--no-art] [--color=WHEN]
            [-c|--no-color] [-v|--version] [-h|--help]
```

Bare `distrofetch` prints the framed report immediately. `distrofetch -d 2` is the full
effect: rain, then the report assembling out of it.

Report format — the wordmark, the host line, then one aligned `Label: value` per fact,
all inside a frame sized to the widest line:

```
┌────────────────────────────────────────────────────────┐
│ ███  ████ ████ ████ ███  ████ ████ ████ ████ ████ █  █ │
│ █  █  ██  █     ██  █  █ █  █ █    █     ██  █    █  █ │
│ █  █  ██  ████  ██  ███  █  █ ███  ███   ██  █    ████ │
│ █  █  ██     █  ██  █ █  █  █ █    █     ██  █    █  █ │
│ ███  ████ ████  ██  █  █ ████ █    ████  ██  ████ █  █ │
│ user@host                                              │
├────────────────────────────────────────────────────────┤
│ OS:        Fedora Linux 44 (Workstation Edition)       │
│ Kernel:    Linux 7.1.5-201.fc44.x86_64                 │
└────────────────────────────────────────────────────────┘
```

Labels render in green, values in bright green, the frame in dim green, and the banner
runs top to bottom through the same five-step ramp the rain fades through. `--no-art`
gives the bare `Label: value` lines with no frame — the shape anything parsing this
wants. With `--no-color` either layout renders with no escape sequences at all.

The frame is drawn only when the terminal can hold it. Width comes from `COLUMNS` when
that is set and numeric, then `tput cols`, then 80 — the same precedence `less` uses,
and the reason the narrow-terminal fallback is testable without allocating a pty.

## Architecture

Three files. The split between detection and rendering is the only structural decision
here, and it exists so the probes can be tested without a terminal and the animation can
be skipped without touching detection.

### Components

| Component | Responsibility |
|---|---|
| `bin/distrofetch` | Argument parsing, library path resolution, orchestration |
| `lib/detect.sh` | Host probes. One line of stdout each, never exits, never writes |
| `lib/render.sh` | Palette, glyph animation, banner, frame, report layout |
| `scripts/banner.sh` | Regenerates the five banner rows from a per-letter table |
| `Makefile` | lint / fmt / test / dist / install — the same targets CI runs |
| `tests/distrofetch.bats` | CLI contract, layout alignment, probe shape assertions |

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
- **Per-distro ASCII logos.** Hundreds of hand-maintained logos, one per distro, plus the
  detection to pick between them, is what makes neofetch large. The single `DISTROFETCH`
  wordmark is not that: it is five constant rows, generated by `scripts/banner.sh`, and
  it does not grow when a new distro ships.
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
- [ ] Bare `distrofetch` prints the report with no animation and no screen clear
- [ ] Every line of the frame ends at the same column, including the banner rows and a
      value wider than the wordmark
- [ ] `COLUMNS=40 distrofetch` falls back to the unframed report rather than wrapping
- [ ] A 2-second rain in a 200-column terminal stays well under one core
- [ ] `LC_ALL=C distrofetch -d 2` rains ASCII rather than mojibake
- [ ] The rain leaves the terminal's previous contents intact
- [ ] `make dist` produces a tarball plus a checksum that `sha256sum -c` verifies
- [ ] Total script size stays under 500 lines across `bin/` and `lib/`

## Open questions

- Is a package count worth the three code paths it costs? It is the only probe that
  differs per distro, and therefore the only reason the smoke matrix earns its runtime.
- arm64: claim support and test it under QEMU, or stay silent about it?
