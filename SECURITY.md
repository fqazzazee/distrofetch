# Security policy — distrofetch

## Supported versions

Only the latest release gets security fixes.

| Version | Supported |
|---|---|
| latest | yes |
| older | no |

## Reporting a vulnerability

Do not open a public issue.

Use [private vulnerability reporting](https://github.com/fqazzazee/distrofetch/security/advisories/new),
or email fadi.qazzazee@gmail.com with the details and, if you have one, a proof of
concept.

Expect an acknowledgment within 72 hours and an assessment within a week. If a fix is
warranted, you will get the timeline and credit in the release notes unless you would
rather not be named.

## Scope

**In scope:** the code in this repository, its default configuration, and its release
artifacts.

Given what this tool does, these are the categories worth reporting:

- **Command injection through a probe.** Anything read from `/proc`, `/etc/os-release`,
  or a package manager reaching a shell as code rather than data.
- **Privilege escalation via `make install`.** The install target writes to a
  user-chosen PREFIX; a path that lets an unprivileged user influence what lands in a
  root-owned location is a real finding.
- **Release artifact integrity.** A gap between what the tarball contains and what the
  checksum covers, or a way to make the release workflow publish something other than
  the tagged tree.
- **Terminal escape injection.** A hostname, distro name, or CPU model containing
  control sequences that reach the terminal unfiltered — the values come from the local
  system, but a container image or a VM template is not always locally controlled.

**Out of scope:** the information the tool prints. Disclosing your kernel version and
package count to whoever can already run commands as you is not a vulnerability — though
it is a good reason to look at a screenshot before posting it.

Also out of scope: vulnerabilities in dependencies without a working exploit path through
this project (there are no runtime dependencies beyond coreutils), and anything that
requires an attacker to already have the privileges the issue would grant.

## Design constraints that back this up

distrofetch runs unprivileged, reads only, and makes no network calls. Any change that
breaks one of those three is a security change and gets reviewed as one — see the
security section of [`SPEC.md`](SPEC.md).
