#!/usr/bin/env bash
# Swall installer — installs the CLI and optionally provisions a self-host server.
#
# Install / upgrade CLI only:
#   curl -fsSL https://install.swall.app | sh
#
# Install CLI + provision self-host server:
#   curl -fsSL https://install.swall.app | sh -s -- --with-server
#
# (Bash-preferring variant, same outcome, explicit interpreter:)
#   curl -fsSL https://install.swall.app | bash
#
# After installation, run `swall setup` to configure your environment.
#
set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Main product repo — private. Only used by --with-server to clone the
# docker-compose source for self-hosting. Regular CLI installs never touch it.
REPO_URL="https://github.com/30xcompany/swall.git"

# Public binary mirror — Swall CLI releases are published here so the curl
# installer works without any GitHub auth, even though the source repo is
# private.
RELEASES_REPO="30xcompany/swall-releases"
RELEASES_WEB_URL="https://github.com/${RELEASES_REPO}"
INSTALL_DIR="${SWALL_INSTALL_DIR:-$HOME/.swall/server}"
BREW_PACKAGE="30xcompany/tap/swall"

# Colors (disabled when not a terminal)
if [ -t 1 ] || [ -t 2 ]; then
  BOLD='\033[1m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  RED='\033[0;31m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { printf "${BOLD}${CYAN}==> %s${RESET}\n" "$*"; }
ok()    { printf "${BOLD}${GREEN}✓ %s${RESET}\n" "$*"; }
warn()  { printf "${BOLD}${YELLOW}⚠ %s${RESET}\n" "$*" >&2; }
fail()  { printf "${BOLD}${RED}✗ %s${RESET}\n" "$*" >&2; exit 1; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

detect_os() {
  case "$(uname -s)" in
    Darwin) OS="darwin" ;;
    Linux)  OS="linux" ;;
    MINGW*|MSYS*|CYGWIN*)
            fail "This script does not support Windows. Use the PowerShell installer instead:
  irm https://install.swall.app/ps1 | iex" ;;
    *)      fail "Unsupported operating system: $(uname -s). Swall supports macOS, Linux, and Windows." ;;
  esac

  ARCH="$(uname -m)"
  case "$ARCH" in
    x86_64)  ARCH="amd64" ;;
    aarch64) ARCH="arm64" ;;
    arm64)   ARCH="arm64" ;;
    *)       fail "Unsupported architecture: $ARCH" ;;
  esac
}

# ---------------------------------------------------------------------------
# CLI Installation
# ---------------------------------------------------------------------------
install_cli_brew() {
  info "Installing Swall CLI via Homebrew..."
  if ! brew tap 30xcompany/tap 2>/dev/null; then
    fail "Failed to add Homebrew tap. Check your network connection."
  fi
  # brew install exits non-zero if already installed on older Homebrew versions
  if ! brew install "$BREW_PACKAGE" 2>/dev/null; then
    if brew list "$BREW_PACKAGE" >/dev/null 2>&1; then
      ok "Swall CLI already installed via Homebrew"
    else
      fail "Failed to install swall via Homebrew."
    fi
  else
    ok "Swall CLI installed via Homebrew"
  fi
}

install_cli_binary() {
  info "Installing Swall CLI from GitHub Releases..."

  # Get latest release tag from the public binary mirror
  local latest
  latest=$(curl -sI "$RELEASES_WEB_URL/releases/latest" 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n' || true)
  if [ -z "$latest" ]; then
    fail "Could not determine latest release. Check your network connection."
  fi

  local url="${RELEASES_WEB_URL}/releases/download/${latest}/swall_${OS}_${ARCH}.tar.gz"
  local tmp_dir
  tmp_dir=$(mktemp -d)

  info "Downloading $url ..."
  if ! curl -fsSL "$url" -o "$tmp_dir/swall.tar.gz"; then
    rm -rf "$tmp_dir"
    fail "Failed to download CLI binary."
  fi

  tar -xzf "$tmp_dir/swall.tar.gz" -C "$tmp_dir" swall

  # Try /usr/local/bin first, fall back to ~/.local/bin
  local bin_dir="/usr/local/bin"
  if [ -w "$bin_dir" ]; then
    mv "$tmp_dir/swall" "$bin_dir/swall"
  elif command_exists sudo; then
    sudo mv "$tmp_dir/swall" "$bin_dir/swall"
  else
    bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    mv "$tmp_dir/swall" "$bin_dir/swall"
    chmod +x "$bin_dir/swall"
    # Add to PATH if not already there
    if ! echo "$PATH" | tr ':' '\n' | grep -q "^$bin_dir$"; then
      export PATH="$bin_dir:$PATH"
      add_to_path "$bin_dir"
    fi
  fi

  rm -rf "$tmp_dir"
  ok "Swall CLI installed to $bin_dir/swall"
}

add_to_path() {
  local dir="$1"
  local line="export PATH=\"$dir:\$PATH\""
  for rc in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [ -f "$rc" ] && ! grep -qF "$dir" "$rc"; then
      printf '\n# Added by Swall installer\n%s\n' "$line" >> "$rc"
    fi
  done
}

get_latest_version() {
  # grep exits 1 when no match; use `|| true` to avoid triggering pipefail
  curl -sI "$RELEASES_WEB_URL/releases/latest" 2>/dev/null | grep -i '^location:' | sed 's/.*tag\///' | tr -d '\r\n' || true
}

upgrade_cli_brew() {
  info "Upgrading Swall CLI via Homebrew..."
  brew update 2>/dev/null || true
  if brew upgrade "$BREW_PACKAGE" 2>/dev/null; then
    ok "Swall CLI upgraded via Homebrew"
  else
    # brew upgrade exits non-zero if already up to date
    ok "Swall CLI is already the latest version"
  fi
}

install_cli() {
  if command_exists swall; then
    local current_ver
    # `swall version` outputs "swall v0.1.13 (commit: abc1234)" — extract just the version
    current_ver=$(swall version 2>/dev/null | awk '{print $2}' || echo "unknown")

    local latest_ver
    latest_ver=$(get_latest_version)

    # Normalize: strip leading 'v' for comparison
    local current_cmp="${current_ver#v}"
    local latest_cmp="${latest_ver#v}"

    if [ -z "$latest_ver" ] || [ "$current_cmp" = "$latest_cmp" ]; then
      ok "Swall CLI is up to date ($current_ver)"
      return 0
    fi

    info "Swall CLI $current_ver installed, latest is $latest_ver — upgrading..."
    if command_exists brew && brew list "$BREW_PACKAGE" >/dev/null 2>&1; then
      upgrade_cli_brew
    else
      install_cli_binary
    fi

    local new_ver
    new_ver=$(swall version 2>/dev/null | awk '{print $2}' || echo "unknown")
    ok "Swall CLI upgraded ($current_ver → $new_ver)"
    return 0
  fi

  if command_exists brew; then
    install_cli_brew
  else
    install_cli_binary
  fi

  # Verify
  if ! command_exists swall; then
    fail "CLI installed but 'swall' not found on PATH. You may need to restart your shell."
  fi
}

# ---------------------------------------------------------------------------
# Docker check
# ---------------------------------------------------------------------------
check_docker() {
  if ! command_exists docker; then
    printf "\n"
    fail "Docker is not installed. Swall self-hosting requires Docker and Docker Compose.

Install Docker:
  macOS:  https://docs.docker.com/desktop/install/mac-install/
  Linux:  https://docs.docker.com/engine/install/

After installing Docker, re-run this script with --with-server."
  fi

  if ! docker info >/dev/null 2>&1; then
    fail "Docker is installed but not running. Please start Docker and re-run this script."
  fi

  ok "Docker is available"
}

# ---------------------------------------------------------------------------
# Server setup (self-host / --with-server)
# ---------------------------------------------------------------------------
setup_server() {
  info "Setting up Swall server..."

  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Updating existing installation at $INSTALL_DIR..."
    cd "$INSTALL_DIR"
    git fetch origin main --depth 1 2>/dev/null || true
    git reset --hard origin/main 2>/dev/null || true
  else
    info "Cloning Swall repository..."
    if ! command_exists git; then
      fail "Git is not installed. Please install git and re-run."
    fi
    # Remove leftover directory from a previously interrupted clone
    if [ -d "$INSTALL_DIR" ]; then
      warn "Removing incomplete installation at $INSTALL_DIR..."
      rm -rf "$INSTALL_DIR"
    fi
    mkdir -p "$(dirname "$INSTALL_DIR")"
    if ! git clone --depth 1 "$REPO_URL" "$INSTALL_DIR" 2>/dev/null; then
      fail "Could not clone Swall server repository from $REPO_URL.
This repository is private — self-hosting requires access.
Options:
  • Request source access at hello@30x.company, then re-run with a
    GitHub PAT:  GIT_ASKPASS=... git credential helper set up, or
  • Use Swall Cloud (no server setup needed): re-run without --with-server
    and then \`swall setup\`."
    fi
    cd "$INSTALL_DIR"
  fi

  ok "Repository ready at $INSTALL_DIR"

  # Generate .env if needed
  if [ ! -f .env ]; then
    info "Creating .env with random JWT_SECRET..."
    cp .env.example .env
    local jwt
    jwt=$(openssl rand -hex 32)
    if [ "$(uname -s)" = "Darwin" ]; then
      sed -i '' "s/^JWT_SECRET=.*/JWT_SECRET=$jwt/" .env
    else
      sed -i "s/^JWT_SECRET=.*/JWT_SECRET=$jwt/" .env
    fi
    ok "Generated .env with random JWT_SECRET"
  else
    ok "Using existing .env"
  fi

  # Start Docker Compose
  info "Starting Swall services (this may take a few minutes on first run)..."
  docker compose -f docker-compose.selfhost.yml up -d --build

  # Wait for health check
  info "Waiting for backend to be ready..."
  local ready=false
  for i in $(seq 1 45); do
    if curl -sf http://localhost:8080/health >/dev/null 2>&1; then
      ready=true
      break
    fi
    sleep 2
  done

  if [ "$ready" = true ]; then
    ok "Swall server is running"
  else
    warn "Server is still starting. You can check logs with:"
    echo "  cd $INSTALL_DIR && docker compose -f docker-compose.selfhost.yml logs"
    echo ""
  fi
}


# ---------------------------------------------------------------------------
# Main: Default mode (install / upgrade CLI only)
# ---------------------------------------------------------------------------
run_default() {
  printf "\n"
  printf "${BOLD}  Swall — Installer${RESET}\n"
  printf "\n"

  detect_os
  install_cli

  printf "\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "${BOLD}${GREEN}  ✓ Swall CLI is ready!${RESET}\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "\n"
  printf "  ${BOLD}Next: configure your environment${RESET}\n"
  printf "\n"
  printf "     ${CYAN}swall setup${RESET}                # Connect to Swall Cloud (swall.app)\n"
  printf "     ${CYAN}swall setup self-host${RESET}       # Connect to a self-hosted server\n"
  printf "\n"
  printf "  ${BOLD}Self-hosting?${RESET} Install the server first:\n"
  printf "     curl -fsSL https://install.swall.app | sh -s -- --with-server\n"
  printf "\n"
}

# ---------------------------------------------------------------------------
# Main: With-server mode (provision self-host infrastructure + install CLI)
# ---------------------------------------------------------------------------
run_with_server() {
  printf "\n"
  printf "${BOLD}  Swall — Self-Host Installer${RESET}\n"
  printf "  Provisioning server infrastructure + installing CLI\n"
  printf "\n"

  detect_os
  check_docker
  setup_server
  install_cli

  printf "\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "${BOLD}${GREEN}  ✓ Swall server is running and CLI is ready!${RESET}\n"
  printf "${BOLD}${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
  printf "\n"
  printf "  ${BOLD}Frontend:${RESET}  http://localhost:3000\n"
  printf "  ${BOLD}Backend:${RESET}   http://localhost:8080\n"
  printf "  ${BOLD}Server at:${RESET} %s\n" "$INSTALL_DIR"
  printf "\n"
  printf "  ${BOLD}Next: configure your CLI to connect${RESET}\n"
  printf "\n"
  printf "     ${CYAN}swall setup self-host${RESET}   # Configure + authenticate + start daemon\n"
  printf "\n"
  printf "  ${BOLD}Login:${RESET} configure ${CYAN}RESEND_API_KEY${RESET} in .env for email codes,\n"
  printf "  or set ${CYAN}APP_ENV=development${RESET} in .env to enable the dev master code ${BOLD}888888${RESET}.\n"
  printf "\n"
  printf "  ${BOLD}To stop all services:${RESET}\n"
  printf "     curl -fsSL https://install.swall.app | sh -s -- --stop\n"
  printf "\n"
}

# ---------------------------------------------------------------------------
# Stop: shut down a self-hosted installation
# ---------------------------------------------------------------------------
run_stop() {
  printf "\n"
  info "Stopping Swall services..."

  if [ -d "$INSTALL_DIR" ]; then
    cd "$INSTALL_DIR"
    if [ -f docker-compose.selfhost.yml ]; then
      docker compose -f docker-compose.selfhost.yml down
      ok "Docker services stopped"
    else
      warn "No docker-compose.selfhost.yml found at $INSTALL_DIR"
    fi
  else
    warn "No Swall installation found at $INSTALL_DIR"
  fi

  if command_exists swall; then
    swall daemon stop 2>/dev/null && ok "Daemon stopped" || true
  fi

  printf "\n"
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
main() {
  local mode="default"

  while [ $# -gt 0 ]; do
    case "$1" in
      --with-server) mode="with-server" ;;
      --local)       mode="with-server" ;;  # backwards compat alias
      --stop)        mode="stop" ;;
      --help|-h)
        echo "Usage: install.sh [--with-server | --stop]"
        echo ""
        echo "  (default)       Install / upgrade the Swall CLI"
        echo "  --with-server   Install CLI + provision a self-host server (Docker)"
        echo "  --stop          Stop a self-hosted installation"
        echo ""
        echo "After installation, run 'swall setup' to configure your environment."
        exit 0
        ;;
      *) warn "Unknown option: $1" ;;
    esac
    shift
  done

  case "$mode" in
    default)     run_default ;;
    with-server) run_with_server ;;
    stop)        run_stop ;;
  esac
}

main "$@"
