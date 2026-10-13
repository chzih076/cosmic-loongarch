#!/usr/bin/env bash
# cosmic-loongarch · 60-verify：冒烟验证（只读）+ 可选重绑输入法
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

REBIND=0; REPORT=0
for a in "$@"; do case "$a" in
  --rebind-ime) REBIND=1;; --report) REPORT=1;;
  -h|--help) echo "用法: $0 [--rebind-ime] [--report]"; exit 0;;
  *) die "未知参数: $a";; esac; done

OUT="$(mktemp)"; exec > >(tee "$OUT") 2>&1
log "== 冒烟验证 $(date -Iseconds) =="

# 1) lock 与构建树一致
if [ -d "$BUILD_DIR/.git" ]; then
  "$REPO_ROOT/scripts/10-fetch.sh" --check >/dev/null 2>&1 && ok "upstream.lock 与构建树一致" || warn "upstream.lock 与构建树不一致"
else warn "构建树不存在：$BUILD_DIR"; fi

# 2) 补丁状态
"$REPO_ROOT/scripts/20-apply.sh" --check >/dev/null 2>&1 && ok "补丁预演通过" || warn "补丁预演未通过（可能需要解冲突）"
[ -s "$STATE_DIR/patches-applied.txt" ] && { log "已应用补丁："; sed 's/^/    /' "$STATE_DIR/patches-applied.txt"; }

# 3) 产物
S="$BUILD_DIR/cosmic-sysext"
[ -d "$S" ] && ok "产物存在（$(du -sh "$S" | cut -f1)）" || warn "产物不存在"

# 4) 已安装状态
if systemd-sysext status 2>/dev/null | grep -q cosmic-sysext; then
  ok "sysext 已合并到 /usr"
  for b in cosmic-comp cosmic-session cosmic-panel cosmic-settings; do
    [ -x "/usr/bin/$b" ] && printf '    %-20s %s\n' "$b" "$(ldd "/usr/bin/$b" 2>/dev/null | grep -c 'not found') 个缺失库" || warn "缺少 /usr/bin/$b"
  done
  [ -f /usr/share/wayland-sessions/cosmic.desktop ] && ok "登录界面可见 COSMIC 会话" || warn "缺少会话文件"
else warn "sysext 未合并（尚未安装？）"; fi

# 5) 运行中的会话
if pgrep -x cosmic-comp >/dev/null 2>&1; then
  ok "COSMIC 正在运行：$(pgrep -c cosmic) 个 cosmic 进程"
  ps -eo comm,rss | grep -i cosmic | awk '{s+=$2} END{printf "    内存合计 %.0f MB\n", s/1024}'
else log "COSMIC 当前未运行"; fi

# 6) 输入法协议
strings -a "$S/usr/bin/cosmic-comp" 2>/dev/null | grep -q zwp_input_method_manager_v2 \
  && ok "cosmic-comp 支持 zwp_input_method_manager_v2（fcitx5 可用）" || warn "未见输入法协议字符串"

# 7) 可选：重绑 fcitx5
if [ "$REBIND" = "1" ]; then
  if ! command -v fcitx5 >/dev/null 2>&1; then warn "未安装 fcitx5，跳过"; else
    active_kde="$(loginctl show-session 2 -p Active --value 2>/dev/null || true)"
    if [ "$active_kde" = "yes" ]; then WD=wayland-0; DP=:0; WHO=KDE; else WD=wayland-1; DP=:1; WHO=COSMIC; fi
    log "重绑 fcitx5 到活动会话：$WHO（WAYLAND_DISPLAY=$WD）"
    pkill -x fcitx5 2>/dev/null || true; sleep 1
    setsid nohup env XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="$WD" DISPLAY="$DP" \
      GTK_IM_MODULE=fcitx QT_IM_MODULE=fcitx QT5_IM_MODULE=fcitx XMODIFIERS=@im=fcitx \
      DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$(id -u)/bus" fcitx5 -d >/tmp/fcitx5-follow.log 2>&1 &
    sleep 4
    grep -m1 'native input method protocol' /tmp/fcitx5-follow.log 2>/dev/null | sed 's/^/    /' || true
    ok "fcitx5 已重绑（引擎：$(XDG_RUNTIME_DIR=/run/user/$(id -u) fcitx5-remote -n 2>/dev/null || echo '?')）"
  fi
fi

exec >/dev/null 2>&1
printf '%s\n' "---- 报告 ----" >&2
if [ "$REPORT" = "1" ]; then cp "$OUT" "$STATE_DIR/last-verify.txt"; ok "报告已写入 $STATE_DIR/last-verify.txt"; fi
grep -cE '^\[+\]' "$OUT" | sed 's/^/通过项: /' >&2
grep -cE '^\[!\]' "$OUT" | sed 's/^/警告项: /' >&2
