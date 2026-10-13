#!/usr/bin/env bash
# cosmic-loongarch · 40-sysext：校验并报告 sysext 产物（只读）
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
source "$(dirname "$(readlink -f "$0")")/lib/common.sh"

S="$BUILD_DIR/cosmic-sysext"
[ -d "$S" ] || die "未找到 $S（先执行 30-build.sh）"

log "产物：$S（$(du -sh "$S" | cut -f1)）"
meta="$S/usr/lib/extension-release.d/extension-release.cosmic-sysext"
[ -f "$meta" ] || die "缺少扩展元数据 $meta"
ok "元数据："; sed 's/^/    /' "$meta"

have_id="$( . /etc/os-release 2>/dev/null; printf '%s' "${ID:-}" )"
have_ver="$( . /etc/os-release 2>/dev/null; printf '%s' "${VERSION_ID:-}" )"
meta_id="$(awk -F= '/^ID=/{gsub(/"/,"",$2); print $2}' "$meta")"
meta_ver="$(awk -F= '/^VERSION_ID=/{gsub(/"/,"",$2); print $2}' "$meta")"
[ "$meta_id" = "$have_id" ] && [ "$meta_ver" = "$have_ver" ] \
  && ok "元数据与本机匹配（$have_id $have_ver）" \
  || warn "元数据（$meta_id $meta_ver）与本机（$have_id $have_ver）不一致：systemd-sysext 可能拒绝合并"

for b in cosmic-comp cosmic-session cosmic-panel cosmic-settings cosmic-bg; do
  [ -f "$S/usr/bin/$b" ] && ok "存在 usr/bin/$b" || warn "缺少 usr/bin/$b"
done
[ -f "$S/usr/share/wayland-sessions/cosmic.desktop" ] && ok "会话文件 cosmic.desktop" || warn "缺少会话文件"
n_missing=$(ldd "$S/usr/bin/cosmic-comp" 2>/dev/null | grep -c 'not found' || true)
[ "${n_missing:-0}" = "0" ] && ok "cosmic-comp 动态库无缺失" || warn "cosmic-comp 缺失 $n_missing 个动态库"
strings -a "$S/usr/bin/cosmic-comp" 2>/dev/null | grep -q zwp_input_method_manager_v2 \
  && ok "输入法协议 zwp_input_method_manager_v2 存在" || warn "未在二进制中发现输入法协议字符串"

log "离线校验（systemd-sysext --root）"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/var/lib/extensions"
ln -s "$S" "$TMP/var/lib/extensions/cosmic-sysext" 2>/dev/null || cp -a "$S" "$TMP/var/lib/extensions/"
systemd-sysext --root="$TMP" list 2>/dev/null | sed 's/^/    /' || warn "离线校验失败（不影响安装，但值得检查）"

state_set last-sysext "$(date -Iseconds)"
ok "40-sysext 完成：可用 50-install.sh 安装"
