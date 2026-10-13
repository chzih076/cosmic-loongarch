#!/usr/bin/env bash
# cosmic-loongarch · 00-deps：依赖体检 + 编译安装 libseat（官方源码，logind 后端）
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

CHECK_ONLY=0; ASSUME_YES=0
for a in "$@"; do case "$a" in
  --check) CHECK_ONLY=1;; --yes|-y) ASSUME_YES=1; export ASSUME_YES;;
  -h|--help) echo "用法: $0 [--check] [--yes]"; exit 0;;
  *) die "未知参数: $a";; esac; done

SEATD_URL="${SEATD_URL:-https://git.sr.ht/~kennylevinsen/seatd}"
SEATD_DIR="${SEATD_DIR:-$BUILD_DIR/../seatd}"

log "架构/发行版：$(uname -m) / $( . /etc/os-release 2>/dev/null; printf '%s %s' "${ID:-?}" "${VERSION_ID:-?}" )"
[ "$(uname -m)" = "loongarch64" ] || warn "本仓库针对 loongarch64；当前架构 $(uname -m) 可能需调整"

log "检查构建工具"
missing=0
for c in git rustc cargo pkg-config meson ninja cmake sed awk; do
  if command -v "$c" >/dev/null 2>&1; then ok "$c"; else warn "缺少 $c"; missing=1; fi
done
command -v just >/dev/null 2>&1 && ok "just ($(just --version))" || { warn "缺少 just（可 cargo install just）"; missing=1; }
command -v sccache >/dev/null 2>&1 && ok "sccache" || warn "缺少 sccache（可选，建议安装以加速重复构建）"
[ "$missing" = "0" ] || warn "请先补齐上面的工具（AOSC: oma install <包名>；Rust 工具用 cargo install）"

log "检查运行期库（缺失会导致会话异常）"
for lib in libseat.so.1 libxkbcommon.so.0 libinput.so.10 libgbm.so.1 libEGL.so.1 libvulkan.so.1 libdisplay-info.so.3 libpipewire-0.3.so.0; do
  if ldconfig -p 2>/dev/null | grep -q "$lib"; then ok "$lib"; else warn "缺少 $lib"; fi
done

if pkg-config --exists libseat 2>/dev/null || [ -n "$(PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion libseat 2>/dev/null)" ]; then
  ok "libseat 已安装（$(PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion libseat)），跳过编译"
else
  [ "$CHECK_ONLY" = "1" ] && die "libseat 未安装（去掉 --check 以自动编译安装）"
  log "libseat 缺失 → 从官方源码编译（$SEATD_URL）"
  if [ ! -d "$SEATD_DIR/.git" ]; then
    git clone --depth 1 "$SEATD_URL" "$SEATD_DIR"
  else
    git -C "$SEATD_DIR" pull --ff-only || warn "seatd 更新失败，使用现有源码"
  fi
  ( cd "$SEATD_DIR" && meson setup build -Dlibseat-logind=systemd -Dman-pages=disabled -Dserver=disabled --wipe >/dev/null 2>&1 || meson setup build -Dlibseat-logind=systemd -Dman-pages=disabled -Dserver=disabled >/dev/null
    ninja -C build >/dev/null )
  sudo_run ninja -C "$SEATD_DIR/build" install
  sudo_run ldconfig
  PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion libseat >/dev/null \
    && ok "libseat 安装完成" || die "libseat 安装后仍找不到（检查 /usr/local/lib/pkgconfig/libseat.pc）"
fi
ok "00-deps 完成"
