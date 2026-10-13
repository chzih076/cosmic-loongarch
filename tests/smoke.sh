#!/usr/bin/env bash
# cosmic-loongarch · 冒烟测试（只读，不改变系统状态）
# 用法: COSMIC_BUILD_DIR=<上游构建树> ./tests/smoke.sh
# SPDX-License-Identifier: GPL-3.0
set -euo pipefail
REPO_ROOT="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
BUILD_DIR="${COSMIC_BUILD_DIR:-$HOME/cosmic-build}"

echo "== cosmic-loongarch smoke test =="
echo "仓库:   $REPO_ROOT"
echo "构建树: $BUILD_DIR"
echo

fail=0
chk() { if eval "$2" >/dev/null 2>&1; then printf '  ✅ %s\n' "$1"; else printf '  ❌ %s\n' "$1"; fail=$((fail+1)); fi; }

chk "upstream.lock 可解析（含 cosmic-epoch）" "grep -q '^cosmic-epoch ' '$REPO_ROOT/upstream.lock'"
chk "upstream.lock 条目数 > 20" "[ \$(grep -vc '^#' '$REPO_ROOT/upstream.lock') -gt 20 ]"
chk "构建树存在且是 git 仓库" "[ -d '$BUILD_DIR/.git' ]"
chk "构建树 commit 与 lock 一致" "[ \"\$(git -C '$BUILD_DIR' rev-parse HEAD)\" = \"\$(awk '/^cosmic-epoch /{print \$2}' '$REPO_ROOT/upstream.lock')\" ]"
chk "构建树工作区干净（补丁已记录或未应用）" "[ -z \"\$(git -C '$BUILD_DIR' status --porcelain --untracked-files=no)\" ]"
chk "sysext 产物存在" "[ -d '$BUILD_DIR/cosmic-sysext' ]"
chk "扩展元数据存在" "[ -f '$BUILD_DIR/cosmic-sysext/usr/lib/extension-release.d/extension-release.cosmic-sysext' ]"
chk "关键二进制存在" "[ -x '$BUILD_DIR/cosmic-sysext/usr/bin/cosmic-comp' ]"
chk "会话文件存在" "[ -f '$BUILD_DIR/cosmic-sysext/usr/share/wayland-sessions/cosmic.desktop' ]"
chk "cosmic-comp 无缺失动态库" "[ \$(ldd '$BUILD_DIR/cosmic-sysext/usr/bin/cosmic-comp' 2>/dev/null | grep -c 'not found') -eq 0 ]"
chk "二进制含输入法协议" "strings -a '$BUILD_DIR/cosmic-sysext/usr/bin/cosmic-comp' | grep -q zwp_input_method_manager_v2"
chk "全部脚本语法正确" "for f in '$REPO_ROOT'/scripts/*.sh '$REPO_ROOT'/scripts/lib/*.sh; do bash -n \"\$f\"; done"
chk "全部补丁可被 git apply 解析（--check）" "for p in '$REPO_ROOT'/patches/*/*.patch; do [ -e \"\$p\" ] || continue; grep -q '^--- ' \"\$p\"; done"

echo
if [ "$fail" -eq 0 ]; then echo "结果: 全部通过 ✅"; else echo "结果: $fail 项失败 ❌"; exit 1; fi
