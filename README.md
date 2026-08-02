# distrofetch

A full-screen system dashboard for Linux — distribution support status, processor
lineage, memory modules, and firmware, beside your distro's logo in ASCII.

[![CI](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml)
[![Smoke test (distros)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml)

## What it does

Prints a dashboard of what a Linux machine actually is — the distribution and how long it
is supported for, the processor down to its microarchitecture and generation, the memory
modules with their speeds and manufacturers, the graphics and network adapters, the USB
and Thunderbolt controllers with their link rates, and the board and its firmware —
beside an ASCII logo of the running distro.

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
  / (_    _)_/  │ Uptime    2d 20h 53m                                 │ │ Released  unknown                                     │
 / /  |  |      │ Shell     bash                                       │ │ Support   supported until 2027-05-19 (289 days)       │
 \ \__/  |      │ Packages  2809 (rpm)                                 │ │                                                       │
  \(_____/      └──────────────────────────────────────────────────────┘ └───────────────────────────────────────────────────────┘
                ┌─ PROCESSOR ────────────────────────────────────────────────────────────────────────────────────────────────────┐
                │   _       _       _   Model      13th Gen Intel(R) Core(TM) i7-1360P (16)                                      │
                │  (_)_ __ | |_ ___| |  Vendor     Intel                                                                         │
                │  | | '_ \| __/ _ \ |  Generation 13th Gen Core, released 2022                                                  │
                │  | | | | | ||  __/ |  Currency   3 generations behind Core Ultra Series 2 (2024)                               │
                │  |_|_| |_|\__\___|_|  Micro-arch Raptor Lake, launched 2023, Intel 7                                           │
                │                       Signature  family 6, model 186, stepping 2, ucode 0x6134                                 │
                │                       Topology   12 cores / 16 threads                                                         │
                │                       Clock      0.9 GHz now, 5.0 GHz max                                                      │
                │                       Cache      48K L1d, 32K L1i, 1280K L2, 18432K L3                                         │
                │                       Features   AVX2, AES-NI, SHA-NI, VT-x                                                    │
                └────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ MEMORY ───────────────────────────────────────────────────────────────────────────────────────────────────────┐
                │ RAM       6.3 GiB / 15.2 GiB                                                                                   │
                │ Swap      0.4 GiB / 7.9 GiB                                                                                    │
                │ Modules   needs root: run sudo distrofetch                                                                     │
                └────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ GRAPHICS ─────────────────────────────────────────────────────────────────────────────────────────────────────┐
                │ GPU       Intel Raptor Lake-P [Iris Xe Graphics] (i915)                                                        │
                └────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ NETWORK ──────────────────────────────────────────────────────────────────────────────────────────────────────┐
                │ wlo1      Intel Raptor Lake PCH CNVi WiFi (iwlwifi) - up, Wi-Fi                                                │
                └────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ PERIPHERALS ──────────────────────────────────────────────────────────────────────────────────────────────────┐
                │ USB         fastest 20 Gbps; root ports are per controller, not sockets                                        │
                │   USB 2.0 (480 Mbps): 2 controllers, 13 root ports                                                             │
                │   USB 3.2 Gen 2x2 (20 Gbps): 1 controller, 3 root ports                                                        │
                │   USB 3.2 Gen 2 (10 Gbps): 1 controller, 4 root ports                                                          │
                │ Thunderbolt domain0: Thunderbolt 4 / USB4 (40 Gbps), INTEL Gen12                                               │
                │   security: user - connections need approval; IOMMU DMA protection on                                          │
                │ Thunderbolt domain1: Thunderbolt 4 / USB4 (40 Gbps), INTEL Gen12                                               │
                │   security: user - connections need approval; IOMMU DMA protection on                                          │
                └────────────────────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ MACHINE ──────────────────────────────────────────────────────────────────────────────────────────────────────┐
                │ Model     ASUSTeK COMPUTER INC. Zenbook Flip UP3404VA_UP3404VA                                                 │
                │ Board     ASUSTeK COMPUTER INC. UP3404VA                                                                       │
                │ Firmware  UP3404VA.301 (2023-05-11)                                                                            │
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
- **What your CPU actually is, and how old.** "13th Gen Intel Core i7-1360P" is a
  marketing string; `family 6, model 186` is Raptor Lake, launched 2023 on Intel 7. The
  same silicon ships under several names, so the lookup keys on the family/model pair.
- **How far behind the current generation you are** — `13th Gen Core, released 2022` and
  `3 generations behind Core Ultra Series 2 (2024)`, beside an Intel or AMD mark. The
  generation being compared against is named rather than just counted, because the count
  is only as current as the bundled table: naming the basis is what lets you notice the
  table has gone stale. Xeon and EPYC parts are reported as not sitting on the consumer
  ladder rather than being placed on one.

  Intel's 13th and 14th Gen desktop parts are the same silicon and share a family/model
  pair, so the brand string wins where it carries a generation marker — otherwise every
  14th Gen chip would report as a generation older than it is.
- **Real core counts.** Read from `/sys/devices/system/cpu/present` rather than by
  counting `/proc/cpuinfo` blocks, which lists only *online* CPUs — so on a laptop that
  parks cores, the naive count changes between runs. Offline cores are noted, not hidden.
- **Your memory modules**: size, type, form factor, rated *and* configured speed, and
  manufacturer. The gap between rated and configured is how you notice XMP is off.
- **Which graphics adapter is actually driving the panel.** A laptop with switchable
  graphics has two, and they are reported separately — the integrated one as `GPU`, the
  discrete one as `3D`, which is how the PCI class distinguishes them.
- **What your USB ports can actually do.** Controllers are grouped by link rate and
  named from the rate, because USB 3.2 Gen 1, Gen 2, and Gen 2x2 all report version
  `3.10` in sysfs and differ only in speed.
- **Whether you have Thunderbolt, of which generation, and under what security policy** —
  including whether IOMMU DMA protection is on, and any attached device's authorisation
  state. `security: none` means every device gets PCIe access the moment it is plugged
  in, so it is spelled out rather than printed bare.

Two things are deliberately *not* claimed. There is **no USB or Thunderbolt port count**:
root-hub port totals are per controller, and one USB-C socket is wired to a 2.0 root hub
and a 3.x one at the same time, so the sum is routinely double the number of holes in the
case. And the mapping from a Thunderbolt domain to a physical connector is board-specific
and not exposed by the kernel, so any number there would be a guess dressed as a
measurement.

Device names come from `pci.ids` where the `hwdata` package is installed, and from a
small bundled vendor table otherwise — minimal containers do not ship 1.6 MB of device
names, so the fallback is the normal case there, and degrades to `Intel [8086:a7a0]`
rather than to nothing.

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

No **MAC address** is ever read, for the same reason: it is a durable, globally unique
identifier for the machine, and this output exists to be screenshotted. The smoke tests
assert that every real interface's MAC is absent from the output on all three tested
distros.

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

`--no-logo` also removes the Intel/AMD mark from the processor panel — it is the switch
for all art, not just the distro column. That mark drops out on its own once the panel is
too narrow to hold both it and the values, because a legible fact beats a legible logo.

Logos are strictly ASCII, at most 20 rows and 30 columns (vendor marks: 10 and 24). That
is not aesthetic conservatism: `${#}` counts bytes rather than characters outside a UTF-8
locale, and an ASCII logo is the only kind whose column width is the same everywhere.

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
tesla@fadis-zenbook14
────────────────────────────────
OS:        Fedora Linux 44 (Workstation Edition)
Kernel:    Linux 7.1.5-201.fc44.x86_64
Arch:      x86_64
Uptime:    2d 20h 53m
Packages:  2809 (rpm)
Shell:     bash
Released:  unknown
Support:   supported until 2027-05-19 (289 days)
CPU:       13th Gen Intel(R) Core(TM) i7-1360P (16)
CPU gen:   13th Gen Core (2022), 3 behind Core Ultra Series 2
Cores:     12 cores / 16 threads
Clock:     0.8 GHz now, 5.0 GHz max
Cache:     48K L1d, 32K L1i, 1280K L2, 18432K L3
Memory:    6.3 GiB / 15.2 GiB
Swap:      0.4 GiB / 7.9 GiB
GPU:       Intel Raptor Lake-P [Iris Xe Graphics] (i915)
Network:   wlo1 Intel Raptor Lake PCH CNVi WiFi up
USB:       usb1 USB 2.0 480 Mbps 1 root ports; usb2 USB 3.2 Gen 2x2 20 Gbps 3 root ports; usb3 USB 2.0 480 Mbps 12 root ports; usb4 USB 3.2 Gen 2 10 Gbps 4 root ports
TBolt:     domain0 Thunderbolt 4 / USB4 (40 Gbps) security=user; domain1 Thunderbolt 4 / USB4 (40 Gbps) security=user
Machine:   ASUSTeK COMPUTER INC. Zenbook Flip UP3404VA_UP3404VA
Firmware:  UP3404VA.301 (2023-05-11)
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
| `lib/devices.sh` | Graphics, network, USB, and Thunderbolt enumeration |
| `lib/hwdata.sh` | Lookups against the bundled reference tables |
| `lib/render.sh` | Palette, animation, panel engine, dashboard layout |

Detection is split from rendering so probes can be tested without a terminal.
`hwdata.sh` is a different kind of thing again: it answers what the machine *cannot* know
about itself — when a release shipped, when support ends, what a family/model pair is
called.

**The reference tables go stale.** `lib/data/*.tsv` each carry a `Data as of:` line and a
refresh source. `cpu-generations.tsv` defines "latest" by its own highest ordinal, so
adding a generation is one line and every "N behind" recalculates — nothing hardcodes the
newest generation, and the failure mode of forgetting is an under-report that the named
comparison basis makes visible. Neither is consulted where a live source exists: `SUPPORT_END=` beats the
release table, and `/proc/cpuinfo` beats everything for what the CPU is. A row that cannot
be confirmed is omitted rather than guessed — a blank is a gap, a wrong end-of-support
date is a lie someone acts on.

`devices.sh` deliberately breaks the one-line-per-probe rule: it prints one line per
device, **or nothing**, because a container with no GPU and a machine whose GPU could not
be named are different answers and `unknown` cannot express the first.

The SMBIOS parser is tested against synthetic records in `tests/fixtures/dmi-entries`,
and device enumeration against synthetic sysfs trees in `tests/fixtures/sysfs` — the real
SMBIOS tables are mode `0400`, and no machine available here has switchable graphics, a
down ethernet link, an unbound driver, a USB4 bus, and an unauthorised Thunderbolt device
at once. Regenerate both with `make fixtures`.

See [`SPEC.md`](SPEC.md) for the design and [`ROADMAP.md`](ROADMAP.md) for what is
planned.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Open an issue before starting anything large.
Reports from distros outside the tested three are especially useful.

## License

MIT — see [`LICENSE`](LICENSE).
