#!/usr/bin/env bash
# cosmic-loongarch · 20-apply：应用/预演/撤销 patches/<repo>/*.patch
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

MODE=apply
for a in "$@"; do case "$a" in
  --check) MODE=check;; --list) MODE=list;; --revert) MODE=revert;;
  -h|--help) echo "用法: $0 [--check|--list|--revert]"; exit 0;;
  *) die "未知参数: $a";; esac; done

[ -d "$PATCHES_DIR" ] || die "缺少 $PATCHES_DIR"
mapfile -t REPOS < <(find "$PATCHES_DIR" -mindepth 1 -maxdepth 1 -type d -not -name templates -printf '%f\n' | sort)
[ "${#REPOS[@]}" -gt 0 ] || { warn "patches/ 下暂无补丁（基线构建）"; exit 0; }

list_patches() { printf '%s\n' "$PATCHES_DIR/$1"/*.patch 2>/dev/null | grep -v '\*' || true; }
applied_file="$STATE_DIR/patches-applied.txt"

case "$MODE" in
  list)
    for r in "${REPOS[@]}"; do
      for p in $(list_patches "$r"); do printf '  %-28s %s\n' "$r" "$(basename "$p")"; done
    done
    ;;
  revert)
    for r in "${REPOS[@]}"; do
      git -C "$BUILD_DIR/$r" rev-parse --is-inside-work-tree >/dev/null 2>&1 || continue
      git -C "$BUILD_DIR/$r" reset -q 2>/dev/null || true
      git -C "$BUILD_DIR/$r" checkout -- . 2>/dev/null || true
      git -C "$BUILD_DIR/$r" clean -fdq 2>/dev/null || true   # 清掉补丁新增的文件（不影响 gitignore 的 target/）
      ok "已撤销 $r 的补丁改动"
    done
    rm -f "$applied_file"; ok "20-apply --revert 完成"
    ;;
  check|apply)
    : > "${applied_file}.tmp"
    fail=0
    for r in "${REPOS[@]}"; do
      git -C "$BUILD_DIR/$r" rev-parse --is-inside-work-tree >/dev/null 2>&1 || { warn "$r 不在构建树中，跳过"; continue; }
      for p in $(list_patches "$r"); do
        name="$(basename "$p")"
        if [ "$MODE" = "check" ]; then
          if git -C "$BUILD_DIR/$r" apply --check "$p" 2>/dev/null; then ok "[预演通过] $r/$name";
          elif git -C "$BUILD_DIR/$r" apply --check --3way "$p" 2>/dev/null; then warn "[需 3-way] $r/$name";
          else warn "[冲突]     $r/$name"; fail=1; fi
        else
          if git -C "$BUILD_DIR/$r" apply --3way --whitespace=nowarn "$p" 2>/dev/null; then
            ok "已应用 $r/$name"; echo "$r $name" >> "${applied_file}.tmp"
          else die "应用失败（需手工解冲突）: $r/$name"; fi
        fi
      done
    done
    [ "$MODE" = "apply" ] && mv "${applied_file}.tmp" "$applied_file"
    { [ "$MODE" = "check" ] && [ "$fail" = "0" ]; } && ok "全部补丁预演通过" || true
    [ "$fail" = "0" ] || exit 1
    ;;
esac
ok "20-apply 完成（模式 $MODE）"
