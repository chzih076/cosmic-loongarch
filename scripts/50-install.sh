#!/usr/bin/env bash
# cosmic-loongarch · 50-install：安装到 /var/lib/extensions 并合并（systemd-sysext）
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

for a in "$@"; do case "$a" in
  --yes|-y) ASSUME_YES=1; export ASSUME_YES;;
  -h|--help) echo "用法: $0 [--yes]"; exit 0;;
  *) die "未知参数: $a";; esac; done

S="$BUILD_DIR/cosmic-sysext"; DST=/var/lib/extensions/cosmic-sysext
[ -d "$S" ] || die "未找到 $S（先 30-build.sh / 40-sysext.sh）"
require_cmd systemd-sysext

log "安装 $S → $DST（目录名不可改，systemd 依赖命名）"
sudo_run mkdir -p /var/lib/extensions
sudo_run rm -rf "$DST"
sudo_run cp -a "$S" "$DST"
sudo_run systemctl start systemd-sysext
systemd-sysext status 2>/dev/null | sed 's/^/    /' || true
systemd-sysext status 2>/dev/null | grep -q cosmic-sysext && ok "扩展已合并" || warn "未看到扩展合并"

state_set installed-at "$(date -Iseconds)"
state_set installed-sha "$(git -C "$BUILD_DIR" rev-parse HEAD 2>/dev/null || echo unknown)"
cat <<'MSG'

下一步（二选一）：
  A) 登录管理器：重启 greeter（如 sudo systemctl restart plasmalogin）后，登录界面会列出 COSMIC
  B) 不打断当前会话：Ctrl+Alt+F3 → 登录 → 运行 start-cosmic（Ctrl+Alt+F2 可返回原桌面）
提示：sysext 生效期间 /usr、/opt 为只读叠加层，请勿用包管理器装包；卸载见 99-uninstall.sh
MSG
