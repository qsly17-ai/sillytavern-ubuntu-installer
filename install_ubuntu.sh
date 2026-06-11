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

trap 'echo -e "${RED}错误：第 ${LINENO} 行命令执行失败。${NC}" >&2' ERR

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
    echo -e "${RED}错误：$*${NC}" >&2
    exit 1
}

usage() {
    cat <<EOF
Ubuntu 酒馆（SillyTavern）安装工具
凌宇和苏苏子制作OVO

使用方法：
  bash install_ubuntu.sh             打开中文菜单
  bash install_ubuntu.sh --one-click 直接执行完整一键安装
  bash install_ubuntu.sh --help      显示帮助

可选环境变量：
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
        read -r -p "按回车键返回菜单..." _ < /dev/tty || true
    fi
}

require_ubuntu() {
    [[ -r /etc/os-release ]] || die "无法检测当前系统。本脚本仅支持 Ubuntu。"

    # shellcheck disable=SC1091
    source /etc/os-release

    if [[ "${ID:-}" != "ubuntu" ]]; then
        die "本脚本仅支持 Ubuntu。当前检测到：${PRETTY_NAME:-未知系统}"
    fi
}

require_privilege_tool() {
    if [[ "${EUID}" -ne 0 ]] && ! command -v sudo >/dev/null 2>&1; then
        die "普通用户运行时需要 sudo 权限，请先安装或启用 sudo。"
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
    [[ -n "$INSTALL_DIR" ]] || die "安装目录为空，请检查 SILLYTAVERN_DIR。"
    [[ "$INSTALL_DIR" != "/" ]] || die "为保护系统，拒绝把 / 作为安装目录。"
}

install_system_deps() {
    require_ubuntu
    require_privilege_tool

    info "正在安装系统依赖：git、curl、ca-certificates"
    as_root apt-get update
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y git curl ca-certificates

    command -v git >/dev/null 2>&1 || die "Git 安装后仍无法使用，请检查 apt 输出。"
    command -v curl >/dev/null 2>&1 || die "curl 安装后仍无法使用，请检查 apt 输出。"

    ok "系统依赖已准备完成。"
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
        ok "Node.js 已准备完成：$(node --version)，npm $(npm --version)"
        return 0
    fi

    if command -v node >/dev/null 2>&1; then
        warn "检测到 Node.js $(node --version)，但 SillyTavern 需要 Node.js 20 或更高版本。"
    else
        warn "未检测到 Node.js。"
    fi

    install_system_deps

    info "正在通过 NodeSource 安装 Node.js ${NODE_MAJOR_TARGET}.x..."
    curl -fsSL "https://deb.nodesource.com/setup_${NODE_MAJOR_TARGET}.x" | as_root_env bash -
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install -y nodejs

    current_major="$(node_major_version)"
    [[ "$current_major" =~ ^[0-9]+$ ]] && [[ "$current_major" -ge 20 ]] || die "Node.js 20 或更高版本未正确安装。"
    command -v npm >/dev/null 2>&1 || die "npm 未正确安装。"

    ok "Node.js 已准备完成：$(node --version)，npm $(npm --version)"
}

confirm_delete_install_dir() {
    local answer

    echo
    warn "安装目录已经存在：$INSTALL_DIR"
    read_tty "是否删除旧目录并重新克隆 SillyTavern？输入 y 确认，直接回车取消 [y/N]: " answer || die "无法读取确认输入。"

    case "$answer" in
        y|Y|yes|YES)
            safe_install_dir
            info "正在删除旧目录..."
            rm -rf -- "$INSTALL_DIR"
            ;;
        *)
            die "已取消克隆，因为目标目录已经存在。"
            ;;
    esac
}

clone_repo() {
    require_ubuntu
    safe_install_dir

    command -v git >/dev/null 2>&1 || die "尚未安装 Git，请先执行菜单选项 1。"

    if [[ -e "$INSTALL_DIR" ]]; then
        confirm_delete_install_dir
    fi

    mkdir -p "$(dirname "$INSTALL_DIR")"

    info "正在把 SillyTavern 的 ${BRANCH} 分支克隆到：$INSTALL_DIR"
    git clone --branch "$BRANCH" --depth 1 "$REPO_URL" "$INSTALL_DIR"

    [[ -f "$INSTALL_DIR/package.json" ]] || die "克隆结束，但没有找到 package.json，项目目录可能不完整。"
    ok "SillyTavern 克隆完成。"
}

install_project_deps() {
    require_ubuntu

    [[ -f "$INSTALL_DIR/package.json" ]] || die "在 $INSTALL_DIR 没有找到 SillyTavern，请先完成克隆。"
    command -v npm >/dev/null 2>&1 || die "尚未安装 npm，请先执行菜单选项 2。"

    info "正在安装 SillyTavern 项目依赖，这一步可能需要几分钟..."
    (
        cd "$INSTALL_DIR"
        export NODE_ENV=production
        npm install --no-save --no-audit --no-fund --loglevel=error --no-progress --omit=dev --ignore-scripts
    )

    ok "SillyTavern 项目依赖已安装完成。"
}

start_tavern() {
    require_ubuntu

    [[ -f "$INSTALL_DIR/start.sh" ]] || die "在 $INSTALL_DIR 没有找到 start.sh，请先完成安装。"

    chmod +x "$INSTALL_DIR/start.sh" || true

    echo
    ok "正在启动 SillyTavern..."
    echo "启动成功后，请在浏览器打开：http://127.0.0.1:8000"
    echo

    (
        cd "$INSTALL_DIR"
        bash ./start.sh
    )
}

update_tavern() {
    require_ubuntu

    [[ -d "$INSTALL_DIR/.git" ]] || die "$INSTALL_DIR 不是有效的 Git 项目目录，请先完成安装。"

    info "正在从 origin/${BRANCH} 更新 SillyTavern..."
    (
        cd "$INSTALL_DIR"
        git fetch origin "$BRANCH"
        git checkout "$BRANCH"
        git pull --ff-only origin "$BRANCH"
    )

    install_project_deps
    ok "SillyTavern 更新完成。"
}

one_click_install() {
    require_ubuntu

    echo "====================================================="
    echo "        Ubuntu 酒馆一键安装"
    echo "        凌宇和苏苏子制作OVO"
    echo "====================================================="
    echo

    install_system_deps
    install_node
    clone_repo
    install_project_deps

    echo
    ok "一键安装全部完成。"
    echo "安装目录：$INSTALL_DIR"
    echo "以后启动可以执行："
    echo "  cd \"$INSTALL_DIR\" && bash ./start.sh"
    echo "启动后浏览器访问："
    echo "  http://127.0.0.1:8000"
}

show_menu() {
    clear || true
    echo "====================================================="
    echo "        Ubuntu 酒馆安装工具"
    echo "        凌宇和苏苏子制作OVO"
    echo "====================================================="
    echo "安装目录：$INSTALL_DIR"
    echo "项目分支：$BRANCH"
    echo
    echo "  1. 安装基础环境"
    echo "  2. 安装或检查 Node.js"
    echo "  3. 下载 SillyTavern 项目"
    echo "  4. 安装项目依赖"
    echo "  5. 启动 SillyTavern"
    echo "  6. 更新 SillyTavern"
    echo "  7. 一键安装（新手推荐）"
    echo "  0. 退出"
    echo
    echo "====================================================="
}

main_menu() {
    require_ubuntu

    local choice

    while true; do
        show_menu
        read_tty "请输入要执行的选项 [0-7]: " choice || die "无法读取菜单选项。"

        case "$choice" in
            1) install_system_deps; pause_menu ;;
            2) install_node; pause_menu ;;
            3) clone_repo; pause_menu ;;
            4) install_project_deps; pause_menu ;;
            5) start_tavern ;;
            6) update_tavern; pause_menu ;;
            7) one_click_install; pause_menu ;;
            0) echo "已退出。"; exit 0 ;;
            *) warn "无效选项，请重新输入。"; pause_menu ;;
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
        die "未知参数：$1"
        ;;
esac
