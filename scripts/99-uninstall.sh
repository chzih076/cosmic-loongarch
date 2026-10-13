#!/usr/bin/env bash
# cosmic-loongarch · 99-uninstall：摘除 sysext，回到原桌面
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

for a in "$@"; do case "$a" in
  --yes|-y) ASSUME_YES=1; export ASSUME_YES;;
  -h|--help) echo "用法: $0 [--yes]"; exit 0;;
  *) die "未知参数: $a";; esac; done

log "停止并移除 sysext"
sudo_run systemctl stop systemd-sysext 2>/dev/null || true
sudo_run rm -rf /var/lib/extensions/cosmic-sysext
state_set uninstalled-at "$(date -Iseconds)"
ok "已移除（若 /usr 仍为只读叠加，重启一次即可完全恢复）"
cat <<'MSG'
如需立刻恢复登录界面：sudo systemctl restart plasmalogin（会结束当前图形会话，注意保存工作）
MSG
