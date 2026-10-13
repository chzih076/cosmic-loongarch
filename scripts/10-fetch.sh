#!/usr/bin/env bash
# cosmic-loongarch · 10-fetch：按 upstream.lock 获取/校验上游源码
#   默认：存在即只校验（不联网）；缺失才克隆
#   --update：增量 fetch 并切到 lock 中的 commit（会联网）
#   --lock  ：由现有构建树反向生成 upstream.lock
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

MODE=verify
for a in "$@"; do case "$a" in
  --check)  MODE=verify;;
  --update) MODE=update;;
  --lock)   MODE=lock;;
  -h|--help) echo "用法: $0 [--check|--update|--lock]"; exit 0;;
  *) die "未知参数: $a";; esac; done

EPOCH_SHA="$(lock_sha cosmic-epoch)"; [ -n "$EPOCH_SHA" ] || die "upstream.lock 解析失败"
EPOCH_URL="$(lock_url cosmic-epoch)"

safe_sha() { case "$1" in ''|*[!0-9a-f]*|0000000000000000000000000000000000000000) return 1;; *) return 0;; esac; }

verify() {
  local bad=0 n sha have
  for n in $(lock_names); do
    sha="$(lock_sha "$n")"
    safe_sha "$sha" || { warn "$n 在 lock 中缺少有效 commit，跳过"; continue; }
    if [ "$n" = "cosmic-epoch" ]; then
      have="$(git -C "$BUILD_DIR" rev-parse HEAD 2>/dev/null || true)"
    else
      have="$(git -C "$BUILD_DIR/$n" rev-parse HEAD 2>/dev/null || true)"
    fi
    if [ "$have" = "$sha" ]; then
      [ "$n" = "cosmic-epoch" ] && ok "cosmic-epoch @ ${sha:0:9}"
    else
      warn "$n 期望 ${sha:0:9}，实为 ${have:0:9}"; bad=1
    fi
  done
  if [ "$bad" = "0" ]; then ok "全部 pin 与 upstream.lock 一致（$(lock_entries | wc -l) 条）"; else
    warn "存在不一致：如需升到 lock 的 commit，执行 $0 --update"; return 1; fi
}

case "$MODE" in
  lock)
    log "由现有构建树重新生成 upstream.lock（SHA 取自 gitlink：git ls-tree HEAD <path>）"
    # 说明：不要解析 `git submodule status <path>`（部分 git 版本会输出异常短值）；
    #       子模块的权威 commit 是父仓库中记录的 gitlink。
    {
      echo "# cosmic-loongarch upstream lockfile"
      echo "# 用途：锁定上游 cosmic-epoch 及其子模块的精确 commit，保证任何人构建出同一份代码"
      echo "# 生成：scripts/10-fetch.sh --lock（本文件由脚本维护，可手工检查但不要手改）"
      echo "# 生成时间：$(date -Iseconds)"
      echo "# 格式：<name> <commit> <官方 URL>（name = 子模块目录名，与 patches/<name>/ 对应）"
      echo "# 来源：SHA 取自父仓库 gitlink（git ls-tree HEAD），URL 取自 .gitmodules"
      echo "#"
      echo "cosmic-epoch $(git -C "$BUILD_DIR" rev-parse HEAD) https://github.com/pop-os/cosmic-epoch"
      git -C "$BUILD_DIR" ls-tree -r HEAD 2>/dev/null | while read -r mode type sha path; do
        [ "$mode" = "160000" ] || continue
        # 从 .gitmodules 里按 path 反查 URL
        url="$(git -C "$BUILD_DIR" config -f .gitmodules --get-regexp '^submodule\..*\.path$' 2>/dev/null \
              | awk -v p="$path" '$2==p{print $1}' | head -1 \
              | sed 's/^submodule\.//; s/\.path$//' \
              | while read -r nm; do git -C "$BUILD_DIR" config -f .gitmodules --get "submodule.$nm.url" 2>/dev/null; done)"
        [ -n "$url" ] || url="https://github.com/pop-os/${path##*/}"
        echo "$path $sha $url"
      done | sort
    } > "$LOCK_FILE"
    ok "已写入 $LOCK_FILE（$(grep -vc '^#' "$LOCK_FILE") 条 pin：1 本体 + $(( $(grep -vc '^#' "$LOCK_FILE") - 1 )) 子模块）"
    ;;
  update)
    if [ ! -d "$BUILD_DIR/.git" ]; then
      log "构建目录不存在 → 克隆上游（$(url_with_proxy "$EPOCH_URL")）"
      git clone --recurse-submodules --jobs 4 "$(url_with_proxy "$EPOCH_URL")" "$BUILD_DIR"
    fi
    log "拉取上游并切到 lock 指定的 commit"
    git -C "$BUILD_DIR" fetch --all --tags --prune || warn "fetch 失败（离线？）"
    git -C "$BUILD_DIR" checkout --detach "$EPOCH_SHA" || die "无法切到 cosmic-epoch $EPOCH_SHA"
    git -C "$BUILD_DIR" submodule update --init --recursive --jobs 4
    for n in $(lock_names); do
      [ "$n" = "cosmic-epoch" ] && continue
      sha="$(lock_sha "$n")"; safe_sha "$sha" || continue
      [ -d "$BUILD_DIR/$n" ] || continue
      git -C "$BUILD_DIR/$n" checkout --detach "$sha" 2>/dev/null || warn "$n 无法切到 $sha"
    done
    verify
    state_set upstream-sha "$EPOCH_SHA"
    ;;
  verify)
    [ -d "$BUILD_DIR/.git" ] || die "构建目录 $BUILD_DIR 不存在（先执行 $0 --update）"
    verify || exit 1
    ;;
esac
ok "10-fetch 完成（BUILD_DIR=$BUILD_DIR）"
