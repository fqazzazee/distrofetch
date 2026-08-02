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
13a. Report the consumer generation the part belongs to, the year that generation
    launched, and how many generations behind the newest known generation it is. Name
    the generation being compared against, never only the count — the count is only as
    current as the bundled table, and naming the basis is what lets a reader notice the
    table is stale.
13b. Take the generation from the brand string where it carries one (`13th Gen`,
    `Core Ultra`), and from the microarchitecture table otherwise. The string wins:
    Intel's 13th and 14th Gen desktop parts are the same silicon and share a
    family/model pair, so the table alone reports every 14th Gen part as a generation
    older than it is.
13c. Report a part that is not on the consumer ladder — Xeon Scalable, EPYC — as such,
    rather than placing it on a ladder it does not sit on.
13d. Show a vendor mark in the processor panel, dropping it when the panel is too
    narrow to hold both the mark and the values. A legible fact beats a legible logo.
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

### Attached devices

18. Report every display-class PCI device, distinguishing VGA, 3D, and display
    controllers. A laptop with switchable graphics has two, and which one drives the
    panel is the difference between them.
19. Report every network interface backed by a hardware device, with its model, driver,
    link state, and negotiated rate where one exists. Identify virtual interfaces by the
    absence of a device link, never by a list of names — the list would need extending
    for every new kind of virtual interface.
20. **Never read a MAC address.** It is a durable, globally unique identifier for the
    machine, and this output is designed to be posted.
21. Report USB host controllers grouped by link speed, named from the speed rather than
    the `version` attribute: USB 3.2 Gen 1, Gen 2, and Gen 2x2 all report version 3.10
    and differ only in rate.
22. State that root-hub port counts are per controller and not sockets on the chassis. A
    single USB-C connector is wired to a 2.0 root hub and a 3.x one at once, so the
    total is routinely double the number of holes in the case.
23. Report Thunderbolt and USB4 domains with generation, security policy, and whether
    IOMMU DMA protection is on; and list attached devices with their authorisation
    state. Never report a Thunderbolt *port count* — the mapping from domain to physical
    connector is board-specific and not exposed by the kernel, so any number would be a
    guess dressed as a measurement.
24. Spell out what a Thunderbolt security level means. `none` reads as "no security
    feature present" when it actually means every device gets PCIe access on connect.
25. Distinguish "no such hardware" from "hardware present but unidentifiable". A
    container with no display adapter and a machine whose GPU could not be named are
    different answers, and `unknown` cannot express the first.
26. Resolve PCI vendor and device names from `pci.ids` where it is installed, and from a
    bundled vendor table otherwise, degrading to `[vendor:device]` hex. The database is
    absent from minimal containers, which is where the smoke matrix runs.

### Storage

27. Report every whole disk with capacity, whether it is solid state, its model, and —
    for NVMe — the PCIe generation and width it negotiated. Skip loop, ram, zram,
    device-mapper, and optical devices: they are either not hardware or have no capacity
    worth reporting, and a machine with twenty snap mounts would otherwise print twenty
    loop devices.
28. Report both the negotiated and the maximum PCIe link when they differ. A Gen4 drive
    in a Gen3 slot runs at half its throughput and nothing else on the system says so.
29. Report capacity in decimal units. A "1 TB" drive is 1000 GB to its manufacturer and
    931 GiB to the kernel, and the number that matches the label is the useful one.
30. **Never read a drive serial number**, for the same reason as a DIMM serial.

### Link detail

31. Report a wireless interface's Wi-Fi generation where the device name carries one,
    and say why there is none where it does not. Neither sysfs nor an unprivileged
    ethtool exposes this — `ETHTOOL_GLINKSETTINGS` returns `EPERM` to an ordinary user —
    so the device name from `pci.ids` is the only source, and it is a label rather than
    a measurement.
32. Identify Intel CNVi parts as unanswerable rather than guessing. CNVi splits the
    wireless MAC, which lives in the PCH and is what the PCI ID names, from the RF
    module that actually sets the generation; two machines reporting the same PCI ID can
    be Wi-Fi 6 and Wi-Fi 6E.
33. Report a wired interface's rated speed where its name states one, alongside the
    negotiated speed. The gap between them is a cable or a switch port, and neither
    number identifies that alone.

### Fitting the terminal

34. Clear the screen before drawing, on a terminal only, and only once the dashboard is
    ready — a failed run leaves the screen it found. `--no-clear` disables it.
35. Measure the terminal and drop detail until the dashboard fits its height. Attempts
    run in strictly decreasing order of information: full, compact, minimal, then the
    same three with panels paired two across, then without the logo. The result is
    always the most complete layout that fits.
36. Drop a panel whose every row is a "none present" answer at the tightest densities. A
    panel that costs three lines to say nothing is worse than its absence, and on a
    container there are three of them.
37. Never claim to fit what cannot fit. Below roughly 26 lines the dashboard overflows,
    and that is preferable to hiding the machine's identity.

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
| `lib/devices.sh` | Graphics, network, USB, and Thunderbolt enumeration |
| `lib/hwdata.sh` | Lookups against the bundled reference tables |
| `lib/render.sh` | Palette, glyph animation, panel engine, dashboard layout |
| `lib/data/*.tsv` | Distribution release/support data; CPU microarchitecture table |
| `lib/logos/*.txt` | One ASCII logo per distribution, plus a generic fallback |
| `Makefile` | lint / fmt / test / dist / install — the same targets CI runs |
| `tests/*.bats` | CLI contract, layout alignment, SMBIOS parsing, table lookups |
| `tests/fixtures/` | Synthetic SMBIOS records, DMI id files, and sysfs trees |

`devices.sh` is separate from `detect.sh` because it breaks that module's contract
deliberately: a probe in `detect.sh` answers one question with one line, while a function
in `devices.sh` answers "what is attached" and prints one line per device **or nothing at
all**. Nothing is the answer for a container with no GPU, and `unknown` cannot say it.

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
- **No stable hardware identifier is ever read.** The DIMM serial at SMBIOS offset
  0x18, PCI serial numbers, and interface MAC addresses are all skipped rather than read
  and discarded, so no future change to the formatting can leak one. Individually these
  are mundane; together they are a fingerprint that survives a reinstall, and the output
  exists to be screenshotted.
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
| `lib/data/cpu-generations.tsv` | Intel ARK, AMD product pages | Every new generation |
| `lib/data/pci-vendors.tsv` | <https://pci-ids.ucw.cz> | Rarely — PCI vendor IDs are permanent |

`cpu-generations.tsv` defines "latest" by its own highest ordinal, so adding a
generation is one line and every "N behind" recalculates. Nothing hardcodes the newest
generation. The failure mode of forgetting is therefore an *under*-report, never an
over-report — and because the dashboard names the generation it compares against, a
stale basis is visible in the output rather than silent.

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
- **A per-part CPU database.** The tables key on microarchitecture and generation, not
  on individual SKUs. Knowing that a chip is Raptor Lake, 13th Gen, 2022 is the useful
  fact; carrying TDP, boost bins, and PCIe lane counts for every part ever sold is a
  different project with a different maintenance burden.
- **A configuration file.** Flags only. If a fact is worth showing, it is worth showing
  by default.
- **Disk, theme, icon, and WM/DE detection.** *Superseded 2026-08-02 for GPU only —
  graphics, network, USB, and Thunderbolt were previously non-goals under this heading.*
  The reasoning stands for what remains: each is a pile of vendor-specific special cases.
  What made graphics and the buses tractable is that everything reported about them comes
  from sysfs with a fixed shape — a PCI class code, a link speed in Mbit/s, a generation
  integer — and none of it needs a per-vendor branch. Anything requiring per-vendor code
  to *read* is still out.
- **Per-region font sizes.** Terminals have no portable mechanism for this. `DECDWL`
  and `DECDHL` (double-width and double-height lines) exist in the VT100 repertoire but
  are unimplemented in kitty, alacritty, and most modern emulators, and where they do
  work they halve the columns on that line and break every alignment guarantee above.
  Visual hierarchy comes from the palette and from dropping detail, not from type size.
- **Filesystem usage, partitions, and mount points.** Storage reporting stops at the
  device. What is *on* a disk is a different question from what the disk is, needs
  `statvfs` per mount, and changes minute to minute.
- **SMART attributes, drive health, and temperature.** These need privileged ioctls and
  a per-vendor attribute table, which is the line this project does not cross.
- **VRAM, GPU clocks, temperatures, and utilisation.** These are where graphics
  reporting turns into a per-driver project: amdgpu exposes them in sysfs, i915 does not,
  and nvidia needs a proprietary tool. The adapter's identity needs none of that.
- **IP addresses, routes, and DNS.** Network reporting here stops at the hardware. What
  is configured on an interface is both larger in scope and more sensitive than what the
  interface is.
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
- [ ] No memory module serial number and no MAC address appears in any output
- [ ] Switchable graphics report both adapters, labelled; a container with none reports
      `none present` rather than `unknown`
- [ ] A down ethernet link reports no rate rather than `-1`
- [ ] USB buses group by speed class and the output states that root ports are not
      sockets
- [ ] Thunderbolt domains report generation, security policy, and DMA protection, and
      no port count is claimed
- [ ] Device names resolve from `pci.ids` where present and degrade to the bundled
      vendor table and then to hex where it is not
- [ ] Every whole disk is reported with capacity and kind; loop, zram, and dm devices
      are not
- [ ] An NVMe drive negotiated below its maximum reports both figures
- [ ] No drive serial appears in any output
- [ ] A Wi-Fi device whose name carries a generation reports it; a CNVi part explains
      why it cannot
- [ ] A 2.5 GbE NIC is not reported as 5 GbE
- [ ] The dashboard fits at 60, 40, and 30 lines, and the screen-clear escape never
      reaches a pipe
- [ ] An unprivileged run states why module detail is unavailable rather than printing
      `unknown`
- [ ] A rolling release reports no end of life; an expired release reports its overrun;
      an unknown release reports `unknown`
- [ ] Every bundled logo is pure ASCII, at most 20 rows and 30 columns; every vendor
      mark at most 10 rows and 24 columns
- [ ] The processor panel names its generation, its year, and its distance from the
      newest known generation, and names that generation
- [ ] A 14th Gen part reports as 14th Gen despite sharing a family/model with 13th Gen
- [ ] A Xeon or EPYC part reports as off-ladder rather than being placed on it
- [ ] The vendor mark drops out before any processor value clips
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
