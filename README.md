# distrofetch

A full-screen system dashboard for Linux — distribution support status, processor
lineage, memory, disks, graphics, network, and firmware, beside your distro's logo in
ASCII.

[![CI](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml)
[![Smoke test (distros)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml)
[![Security](https://github.com/fqazzazee/distrofetch/actions/workflows/security.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/security.yaml)

```console
$ distrofetch
distrofetch 0.1.0                                                                              tesla@fadis-zenbook14
────────────────────────────────────────────────────────────────────────────────────────────────────────────────────

       _____    ┌─ SYSTEM ─────────────────────────────────────────────────────────────────────────────────────────┐
      /   __)\  │ OS        Fedora Linux 44 (Workstation Edition)                                                  │
      |  /  \ \ │ Kernel    Linux 7.1.5-201.fc44.x86_64                                                            │
   ___|  |__/ / │ Arch      x86_64                                                                                 │
  / (_    _)_/  │ Uptime    3d 2h 35m                                                                              │
 / /  |  |      │ Shell     bash                                                                                   │
 \ \__/  |      │ Packages  2812 (rpm)                                                                             │
  \(_____/      └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ DISTRIBUTION ───────────────────────────────────────────────────────────────────────────────────┐
                │ ID        fedora                                                                                 │
                │ Version   44                                                                                     │
                │ Codename  none                                                                                   │
                │ Released  unknown                                                                                │
                │ Support   supported until 2027-05-19 (289 days)                                                  │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ PROCESSOR ──────────────────────────────────────────────────────────────────────────────────────┐
                │   _       _       _   Model      13th Gen Intel(R) Core(TM) i7-1360P (16)                        │
                │  (_)_ __ | |_ ___| |  Vendor     Intel                                                           │
                │  | | '_ \| __/ _ \ |  Generation 13th Gen Core, released 2022                                    │
                │  | | | | | ||  __/ |  Currency   4 generations behind Core Ultra Series 3 (2026)                 │
                │  |_|_| |_|\__\___|_|  Micro-arch Raptor Lake, launched 2023, Intel 7                             │
                │                       Signature  family 6, model 186, stepping 2, ucode 0x6134                   │
                │                       Topology   12 cores / 16 threads (14 online)                               │
                │                       Clock      0.4 GHz now, 5.0 GHz max                                        │
                │                       Cache      48K L1d, 32K L1i, 1280K L2, 18432K L3                           │
                │                       Features   AVX2, AES-NI, SHA-NI, VT-x                                      │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ MEMORY ─────────────────────────────────────────────────────────────────────────────────────────┐
                │ RAM       6.0 GiB / 15.2 GiB                                                                     │
                │ Channels  4 channels across 2 controllers, 8 slots                                               │
                │ Swap      0.6 GiB / 7.9 GiB                                                                      │
                │ Modules   needs root: run sudo distrofetch                                                       │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ STORAGE ────────────────────────────────────────────────────────────────────────────────────────┐
                │ nvme0n1   1.0 TB NVMe WD PC SN560 SDDPNQE-1T00-1102 - PCIe Gen 4 x4 (4 lanes)                    │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ GRAPHICS ───────────────────────────────────────────────────────────────────────────────────────┐
                │ GPU       Intel Raptor Lake-P [Iris Xe Graphics] (i915)                                          │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ NETWORK ────────────────────────────────────────────────────────────────────────────────────────┐
                │ wlo1      Intel Raptor Lake PCH CNVi WiFi (iwlwifi) - up, CNVi, generation set by the RF module  │
                │           not the PCI ID                                                                         │
                │ Virtual   br-df56d9872e83 (bridge, down) docker0 (bridge, down) lo (loopback, unknown)           │
                │           tailscale0 (tunnel, unknown)                                                           │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ PERIPHERALS ────────────────────────────────────────────────────────────────────────────────────┐
                │ USB         fastest 20 Gbps; root ports are per controller, not sockets                          │
                │   USB 2.0 (480 Mbps): 2 controllers, 13 root ports                                               │
                │   USB 3.2 Gen 2x2 (20 Gbps): 1 controller, 3 root ports                                          │
                │   USB 3.2 Gen 2 (10 Gbps): 1 controller, 4 root ports                                            │
                │ Thunderbolt domain0: Thunderbolt 4 / USB4 (40 Gbps), INTEL Gen12                                 │
                │   security: user - connections need approval; IOMMU DMA protection on                            │
                │ Thunderbolt domain1: Thunderbolt 4 / USB4 (40 Gbps), INTEL Gen12                                 │
                │   security: user - connections need approval; IOMMU DMA protection on                            │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
                ┌─ MACHINE ────────────────────────────────────────────────────────────────────────────────────────┐
                │ Model     ASUSTeK COMPUTER INC. Zenbook Flip UP3404VA_UP3404VA                                   │
                │ Board     ASUSTeK COMPUTER INC. UP3404VA                                                         │
                │ Firmware  UP3404VA.301 (2023-05-11)                                                              │
                └──────────────────────────────────────────────────────────────────────────────────────────────────┘
```

Bash and coreutils, no runtime dependencies. It reads `/etc/os-release`, `/proc`, `/sys`,
and your package manager's database — no network calls, no writes, no root.

## Install

```bash
git clone https://github.com/fqazzazee/distrofetch.git
cd distrofetch && sudo make install      # /usr/local by default
```

`make install PREFIX=~/.local` to put it elsewhere, `sudo make uninstall` to remove it.
Release tarballs carry a `.sha256` — check it before extracting.

**Requires** Bash 5.0+ and coreutils. Linux only; the probes read `/proc`.

## What it tells you that `uname -a` cannot

- **Whether your distribution is still supported.** From `SUPPORT_END=` in
  `/etc/os-release` where the distro ships it, and a bundled table otherwise. Expired
  renders red, within 90 days amber.
- **What your CPU actually is, and how old.** `family 6, model 186` is Raptor Lake,
  2023 — the marketing name doesn't say. Plus how many generations behind the current
  one you are, naming what it compared against.
- **What your NVMe drive is running at.** `PCIe Gen 4 x4 (4 lanes)`, and when it has
  negotiated down, `PCIe Gen 3 x2 (2 lanes), capable of Gen 4 x4`.
- **How many memory channels**, from EDAC — single versus dual channel is invisible
  everywhere else.
- **Your memory modules**: size, type, rated *and* configured speed, manufacturer. The
  gap between the two speeds is how you notice XMP is off.
- **Which Wi-Fi generation** your card is. For Intel CNVi parts it says the generation
  *cannot* be known from the PCI ID rather than guessing — the radio is a separate
  module from the chip the ID names.
- **Every network interface**, including ones with nothing plugged in.
- **Real core counts**, from `/sys/devices/system/cpu/present` rather than by counting
  `/proc/cpuinfo` blocks, which lists only *online* CPUs.

## Privacy

This output is designed to be screenshotted, so **no stable hardware identifier is ever
read**: not DIMM or drive serials, not MAC addresses. Those paths are never opened, so no
change to the formatting can leak one. Tests assert it, on every supported distro.

Memory module detail lives in SMBIOS tables the kernel exposes at mode `0400`. An
unprivileged run says so and names the command that would show them; `sudo distrofetch`
fills in that one panel. **distrofetch never asks for privilege and never needs it.**

## Options

| Option | Default | Description |
|---|---|---|
| `--no-art` | | Plain `Label: value` lines: no panels, no logo |
| `--no-clear` | | Draw in place instead of clearing the screen |
| `--fit` | | Drop detail until it fits the terminal height |
| `--theme=NAME` | `vivid` | `vivid` or `matrix` |
| `--logo=NAME` | auto | Force a distro logo; `--list-logos` prints them |
| `--no-logo` | | No logo art anywhere |
| `-d`, `--duration N` | `0` | Seconds of matrix rain first; `0` means none |
| `--color=WHEN` | `auto` | `always`, `never`, or `auto` |
| `-q`, `--quiet` | | No progress output while probing |
| `-v`, `--version`, `-h`, `--help` | | |

Exit status is `0` on success and `2` on a usage error.

**Nothing is ever truncated.** Panels size to their content and long values wrap; an
ellipsis in this output would mean a fact was thrown away. That means it can be taller
than your terminal — `--fit` trades detail for height if you would rather it fit.

Animation and colour switch off automatically when stdout is not a terminal, so piping
is safe by default.

## Scripting against it

Use `--no-art`: one fact per line, no frame, no logo. The smoke tests assert on all three
tested distros that no part of the dashboard leaks into it.

```console
$ distrofetch --no-art --no-color
tesla@fadis-zenbook14
────────────────────────────────
OS:        Fedora Linux 44 (Workstation Edition)
Kernel:    Linux 7.1.5-201.fc44.x86_64
Arch:      x86_64
Uptime:    3d 2h 35m
Packages:  2812 (rpm)
Shell:     bash
Released:  unknown
Support:   supported until 2027-05-19 (289 days)
CPU:       13th Gen Intel(R) Core(TM) i7-1360P (15)
CPU gen:   13th Gen Core (2022), 4 behind Core Ultra Series 3
Cores:     12 cores / 16 threads
Clock:     0.4 GHz now, 5.0 GHz max
Cache:     48K L1d, 32K L1i, 1280K L2, 18432K L3
Memory:    6.0 GiB / 15.2 GiB
Channels:  4 channels, 2 controllers, 8 slots
Swap:      0.6 GiB / 7.9 GiB
Disks:     nvme0n1 1.0 TB NVMe WD PC SN560 SDDPNQE-1T00-1102 PCIe Gen 4 x4 (4 lanes)
GPU:       Intel Raptor Lake-P [Iris Xe Graphics] (i915)
Network:   br-df56d9872e83 (bridge, down); docker0 (bridge, down); lo (loopback, unknown); tailscale0 (tunnel, unknown); wlo1 Intel Raptor Lake PCH CNVi WiFi up
USB:       usb1 USB 2.0 480 Mbps 1 root ports; usb2 USB 3.2 Gen 2x2 20 Gbps 3 root ports; usb3 USB 2.0 480 Mbps 12 root ports; usb4 USB 3.2 Gen 2 10 Gbps 4 root ports
TBolt:     domain0 Thunderbolt 4 / USB4 (40 Gbps) security=user; domain1 Thunderbolt 4 / USB4 (40 Gbps) security=user
Machine:   ASUSTeK COMPUTER INC. Zenbook Flip UP3404VA_UP3404VA
Firmware:  UP3404VA.301 (2023-05-11)
```

## Development

```bash
make check-tools   # verify shellcheck, shfmt, and bats are installed
make lint test     # shellcheck; bats
make fmt-check     # shfmt, non-destructive
make check-data    # compare the CPU table against Intel's and AMD's sites (needs network)
make fixtures      # regenerate the SMBIOS and sysfs test fixtures
```

| Module | Holds |
|---|---|
| `lib/detect.sh` | Probes. One line each, `unknown` rather than failure |
| `lib/devices.sh` | Graphics, network, USB, Thunderbolt, storage enumeration |
| `lib/dmi.sh` | DMI fields and the SMBIOS type-17 parser |
| `lib/hwdata.sh` | Lookups against the bundled reference tables |
| `lib/render.sh` | Palette, animation, panel engine, layout |

Detection is split from rendering so probes can be tested without a terminal. The tables
in `lib/data/` go stale by nature: a live source always beats them, and a miss prints
`unknown` rather than a guess.

Hardware paths are tested against synthetic fixtures in `tests/fixtures/`, because the
real SMBIOS tables are root-only and no machine here has switchable graphics, a degraded
PCIe link, and an unauthorised Thunderbolt device at once.

See [`SPEC.md`](SPEC.md) for the design and the reasoning, [`ROADMAP.md`](ROADMAP.md) for
what is planned, and [`docs/DECISIONS.md`](docs/DECISIONS.md) for why things are the way
they are.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Open an issue before starting anything large.
Reports from distros outside the tested three are especially useful — as is a
`sudo distrofetch` from a machine with more than one memory module.

## License

MIT — see [`LICENSE`](LICENSE).
