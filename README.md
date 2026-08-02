# distrofetch

A full-screen system dashboard for Linux — distribution support status, processor
lineage, memory modules, and firmware, beside your distro's logo in ASCII.

[![CI](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml)
[![Smoke test (distros)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml)

## What it does

Prints a dashboard of what a Linux machine actually is — the distribution and how long it
is supported for, the processor down to its microarchitecture and launch year, the memory
modules with their speeds and manufacturers, the board and its firmware — beside an ASCII
logo of the running distro.

It reads `/etc/os-release`, `/proc`, `/sys`, and your package manager's database. No
network calls, no writes, and no root.

```console
$ distrofetch
distrofetch 0.1.0                                                                                            tesla@fadis-zenbook14
──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

       _____    ┌─ SYSTEM ─────────────────────────────────────────────┐ ┌─ DISTRIBUTION ────────────────────────────────────────┐
      /   __)\  │ OS        Fedora Linux 44 (Workstation Edition)      │ │ ID        fedora                                      │
      |  /  \ \ │ Kernel    Linux 7.1.5-201.fc44.x86_64                │ │ Version   44                                          │
   ___|  |__/ / │ Arch      x86_64                                     │ │ Codename  none                                        │
  / (_    _)_/  │ Uptime    2d 19h 55m                                 │ │ Released  unknown                                     │
 / /  |  |      │ Shell     bash                                       │ │ Support   supported until 2027-05-19 (289 days)       │
 \ \__/  |      │ Packages  2809 (rpm)                                 │ │                                                       │
  \(_____/      └──────────────────────────────────────────────────────┘ └───────────────────────────────────────────────────────┘
                ┌─ PROCESSOR ──────────────────────────────────────────┐ ┌─ MACHINE ─────────────────────────────────────────────┐
                │ Model      13th Gen Intel(R) Core(TM) i7-1360P (16)  │ │ Model     ASUSTeK COMPUTER INC. Zenbook Flip UP340... │
                │ Vendor     Intel                                     │ │ Board     ASUSTeK COMPUTER INC. UP3404VA              │
                │ Micro-arch Raptor Lake, launched 2023, Intel 7       │ │ Firmware  UP3404VA.301 (2023-05-11)                   │
                │ Signature  family 6, model 186, stepping 2, ucode... │ │                                                       │
                │ Topology   12 cores / 16 threads                     │ │                                                       │
                │ Clock      0.4 GHz now, 5.0 GHz max                  │ │                                                       │
                │ Cache      48K L1d, 32K L1i, 1280K L2, 18432K L3     │ │                                                       │
                │ Features   AVX2, AES-NI, SHA-NI, VT-x                │ │                                                       │
                └──────────────────────────────────────────────────────┘ └───────────────────────────────────────────────────────┘
                ┌─ MEMORY ───────────────────────────────────────────────────────────────────────────────────────────────────────┐
                │ RAM       6.6 GiB / 15.2 GiB                                                                                   │
                │ Swap      0.4 GiB / 7.9 GiB                                                                                    │
                │ Modules   needs root: run sudo distrofetch                                                                     │
                └────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Two panel columns when the terminal is wide enough, one when it is not, and a plain list
below 56 columns. Nothing here costs wall-clock time — it prints immediately, which is
the point for something you run from a shell startup file.

It is Bash and coreutils, with no runtime dependencies: it runs on the minimal container
or the freshly-installed box where you have not yet installed anything.

## What it can tell you that `uname -a` cannot

- **Whether your distribution is still supported**, and for how long. Taken from
  `SUPPORT_END=` in `/etc/os-release` where the distro ships it — Fedora, RHEL, and the
  RHEL rebuilds do — and from a bundled table otherwise. An expired release is coloured
  red, one within 90 days amber.
- **What your CPU actually is.** "13th Gen Intel Core i7-1360P" is a marketing string;
  `family 6, model 186` is Raptor Lake, launched 2023 on Intel 7. The same silicon ships
  under several names, so the lookup keys on the family/model pair.
- **Real core counts.** Read from `/sys/devices/system/cpu/present` rather than by
  counting `/proc/cpuinfo` blocks, which lists only *online* CPUs — so on a laptop that
  parks cores, the naive count changes between runs. Offline cores are noted, not hidden.
- **Your memory modules**: size, type, form factor, rated *and* configured speed, and
  manufacturer. The gap between rated and configured is how you notice XMP is off.

Module detail comes from the raw SMBIOS tables, which the kernel exposes at mode `0400`.
An unprivileged run says so and names the command that would show them:

```
│ Modules   needs root: run sudo distrofetch                          │
```

Run it privileged and that line becomes the modules themselves (shown here against the
test fixtures, since the author's laptop has two soldered sticks and less to say):

```console
# distrofetch
                ┌─ MEMORY ───────────────────────────────────────────────────────────────────────────────────────────────────────┐
                │ RAM       6.6 GiB / 15.2 GiB                                                                                   │
                │ Swap      0.4 GiB / 7.9 GiB                                                                                    │
                │ DIMM 0: 16 GiB DDR5 SODIMM @ 5200 MT/s (rated 5600) - SK Hynix (HMCG78AGBSA095N)                               │
                │ DIMM_A1: 32 GiB DDR4 DIMM @ 3200 MT/s - Corsair (CMK32GX4M2)                                                   │
                │ DIMM_B1: 16 MiB DDR3 DIMM @ 1600 MT/s - Micron (MT8JTF)                                                        │
                │ DIMM 1: 8 GiB DDR5 SODIMM @ 5200 MT/s (rated 5600)                                                             │
                │ Slots     4 of 6 populated                                                                                     │
```

**distrofetch never asks for privilege and never needs it.** Everything else works
unprivileged; `sudo distrofetch` just fills in that one panel. The module *serial number*
is never read at all — it is a durable hardware identifier, and this output exists to be
screenshotted.

## Logos

Roughly twenty distributions have their own art, and a derivative borrows its parent's
via `ID_LIKE`. Anything unrecognised gets a generic penguin.

```bash
distrofetch --list-logos      # what is bundled
distrofetch --logo=gentoo     # wear someone else's
distrofetch --no-logo         # panels only
```

Logos are strictly ASCII, at most 20 rows and 30 columns. That is not aesthetic
conservatism: `${#}` counts bytes rather than characters outside a UTF-8 locale, and an
ASCII logo is the only kind whose column width is the same everywhere.

## Install

```bash
git clone https://github.com/fqazzazee/distrofetch.git
cd distrofetch
sudo make install            # /usr/local by default
```

Or from a release tarball:

```bash
curl -fsSLO https://github.com/fqazzazee/distrofetch/releases/latest/download/distrofetch-0.1.0.tar.gz
sha256sum -c distrofetch-0.1.0.tar.gz.sha256
tar xzf distrofetch-0.1.0.tar.gz
cd distrofetch-0.1.0 && sudo make install
```

Install somewhere else with `make install PREFIX=~/.local`, and remove it with
`sudo make uninstall`.

**Requires:** Bash 5.0+ and coreutils. Tested on Arch, Debian stable, and Fedora,
x86_64. Linux only — the probes read `/proc`, which macOS and the BSDs do not have.

## Use

```console
$ distrofetch
```

The report prints immediately. The animation is opt-in:

```console
$ distrofetch -d 2
```

That gives you two seconds of rain — columns of glyphs falling with a white leading
character and a tail that fades through five greens — after which the banner assembles a
row at a time and each value resolves out of the noise into the real thing.

The rain runs on the alternate screen buffer, so whatever was in your terminal is still
there when it finishes; the report then prints into your normal scrollback where it
stays. Ctrl-C mid-animation puts everything back.

`--no-art` gives you the bare lines, which is what you want if something is reading the
output:

```console
$ distrofetch --no-art --no-color
tesla@workstation
────────────────────────────────
OS:        Fedora Linux 44 (Workstation Edition)
Kernel:    Linux 7.1.5-201.fc44.x86_64
Arch:      x86_64
Uptime:    2d 7h 15m
Packages:  2809 (rpm)
Shell:     bash
CPU:       13th Gen Intel(R) Core(TM) i7-1360P (16)
Memory:    6.9 GiB / 15.2 GiB
```

Both the animation and color switch off automatically whenever stdout is not a terminal,
so piping and redirecting are safe by default — no escape sequences end up in your file.
When the consumer does understand ANSI, override it:

```bash
distrofetch --color=always | less -R
```

## Options

| Option | Default | Description |
|---|---|---|
| `--logo=NAME` | auto | Force a specific distro logo |
| `--no-logo` | | Dashboard without the logo column |
| `--no-art` | | Plain `Label: value` lines: no panels, no logo |
| `--list-logos` | | Print the bundled logo names and exit |
| `-d`, `--duration N` | `0` | Seconds of rain before the dashboard; `0` means none |
| `-n`, `--no-rain` | | Skip the animation — the default, kept for explicitness |
| `--color=WHEN` | `auto` | `always`, `never`, or `auto` (on for a terminal, off otherwise) |
| `-c`, `--no-color` | | Alias for `--color=never` |
| `-v`, `--version` | | Print the version and exit |
| `-h`, `--help` | | Print help and exit |

`--color` and `--logo` accept either form: `--logo=arch` or `--logo arch`.

Exit status is `0` on success and `2` on a usage error.

### Scripting against it

Use `--no-art`. It is one fact per line with no frame and no logo, and no part of the
dashboard leaks into it — the smoke tests assert that on all three tested distros.

```console
$ distrofetch --no-art --no-color
tesla@fadis-zenbook14
────────────────────────────────
OS:        Fedora Linux 44 (Workstation Edition)
Kernel:    Linux 7.1.5-201.fc44.x86_64
Arch:      x86_64
Uptime:    2d 19h 55m
Packages:  2809 (rpm)
Shell:     bash
Released:  unknown
Support:   supported until 2027-05-19 (289 days)
CPU:       13th Gen Intel(R) Core(TM) i7-1360P (16)
Cores:     12 cores / 16 threads
Clock:     0.7 GHz now, 5.0 GHz max
Cache:     48K L1d, 32K L1i, 1280K L2, 18432K L3
Memory:    6.6 GiB / 15.2 GiB
Swap:      0.4 GiB / 7.9 GiB
Machine:   ASUSTeK COMPUTER INC. Zenbook Flip UP3404VA_UP3404VA
Firmware:  UP3404VA.301 (2023-05-11)
```

Both the animation and color switch off automatically whenever stdout is not a terminal,
so piping and redirecting are safe by default. When the consumer does understand ANSI:

```bash
distrofetch --color=always | less -R
```

`--color=always` never turns the animation on. The rain positions the cursor and switches
screen buffers, so it needs a real terminal regardless of what color is set to.

Terminal width comes from `COLUMNS` if it is set, then `tput cols`, then 80. Export
`COLUMNS` if you are running under something that does not set it.

### The animation

Off by default, because the common case is a shell startup file where two seconds is a
long time to wait for your prompt:

```bash
distrofetch -d 2
```

Columns of glyphs fall with a white leading character and a tail fading through five
greens, on the alternate screen buffer — so whatever was in your terminal is still there
when it finishes. Ctrl-C puts everything back. Outside a UTF-8 locale the glyphs fall
back to ASCII, because Bash slices strings by byte there and half-width katakana would
come apart into mojibake.

## Development

```bash
make check-tools   # verify shellcheck, shfmt, and bats are installed
make lint          # shellcheck
make fmt-check     # shfmt, non-destructive
make test          # bats
make smoke         # run the real entry point against this machine
```

| Module | Holds |
|---|---|
| `lib/detect.sh` | Probes. One line each, `unknown` rather than failure |
| `lib/dmi.sh` | DMI text fields and the SMBIOS type-17 parser |
| `lib/hwdata.sh` | Lookups against the bundled reference tables |
| `lib/render.sh` | Palette, animation, panel engine, dashboard layout |

Detection is split from rendering so probes can be tested without a terminal.
`hwdata.sh` is a different kind of thing again: it answers what the machine *cannot* know
about itself — when a release shipped, when support ends, what a family/model pair is
called.

**The reference tables go stale.** `lib/data/*.tsv` each carry a `Data as of:` line and a
refresh source. Neither is consulted where a live source exists: `SUPPORT_END=` beats the
release table, and `/proc/cpuinfo` beats everything for what the CPU is. A row that cannot
be confirmed is omitted rather than guessed — a blank is a gap, a wrong end-of-support
date is a lie someone acts on.

The SMBIOS parser is tested against synthetic records in `tests/fixtures/dmi-entries`,
because the real tables are mode `0400` and one machine's memory proves very little
anyway. Regenerate them with `make fixtures` after editing the generator.

See [`SPEC.md`](SPEC.md) for the design and [`ROADMAP.md`](ROADMAP.md) for what is
planned.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Open an issue before starting anything large.
Reports from distros outside the tested three are especially useful.

## License

MIT — see [`LICENSE`](LICENSE).
