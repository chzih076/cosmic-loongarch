#!/usr/bin/env bash
# cosmic-loongarch · 公共库：路径、日志、lock 解析、构建环境、状态记录
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LOCK_FILE="$REPO_ROOT/upstream.lock"
PATCHES_DIR="$REPO_ROOT/patches"
STATE_DIR="$REPO_ROOT/state"
BUILD_DIR="${COSMIC_BUILD_DIR:-$HOME/cosmic-build}"
BUILD_LOG="${BUILD_LOG:-$BUILD_DIR/build.log}"

if [ -t 1 ]; then c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_blu=$'\033[36m'; c_off=$'\033[0m'
else c_red=; c_grn=; c_yel=; c_blu=; c_off=; fi
log()  { printf '%s[*]%s %s\n' "$c_blu" "$c_off" "$*"; }
ok()   { printf '%s[+]%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yel" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

require_cmd() { command -v "$1" >/dev/null 2>&1 || die "缺少命令: $1"; }

# ---- upstream.lock ----------------------------------------------------------
lock_entries() { grep -vE '^[[:space:]]*#|^[[:space:]]*$' "$LOCK_FILE"; }
lock_sha()     { awk -v n="$1" '$1==n{print $2}' "$LOCK_FILE"; }
lock_url()     { awk -v n="$1" '$1==n{print $3}' "$LOCK_FILE"; }
lock_names()   { lock_entries | awk '{print $1}'; }

# ---- 状态记录 ---------------------------------------------------------------
state_set() { mkdir -p "$STATE_DIR"; printf '%s\n' "$2" > "$STATE_DIR/$1"; }
state_get() { [ -f "$STATE_DIR/$1" ] && cat "$STATE_DIR/$1" || true; }

# ---- 构建环境（K-001 / K-002 的规避在此统一导出）----------------------------
export_build_env() {
  export PKG_CONFIG_PATH="/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
  export LIBRARY_PATH="/usr/local/lib:${LIBRARY_PATH:-}"
  export LD_LIBRARY_PATH="/usr/local/lib:${LD_LIBRARY_PATH:-}"
  export TURBOJPEG_SOURCE="${TURBOJPEG_SOURCE:-pkg-config}"     # K-002
  export CARGO_BUILD_JOBS="${CARGO_BUILD_JOBS:-8}"              # 防内存爆
  export CARGO_TERM_COLOR=never
  if command -v sccache >/dev/null 2>&1; then
    export RUSTC_WRAPPER="$(command -v sccache)"
    export SCCACHE_DIR="${SCCACHE_DIR:-$HOME/.cache/sccache}"
    export SCCACHE_MAXSIZE="${SCCACHE_MAXSIZE:-20G}"
  else
    warn "未找到 sccache：重复构建会明显更慢（可选：cargo install sccache）"
  fi
  export GH_PROXY="${GH_PROXY:-}"
}

# 官方 URL → 经镜像/代理的 URL（仅用于 git 克隆）
url_with_proxy() {
  if [ -n "${GH_PROXY:-}" ]; then printf '%s%s' "$GH_PROXY" "$1"; else printf '%s' "$1"; fi
}

# 需要 sudo 的操作：--yes 时用 -n 非交互，否则提示
sudo_run() {
  if [ "${ASSUME_YES:-0}" = "1" ]; then sudo -n "$@"; else sudo "$@"; fi
}
