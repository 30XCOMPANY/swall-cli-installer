# Swall Installer

Hosts the one-line Swall CLI installer at **[install.swall.app](https://install.swall.app)**.

## Install (macOS / Linux)

```bash
curl -fsSL https://install.swall.app | sh
```

## Install (Windows)

```powershell
irm https://install.swall.app/ps1 | iex
```

## What this repo contains

- `install.sh` — POSIX installer. Detects OS/arch, pulls the latest
  CLI binary from `github.com/30xcompany/swall-releases`, and drops
  `swall` on your PATH.
- `install.ps1` — Windows PowerShell installer. Same behaviour, with
  SHA-256 checksum verification and a user-level PATH update.
- `_redirects` / `_headers` — Cloudflare Pages config so
  `install.swall.app` serves `install.sh` at the root and
  `install.swall.app/ps1` serves `install.ps1`.

## Release flow

1. Swall's main (private) repo tags a release via `.github/workflows/release.yml`.
2. GoReleaser uploads platform binaries to
   [`30xcompany/swall-releases`](https://github.com/30xcompany/swall-releases)
   (public).
3. `install.sh` / `install.ps1` resolve `releases/latest` on the
   public mirror, download the matching `tar.gz` / `zip`, verify, and
   install.

## Why three repos?

- **`30xcompany/swall`** — private. Business code.
- **`30xcompany/swall-releases`** — public. Binary artifacts only.
  Keeps the installer working without any GitHub auth, even though
  the source is closed.
- **`30xcompany/swall-cli-installer`** — public. This repo.
  Hosted on Cloudflare Pages at `install.swall.app`. Static files.

Each repo has one job. The installer never needs a token.

## Updating the scripts

These scripts are mirrored from the main repo's `scripts/install.sh`
and `scripts/install.ps1`. Source of truth lives there — we just
publish a copy here. A future GitHub Action will automate the mirror.

## License

Installer scripts: MIT (same as Homebrew formula / CLI license).
