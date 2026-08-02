# distrofetch — Specification

> Status: draft · Last updated: 2026-08-02
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

### The report

1. Print user@hostname, OS, kernel, architecture, uptime, package count, and shell.
2. Every probe returns exactly one line; a probe that cannot determine its fact returns
   the literal string `unknown` rather than failing or printing nothing.
3. Lay the facts out as a dashboard of five panels — system, distribution, processor,
   memory, machine — beside an ASCII logo of the running distribution. Two panel columns
   when the terminal is wide enough for both to hold a full value, one when it is not,
   and the plain list below 56 columns.
4. Every panel border lands in the same column. A grid that shears reads as a broken
   program, so width is computed rather than measured, and never measured from a
   rendered line.
5. `--no-art` prints one fact per line with no panels and no logo. That is the form
   anything parsing this output is told to use, and no part of the dashboard may leak
   into it.

### Distribution history

6. Report the release date and support status of the running distribution.
7. Take support status from `SUPPORT_END=` in `/etc/os-release` when the distribution
   ships it — Fedora, RHEL, and the RHEL rebuilds do — and from a bundled table
   otherwise. The live field always wins: it is current, and the table is a snapshot.
8. Report a rolling release as having no end of life rather than as missing data.
9. Say `unknown` for a release the bundled table does not cover. A stale end-of-support
   date is worse than a blank one: a blank is a gap, a wrong date is a lie the user acts
   on.
10. Colour a support status that has passed, and one within 90 days of passing,
    differently from a healthy one.

### Hardware detail

11. Report CPU vendor, model, microarchitecture, launch year, and process node.
    Microarchitecture is resolved from the `vendor/family/model` triple in
    `/proc/cpuinfo`, not from the marketing string — the same silicon ships under many
    names, and the triple is what actually identifies it.
12. Report core and thread counts from `/sys/devices/system/cpu/present`, not from the
    number of `processor` blocks in `/proc/cpuinfo`. The latter lists only *online*
    CPUs, so on a machine that parks cores the count changes between runs. Note the
    online count separately when it differs.
13. Report clock (current and maximum), cache sizes per level, and the instruction-set
    extensions that change what software will run.
14. Report memory used/total and swap used/total, and machine model, board, and firmware
    version with its date.
15. Report per-module memory size, type, form factor, rated and configured speed, and
    manufacturer, when the raw SMBIOS tables can be read.
16. **Never require root.** The raw SMBIOS tables are mode 0400, so module detail is
    available only to a privileged run. An unprivileged run states why the detail is
    missing and names the command that would show it; it must not print `unknown`, which
    reads as a failed probe rather than as a permission boundary.
17. Never read the memory module serial number. It is a durable hardware identifier and
    this output is designed to be posted publicly.

### The animation

18. Animate falling glyphs before the dashboard, for a duration the user controls. The
    animation is opt-in: the default duration is `0`, which skips it entirely.
19. Render the rain as columns, not scatter: each column is one stream with its own
    position, speed, and trail length, a white leading glyph, and a tail that fades
    through the green ramp before being erased.
20. Run the animation on the alternate screen buffer and return to the normal buffer
    before printing, so nothing the user had on screen is destroyed.
21. Fall back to an ASCII glyph set outside a UTF-8 locale. `${var:i:1}` slices bytes
    rather than characters there, which turns half-width katakana into mojibake.
22. Restore the cursor, leave the alternate screen, and reset the palette if interrupted
    mid-animation.

### Output discipline

23. Detect that stdout is not a terminal and disable the animation, the cursor control,
    **and color** automatically, so piped and redirected output contains no escape
    sequences.
24. Resolve color from `--color=WHEN`, where `WHEN` is `always`, `never`, or `auto`, and
    `auto` is the automatic behavior in 23. `--no-color` is an alias for `never`. Reject
    any other value with a usage error that names the three valid ones.
25. Gate the animation on a real terminal independently of color. `--color=always` forces
    escapes into a pipe by request; it must never force cursor positioning into one.
26. Exit `0` on success and `2` on a usage error, writing usage errors to stderr.
27. Select the package-count backend from what is present on the system: pacman, then
    dpkg, then rpm.
28. Reject a `--logo` value that is not a bundled name, before any output is written. A
    name is joined to a directory and a suffix, so a path must never be followed.
29. Run from a source checkout and from an installed prefix without configuration,
    resolving the shell libraries, the reference tables, and the logo art from the same
    base.

## UX

```
distrofetch [--logo=NAME] [--no-logo] [--no-art] [--list-logos]
            [-d|--duration N] [-n|--no-rain] [--color=WHEN] [-c|--no-color]
            [-v|--version] [-h|--help]
```

Bare `distrofetch` prints the dashboard immediately. `distrofetch -d 2` prefixes it with
two seconds of rain.

```
distrofetch 0.1.0                                          user@host
────────────────────────────────────────────────────────────────────

       _____    ┌─ SYSTEM ─────────────┐ ┌─ DISTRIBUTION ──────────┐
      /   __)\  │ OS        Fedora ... │ │ ID        fedora        │
      |  /  \ \ │ Kernel    Linux ...  │ │ Version   44            │
   ___|  |__/ / │ ...                  │ │ Support   until 2027-05 │
  / (_    _)_/  └──────────────────────┘ └─────────────────────────┘
 / /  |  |      ┌─ PROCESSOR ──────────┐ ┌─ MACHINE ───────────────┐
 \ \__/  |      │ Micro-arch Raptor ...│ │ Board     ...           │
  \(_____/      └──────────────────────┘ └─────────────────────────┘
                ┌─ MEMORY ─────────────────────────────────────────┐
                │ DIMM 0: 16 GiB DDR5 SODIMM @ 5200 MT/s (rated ...│
                └──────────────────────────────────────────────────┘
```

Memory gets the full width because a module line carries locator, size, type, form
factor, both speeds, and a part number, and it is the row people came for.

Labels render in green, values in bright green, the frame in dim green, the logo in
green. A support status that has passed renders in red; one within 90 days of passing
renders in amber. With `--no-color` the same layout renders with no escape sequences.

Width comes from `COLUMNS` when it is set and numeric, then `tput cols`, then 80 — the
same precedence `less` uses, and the reason the narrow-terminal fallback is testable
without allocating a pty. Total width is capped at 130 columns: panels stretched across
an ultrawide terminal are unreadable, because the eye has to travel the whole line to
pair a key with its value.

## Architecture

Three files. The split between detection and rendering is the only structural decision
here, and it exists so the probes can be tested without a terminal and the animation can
be skipped without touching detection.

### Components

| Component | Responsibility |
|---|---|
| `bin/distrofetch` | Argument parsing, library path resolution, orchestration |
| `lib/detect.sh` | Host probes. One line of stdout each, never exits, never writes |
| `lib/dmi.sh` | DMI text fields, and the SMBIOS type-17 parser |
| `lib/hwdata.sh` | Lookups against the bundled reference tables |
| `lib/render.sh` | Palette, glyph animation, panel engine, dashboard layout |
| `lib/data/*.tsv` | Distribution release/support data; CPU microarchitecture table |
| `lib/logos/*.txt` | One ASCII logo per distribution, plus a generic fallback |
| `Makefile` | lint / fmt / test / dist / install — the same targets CI runs |
| `tests/*.bats` | CLI contract, layout alignment, SMBIOS parsing, table lookups |
| `tests/fixtures/` | Synthetic SMBIOS records and DMI id files |

The split between detection and rendering exists so the probes can be tested without a
terminal. The split between detection and `hwdata.sh` is different in kind: detection
answers what the machine says about itself, `hwdata.sh` answers what the machine cannot
know — when a release shipped, when its support ends, what a family/model pair is
called.

**Logos are strictly ASCII.** `${#}` counts bytes rather than characters outside a UTF-8
locale, so an ASCII logo is the only kind whose column width is the same everywhere. The
frame is multibyte, which is why its width is computed by repetition rather than
measured.

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

### Hardware inventory

Reporting per-module memory detail widened the fingerprint, so two rules constrain it:

- **The module serial number is never read.** SMBIOS type 17 carries it at offset 0x18,
  next to the fields that are printed. It is a durable, globally unique hardware
  identifier, and this output exists to be screenshotted. The parser skips the offset
  entirely rather than reading and discarding it, so it cannot leak through a future
  change to the formatting.
- **Privilege is never requested.** The raw SMBIOS tables are mode 0400. distrofetch
  reports what an unprivileged process can see and names `sudo distrofetch` as the way
  to see more; it does not re-exec itself, prompt, or fail. A fetch tool that asks for
  root is a fetch tool that gets it, and that is a bad habit to teach.

The parser reads attacker-influenced binary data — firmware fills SMBIOS, and a
malicious hypervisor controls it entirely for a guest. It therefore treats every field
as data: string indices are bounds-checked against the structure, byte values are only
ever compared or arithmetic-shifted, and nothing read from the table reaches `eval`, a
glob, or a command name.

## Pinned versions

Changing anything in this table is a decision, and gets recorded in `docs/DECISIONS.md`.

| Thing | Version | Why this one |
|---|---|---|
| Bash | 5.0+ | <!-- assumed --> Arch, Debian 12, and Fedora all ship 5.2. Going lower buys only macOS's bash 3.2, and macOS is a non-goal |
| shfmt | 3.10.0 | Pinned so a formatting release cannot turn CI red on an unchanged tree |
| shellcheck | ubuntu-latest default | Tracks the runner image; a new warning class is worth knowing about |
| bats | Ubuntu package | Test assertions here are plain `[[ ]]`, so the version barely matters |

### Bundled data

| Table | Refreshed from | Goes stale |
|---|---|---|
| `lib/data/distro-releases.tsv` | <https://endoflife.date> | Every release and EOL announcement |
| `lib/data/cpu-arch.tsv` | Intel ARK, AMD product pages | Every new microarchitecture |

Both carry a `Data as of:` line that gets bumped on every refresh. Neither is consulted
where a live source exists: `SUPPORT_END=` beats the release table, and nothing beats
`/proc/cpuinfo` for what the CPU actually is. A row that cannot be confirmed is omitted
rather than guessed.

Supported platforms: Linux on x86_64. Arch, Debian stable, and Fedora are smoke-tested
on every push. <!-- assumed --> arm64 is expected to work but is not tested.

## Non-goals

- **macOS and BSD.** The probes read `/proc`. Supporting Darwin means a second detection
  implementation against `sysctl` and IOKit, not a compatibility shim.
- **A logo for every distribution that exists.** *Superseded 2026-08-02 — logos were
  previously a non-goal outright.* Roughly twenty are bundled, covering the distributions
  the project expects to run on, plus a generic fallback and an `ID_LIKE` rule so a
  derivative borrows its parent's art. What stays out of scope is the neofetch position:
  hundreds of hand-maintained logos with per-distro rendering quirks. A logo is one ASCII
  file with a width and height budget, or it is not added.
- **Image protocols for logos.** No sixel, no kitty graphics, no w3m. ASCII only, which
  is also what keeps the column width the same in every locale.
- **A configuration file.** Flags only. If a fact is worth showing, it is worth showing
  by default.
- **GPU, disk, theme, icon, or WM/DE detection.** Every one of these is a pile of
  vendor-specific special cases, and they are where fetch tools go to become unmaintainable.
- **Non-Linux package managers**, Nix, and Homebrew. <!-- assumed -->
- **Running as root or requiring elevated privilege** for any probe.

## Acceptance criteria

- [ ] `make lint`, `make fmt-check`, and `make test` pass on a clean checkout
- [ ] `distrofetch --no-color` produces the dashboard with zero escape bytes
- [ ] `distrofetch --no-art --no-color` produces one fact per line with no frame, no
      logo, and no escape bytes
- [ ] The smoke-test matrix passes on Arch, Debian, and Fedora: every probe populated,
      each distro selecting its own package backend and its own logo
- [ ] Every panel border lands in the same column at 60, 70, 80, 100, 120, 140, and 200
      columns, and no line exceeds the terminal width
- [ ] `COLUMNS=40 distrofetch` falls back to the plain list rather than wrapping
- [ ] `make install PREFIX=$(mktemp -d)` then running the installed copy from outside the
      source tree resolves libraries, tables, and logos
- [ ] The SMBIOS parser reads both size units, the 32-bit extended-size escape, an empty
      slot, and a record with no manufacturer, against synthetic fixtures
- [ ] No memory module serial number appears in any output
- [ ] An unprivileged run states why module detail is unavailable rather than printing
      `unknown`
- [ ] A rolling release reports no end of life; an expired release reports its overrun;
      an unknown release reports `unknown`
- [ ] Every bundled logo is pure ASCII, at most 20 rows and 30 columns
- [ ] `--logo` rejects a path and an unknown name, both before any output
- [ ] Ctrl-C during the animation restores the cursor and leaves the terminal usable
- [ ] A 2-second rain in a 200-column terminal stays well under one core
- [ ] `LC_ALL=C distrofetch -d 2` rains ASCII rather than mojibake
- [ ] The rain leaves the terminal's previous contents intact
- [ ] `make dist` produces a tarball plus a checksum that `sha256sum -c` verifies

## Open questions

- The distribution table has no Fedora or Arch release dates, so both report `Released:
  unknown`. Fedora ships `SUPPORT_END=` so its support status is right regardless, but
  the release date is a visible gap. Fill it, or drop the row when it is unknown?
- Should `dmidecode` be used when it is installed *and* the process is root, in
  preference to the built-in parser? It would cover firmware quirks this parser has never
  seen, at the cost of a conditional dependency and two code paths that can disagree.
- The CPU table keys on `vendor/family/model` and therefore says nothing about which
  *part* is installed — a Raptor Lake i3 and i9 look identical to it. Worth adding a
  model-string layer, or is the microarchitecture the useful fact?
- arm64: claim support and test it under QEMU, or stay silent about it? `/proc/cpuinfo`
  has no `model name` there, and no SMBIOS on most boards.
- Is a package count worth the three code paths it costs? It remains the only probe that
  differs per distro, and therefore a reason the smoke matrix earns its runtime.
