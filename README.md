# distrofetch

Matrix-styled system information for Linux — the falling-glyph effect settles into a
report of what the machine actually is.

[![CI](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/ci.yaml)
[![Smoke test (distros)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml/badge.svg)](https://github.com/fqazzazee/distrofetch/actions/workflows/smoke-distros.yaml)

## What it does

Prints your OS, kernel, architecture, uptime, package count, shell, CPU, and memory,
introduced by a short rain of katakana glyphs. It reads `/etc/os-release`, `/proc`, and
your package manager's database — nothing else. No network calls, no writes, no root.

It is a single Bash script with no runtime dependencies beyond coreutils, which is the
point: it runs on the minimal container or the freshly-installed box where you have not
yet installed anything, and it is short enough to read before you run it.

It does not try to be neofetch. There is no ASCII distro logo, no image protocol, no
configuration file, and no plugin system.

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

The glyphs fall for two seconds, then:

```console
$ distrofetch --no-color
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

The animation is skipped automatically whenever stdout is not a terminal, so piping and
redirecting are always safe — no escape sequences end up in your file.

## Options

| Option | Default | Description |
|---|---|---|
| `-n`, `--no-rain` | off | Skip the animation, print the report only |
| `-c`, `--no-color` | off | Disable ANSI color; implies `--no-rain` |
| `-d`, `--duration N` | `2` | Seconds of rain before the report settles |
| `-v`, `--version` | | Print the version and exit |
| `-h`, `--help` | | Print help and exit |

Exit status is `0` on success and `2` on a usage error.

## Development

```bash
make check-tools   # verify shellcheck, shfmt, and bats are installed
make lint          # shellcheck
make fmt-check     # shfmt, non-destructive
make test          # bats
make smoke         # run the real entry point against this machine
```

`lib/detect.sh` holds the probes and `lib/render.sh` holds the output layer; the split
exists so detection can be tested without a terminal. Every probe prints one line and
returns `unknown` rather than failing, which is what keeps the renderer simple.

See [`SPEC.md`](SPEC.md) for the design and [`ROADMAP.md`](ROADMAP.md) for what is
planned.

## Contributing

See [`CONTRIBUTING.md`](CONTRIBUTING.md). Open an issue before starting anything large.
Reports from distros outside the tested three are especially useful.

## License

MIT — see [`LICENSE`](LICENSE).
