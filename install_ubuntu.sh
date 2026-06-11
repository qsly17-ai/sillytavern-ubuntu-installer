#!/usr/bin/env bash

set -Eeuo pipefail

REPO_URL="${SILLYTAVERN_REPO_URL:-https://github.com/SillyTavern/SillyTavern.git}"
BRANCH="${SILLYTAVERN_BRANCH:-release}"
INSTALL_DIR="${SILLYTAVERN_DIR:-$HOME/SillyTavern}"
NODE_MAJOR_TARGET="${NODE_MAJOR_TARGET:-22}"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

trap 'echo -e "${RED}Error: command failed at line ${LINENO}.${NC}" >&2' ERR

info() {
    echo -e "${BLUE}$*${NC}"
}

ok() {
    echo -e "${GREEN}$*${NC}"
}

warn() {
    echo -e "${YELLOW}$*${NC}"
}

die() {
    echo -e "${RED}Error: $*${NC}" >&2
    exit 1
}

usage() {
    cat <<EOF
Ubuntu SillyTavern installer
凌宇和苏苏子制作OVO

Usage:
  bash install_ubuntu.sh             Open menu
  bash install_ubuntu.sh --one-click Run full install without opening menu
  bash install_ubuntu.sh --help      Show help

Environment overrides:
  SILLYTAVERN_DIR=/path/to/SillyTavern
  SILLYTAVERN_BRANCH=release
  SILLYTAVERN_REPO_URL=https://github.com/SillyTavern/SillyTavern.git
EOF
}

read_tty() {
    local prompt="$1"
    local var_name="$2"
    local value=""

    if [[ -r /dev/tty ]]; then
        read -r -p "$prompt" value < /dev/tty
    else
        read -r -p "$prompt" value
    fi

    printf -v "$var_name" '%s' "$value"
}

pause_menu() {
    local _
    if [[ -r /dev/tty ]]; then
        read -r -p "Press Enter to continue..." _ < /dev/tty || true
    fi
}

require_ubuntu() {
    [[ -r /etc/os-release ]] || die "Cannot detect OS. This script supports Ubuntu only."

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        die "This script supports Ubuntu only. Detected: ${PRETTY_NAME:-unknown}"
    fi
}

require_privilege_tool() {
    if [[ "${EUID}" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        die "sudo is required when running as a normal user."
    fi
}

as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

as_root_env() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        sudo -E "$@"
    fi
}

safe_install_dir() {
    [[ -n "$INSTALL_DIR" ]] || die "INSTALL_DIR is empty."
    [[ "$INSTALL_DIR" != "/" ]] || die "Refusing to use / as the install directory."
}

install_system_deps() {
    require_ubuntu
    require_privilege_tool

    info "Installing system dependencies: git curl ca-certificates"
    as_root apt-get update
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates

    command -v git >/dev/null 2>&1 || die "git is still unavailable after installation."
    command -v curl >/dev/null 2>&1 || die "curl is still unavailable after installation."

    ok "System dependencies are ready."
}

node_major_version() {
    local major="0"

    if command -v node >/dev/null 2>&1; then
        major="$(node -p "process.versions.node.split('.')[0]" 2>/dev/null || echo 0)"
    fi

    echo "$major"
}

install_node() {
    require_ubuntu
    require_privilege_tool

    local current_major
    current_major="$(node_major_version)"

    if [[ "$current_major" =~ ^[0-9]+$ ]] && [[ "$current_major" -ge 20 ]] && command -v npm >/dev/null 2>&1; then
        ok "Node.js is ready: $(node --version), npm $(npm --version)"
        return 0
    fi

    if command -v node >/dev/null 2>&1; then
        warn "Detected Node.js $(node --version), but SillyTavern requires Node.js >= 20."
    else
        warn "Node.js was not found."
    fi

    install_system_deps

    info "Installing Node.js ${NODE_MAJOR_TARGET}.x from NodeSource..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_TARGET}.x" | as_root_env bash -
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

    current_major="$(node_major_version)"
    [[ "$current_major" =~ ^[0-9]+$ ]] && [[ "$current_major" -ge 20 ]] || die "Node.js >= 20 was not installed correctly."
    command -v npm >/dev/null 2>&1 || die "npm was not installed correctly."

    ok "Node.js is ready: $(node --version), npm $(npm --version)"
}

confirm_delete_install_dir() {
    local answer

    echo
    warn "Directory already exists: $INSTALL_DIR"
    read_tty "Delete it and clone SillyTavern again? [y/N]: " answer || die "Could not read confirmation."

    case "$answer" in
        y|Y|yes|YES)
            safe_install_dir
            info "Removing old directory..."
            rm -rf -- "$INSTALL_DIR"
            ;;
        *)
            die "Clone cancelled because the target directory already exists."
            ;;
    esac
}

clone_repo() {
    require_ubuntu
    safe_install_dir

    command -v git >/dev/null 2>&1 || die "git is not installed. Run menu option 1 first."

    if [[ -e "$INSTALL_DIR" ]]; then
        confirm_delete_install_dir
    fi

    mkdir -p "$(dirname "$INSTALL_DIR")"

    info "Cloning SillyTavern ${BRANCH} into $INSTALL_DIR"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"

    [[ -f "$INSTALL_DIR/package.json" ]] || die "Clone finished, but package.json was not found."
    ok "SillyTavern cloned successfully."
}

install_project_deps() {
    require_ubuntu

    [[ -f "$INSTALL_DIR/package.json" ]] || die "SillyTavern is not installed at $INSTALL_DIR."
    command -v npm >/dev/null 2>&1 || die "npm is not installed. Run menu option 2 first."

    info "Installing SillyTavern npm dependencies..."
    (
        cd "$INSTALL_DIR"
        export NODE_ENV=production
        npm install --no-save --no-audit --no-fund --loglevel=error --no-progress --omit=dev --ignore-scripts
    )

    ok "SillyTavern dependencies are ready."
}

start_tavern() {
    require_ubuntu

    [[ -f "$INSTALL_DIR/start.sh" ]] || die "start.sh was not found at $INSTALL_DIR."

    chmod +x "$INSTALL_DIR/start.sh" || true

    echo
    ok "Starting SillyTavern..."
    echo "Open this address in your browser: http://127.0.0.1:8000"
    echo

    (
        cd "$INSTALL_DIR"
        bash ./start.sh
    )
}

update_tavern() {
    require_ubuntu

    [[ -d "$INSTALL_DIR/.git" ]] || die "$INSTALL_DIR is not a git repository."

    info "Updating SillyTavern from origin/${BRANCH}..."
    (
        cd "$INSTALL_DIR"
        git fetch origin "$BRANCH"
        git checkout "$BRANCH"
        git pull --ff-only origin "$BRANCH"
    )

    install_project_deps
    ok "SillyTavern update finished."
}

one_click_install() {
    require_ubuntu

    echo "====================================================="
    echo "        Ubuntu SillyTavern one-click install"
    echo "        凌宇和苏苏子制作OVO"
    echo "====================================================="
    echo

    install_system_deps
    install_node
    clone_repo
    install_project_deps

    echo
    ok "Install finished."
    echo "Install path: $INSTALL_DIR"
    echo "Start command:"
    echo "  cd \"$INSTALL_DIR\" && bash ./start.sh"
    echo "Browser address after start:"
    echo "  http://127.0.0.1:8000"
}

show_menu() {
    clear || true
    echo "====================================================="
    echo "        SillyTavern Ubuntu Installer"
    echo "        凌宇和苏苏子制作OVO"
    echo "====================================================="
    echo "Install path: $INSTALL_DIR"
    echo "Branch:       $BRANCH"
    echo
    echo "  1. Install system dependencies"
    echo "  2. Install/check Node.js"
    echo "  3. Clone SillyTavern"
    echo "  4. Install project dependencies"
    echo "  5. Start SillyTavern"
    echo "  6. Update SillyTavern"
    echo "  7. One-click install"
    echo "  0. Exit"
    echo
    echo "====================================================="
}

main_menu() {
    require_ubuntu

    local choice

    while true; do
        show_menu
        read_tty "Choose an action [0-7]: " choice || die "Could not read menu choice."

        case "$choice" in
            1) install_system_deps; pause_menu ;;
            2) install_node; pause_menu ;;
            3) clone_repo; pause_menu ;;
            4) install_project_deps; pause_menu ;;
            5) start_tavern ;;
            6) update_tavern; pause_menu ;;
            7) one_click_install; pause_menu ;;
            0) echo "Bye."; exit 0 ;;
            *) warn "Invalid choice."; pause_menu ;;
        esac
    done
}

case "${1:-}" in
    "")
        main_menu
        ;;
    --one-click)
        one_click_install
        ;;
    --help|-h)
        usage
        ;;
    *)
        usage
        die "Unknown argument: $1"
        ;;
esac
