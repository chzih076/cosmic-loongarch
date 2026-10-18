#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
#
# 60-verify.sh — 验证原生包安装后的状态（全部为只读检查）
#
# 检查项：
#   1. 各组件的包版本 = 目标 epoch 版本
#   2. 构建产物与已安装二进制逐字节一致（补丁组件除外，需单独校验特征串）
#   3. /usr 可写（非只读叠加）且无 systemd-sysext 合并
#   4. 补丁特征存在（cosmic-comp 的 animations 开关）
#   5. 主题编辑器包含磨砂 UI（cosmic-settings）
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); REPO_ROOT=$(cd "$HERE/.." && pwd)
if [ -t 1 ]; then c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_off=$'\033[0m'
else c_red=; c_grn=; c_yel=; c_off=; fi
ok(){ printf '%s[+]%s %s\n' "$c_grn" "$c_off" "$*"; }
bad(){ printf '%s[x]%s %s\n' "$c_red" "$c_off" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$c_yel" "$c_off" "$*" >&2; }
say(){ printf '\n== %s\n' "$*"; }

VERSION=$(cat "$REPO_ROOT/state/epoch-version" 2>/dev/null || echo "1.10.0")
BUILD_DIR="${COSMIC_BUILD_DIR:-$(cat "$REPO_ROOT/state/build-dir" 2>/dev/null)}"
SX="$BUILD_DIR/cosmic-sysext"
FAIL=0

say "1) 包版本（目标 $VERSION）"
for p in $(dpkg -l 2>/dev/null | awk '/^ii/{print $2" "$3}' | grep -E '^(cosmic-|xdg-desktop-portal-cosmic|pop-launcher)' | awk '{print $1}'); do
  v=$(dpkg -l "$p" 2>/dev/null | awk '/^ii/{print $3}')
  case "$v" in "$VERSION"*|1) ok "$(printf '%-32s %s' "$p" "$v")";; *) bad "$(printf '%-32s %s（非 %s）' "$p" "$v" "$VERSION")"; FAIL=1;; esac
done

say "2) 二进制与构建产物比对"
if [ -d "$SX/usr/bin" ]; then
  same=0; diff=0; miss=0
  for f in "$SX"/usr/bin/*; do
    b=$(basename "$f")
    if [ ! -x "/usr/bin/$b" ]; then bad "未安装: $b"; miss=$((miss+1)); continue; fi
    a=$(sha256sum "$f" | cut -c1-16); c=$(sha256sum "/usr/bin/$b" | cut -c1-16)
    if [ "$a" = "$c" ]; then same=$((same+1)); else
      case "$b" in
        cosmic-comp) ok "cosmic-comp 使用带补丁版本（预期不同）";;
        *) bad "不一致: $b（构建=$a 安装=$c）"; FAIL=1;;
      esac; diff=$((diff+1))
    fi
  done
  ok "一致 $same 个，差异 $diff 个，缺失 $miss 个"
else
  warn "找不到构建产物，跳过比对（设置 COSMIC_BUILD_DIR 或 state/build-dir）"
fi

say "3) 文件系统与叠加层"
if systemd-sysext status 2>/dev/null | grep -q cosmic; then bad "sysext 仍处于合并状态（应无）"; FAIL=1; else ok "无 sysext 合并"; fi
if findmnt -no FSTYPE /usr 2>/dev/null | grep -q overlay; then bad "/usr 是 overlay（只读叠加）"; FAIL=1; else ok "/usr 不是叠加层"; fi
if [ -w /usr/bin ]; then ok "/usr 可写"; else warn "/usr 不可写（非 root 身份运行则正常）"; fi

say "4) 补丁特征"
if strings -a /usr/bin/cosmic-comp 2>/dev/null | grep -q 'animations: enabled'; then ok "cosmic-comp 含动画补丁"; else bad "cosmic-comp 缺少补丁特征"; FAIL=1; fi
if strings -a /usr/bin/cosmic-settings 2>/dev/null | grep -qi 'frosted.thickness'; then ok "cosmic-settings 含磨砂 UI"; else bad "cosmic-settings 缺少磨砂 UI"; FAIL=1; fi

say "结果"
if [ "$FAIL" = 0 ]; then ok "全部检查通过"; exit 0; else bad "存在失败项"; exit 1; fi
