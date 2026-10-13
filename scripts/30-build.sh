#!/usr/bin/env bash
# cosmic-loongarch · 30-build：构建（just sysext），内置 loongarch64 必需环境变量与缓存
#   --jobs N   并发数（默认 8）
#   --slim     构建后清理各仓库 target/（释放约 37 GB；保留 sccache）
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

SLIM=0
while [ $# -gt 0 ]; do case "$1" in
  --jobs) CARGO_BUILD_JOBS="$2"; shift 2;;
  --slim) SLIM=1; shift;;
  -h|--help) echo "用法: $0 [--jobs N] [--slim]"; exit 0;;
  *) die "未知参数: $1";; esac; done

[ -d "$BUILD_DIR/.git" ] || die "构建目录不存在（先 10-fetch.sh）"
require_cmd just
export_build_env

log "环境：libseat=$(PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion libseat 2>/dev/null || echo 缺失) turbojpeg=$(pkg-config --modversion libturbojpeg 2>/dev/null || echo 缺失)"
log "并发=$CARGO_BUILD_JOBS  sccache=${RUSTC_WRAPPER:-未启用}  TURBOJPEG_SOURCE=$TURBOJPEG_SOURCE"
log "构建日志 → $BUILD_LOG"
mkdir -p "$BUILD_DIR"
date -Iseconds > "$BUILD_LOG"
( cd "$BUILD_DIR" && just sysext ) >>"$BUILD_LOG" 2>&1 || {
  warn "构建失败，最后 30 行："; tail -30 "$BUILD_LOG" | sed 's/^/    /'; die "见 $BUILD_LOG"; }
ok "构建完成：$(grep -c 'Finished.*release' "$BUILD_LOG") 个组件首次产出（其余命中缓存）"
state_set upstream-sha "$(git -C "$BUILD_DIR" rev-parse HEAD)"
state_set last-build "$(date -Iseconds)"

if [ -d "$BUILD_DIR/cosmic-sysext" ]; then
  ok "产物：$BUILD_DIR/cosmic-sysext（$(du -sh "$BUILD_DIR/cosmic-sysext" | cut -f1)）"
fi

if [ "$SLIM" = "1" ]; then
  log "清理各仓库 target/（sccache 保留）"
  before="$(du -shc "$BUILD_DIR"/*/target 2>/dev/null | tail -1 | cut -f1 || echo 0)"
  rm -rf "$BUILD_DIR"/*/target
  ok "已释放（清理前合计 $before）"
fi
