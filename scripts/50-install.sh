#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
#
# 50-install.sh — 安装 40-package.sh 产出的原生 .deb
#
# 包名与发行版一致、版本更高（如 1.10.0 > 1.0.14），dpkg 视为升级替换，
# 因此 /usr 保持可写、oma/dpkg 等包管理器继续正常工作。
#
# 用法： sudo ./scripts/50-install.sh [--version 1.10.0] [--dry-run]
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); REPO_ROOT=$(cd "$HERE/.." && pwd)
if [ -t 1 ]; then c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_off=$'\033[0m'
else c_red=; c_grn=; c_yel=; c_off=; fi
say(){ printf '\n== %s\n' "$*"; }; ok(){ printf '%s[+]%s %s\n' "$c_grn" "$c_off" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$c_yel" "$c_off" "$*" >&2; }; die(){ printf '%s[x]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

VERSION="1.10.0"; DRY=0
while [ $# -gt 0 ]; do case "$1" in
  --version) VERSION="$2"; shift 2;;
  --dry-run) DRY=1; shift;;
  -h|--help) sed -n '2,14p' "$0"; exit 0;;
  *) die "未知参数: $1";;
esac; done

DEBS_DIR="$REPO_ROOT/out/debs"
[ -d "$DEBS_DIR" ] || die "未找到 $DEBS_DIR（先运行 40-package.sh）"
shopt -s nullglob
DEBS=("$DEBS_DIR"/*.deb)
[ ${#DEBS[@]} -gt 0 ] || die "目录里没有 .deb"
[ "$(id -u)" = 0 ] || die "需要 root：sudo $0"
command -v dpkg >/dev/null || die "缺少 dpkg"

say "1) 预检（dpkg --dry-run，不实际安装）"
if dpkg --dry-run -i "${DEBS[@]}" >/dev/null 2>"$REPO_ROOT/out/.dryrun.log"; then
  ok "无冲突，可以安装"
else
  warn "dpkg 预检有提示（前 10 行）："; head -10 "$REPO_ROOT/out/.dryrun.log"
fi

say "2) 安装 ${#DEBS[@]} 个包（版本 $VERSION）"
if [ "$DRY" = 1 ]; then
  warn "--dry-run：跳过实际安装"; exit 0
fi
dpkg -i "${DEBS[@]}" || die "安装失败"

say "3) 刷新缓存"
for c in /usr/share/icons/Cosmic /usr/share/icons/hicolor; do
  [ -d "$c" ] && gtk-update-icon-cache -q -t -f "$c" 2>/dev/null && ok "图标缓存: $c"
done
update-desktop-database /usr/share/applications 2>/dev/null && ok "桌面条目数据库"
command -v systemctl >/dev/null && systemctl daemon-reload 2>/dev/null && ok "systemd 配置重载"

say "4) 安装后版本"
dpkg -l 2>/dev/null | awk '/^ii/{print $2" "$3}' | grep -E '^(cosmic-|xdg-desktop-portal-cosmic|pop-launcher)' | while read -r p v; do
  printf '  %-32s %s\n' "$p" "$v"
done

say "完成"
cat <<'EOF'
  需要【注销并重新登录】（或重启）让新组件生效。
  回滚到发行版自带版本: sudo ./scripts/99-uninstall.sh
EOF
