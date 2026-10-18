#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
#
# 99-uninstall.sh — 从本项目的原生包回滚到发行版自带的版本
#
# 做法：把本项目的包列表按发行版仓库里的版本重新安装（降级），
# 从而恢复发行版的 COSMIC（AOSC 目前是 epoch 1.0.x）。
#
# 用法： sudo ./scripts/99-uninstall.sh [--dry-run]
set -uo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd); REPO_ROOT=$(cd "$HERE/.." && pwd)
if [ -t 1 ]; then c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_off=$'\033[0m'
else c_red=; c_grn=; c_yel=; c_off=; fi
say(){ printf '\n== %s\n' "$*"; }; ok(){ printf '%s[+]%s %s\n' "$c_grn" "$c_off" "$*"; }
warn(){ printf '%s[!]%s %s\n' "$c_yel" "$c_off" "$*" >&2; }; die(){ printf '%s[x]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

DRY=0; [ "${1:-}" = "--dry-run" ] && DRY=1
[ "$(id -u)" = 0 ] || die "需要 root：sudo $0"

# 本项目安装过的包（与 40-package.sh 的映射一致）
PKGS="cosmic-comp cosmic-panel cosmic-settings cosmic-settings-daemon cosmic-session \
cosmic-applets cosmic-app-library cosmic-bg cosmic-edit cosmic-files cosmic-greeter \
cosmic-idle cosmic-initial-setup cosmic-launcher cosmic-notifications cosmic-osd \
cosmic-player cosmic-randr cosmic-screenshot cosmic-store cosmic-term cosmic-workspaces \
xdg-desktop-portal-cosmic pop-launcher"

say "1) 当前版本"
for p in $PKGS; do
  v=$(dpkg -l "$p" 2>/dev/null | awk '/^ii/{print $3}')
  printf '  %-32s %s\n' "$p" "${v:-（未安装）}"
done

say "2) 从发行版仓库重装（降级 = 回滚）"
if [ "$DRY" = 1 ]; then
  warn "--dry-run：以下命令不会执行："
  echo "  apt-get install -y --allow-downgrades $PKGS"
  exit 0
fi
# shellcheck disable=SC2086
apt-get install -y --allow-downgrades $PKGS || die "降级失败（可能需要先 apt-get update）"

say "3) 清理本项目专属包"
for p in cosmic-desktop-extras cosmic-icons cosmic-wallpapers; do
  dpkg -l "$p" >/dev/null 2>&1 && dpkg -r "$p" && ok "已移除 $p"
done

say "完成"
echo "  请注销并重新登录；如需恢复 1.10.0 原生包，重新运行 40-package.sh + 50-install.sh"
