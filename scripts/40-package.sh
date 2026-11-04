#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0
#
# 40-package.sh — 把构建产物打成原生 .deb 软件包（替代旧的 sysext 方案）
#
# 与发行版包共存的设计：
#   · 包名沿用发行版（cosmic-* / pop-launcher / xdg-desktop-portal-cosmic），
#     版本号用上游 epoch 版本（如 1.10.0）。dpkg 版本比较 1.10.0 > 1.0.14，
#     所以 `dpkg -i` 就是"升级替换"，不产生文件冲突、不破坏包管理器。
#   · 每包只含该组件的二进制 + 必要数据文件；**不镜像发行版包中的 doc/license/man**
#     （几千个文件，曾一次写出 62 GB 垃圾）。
#   · 带补丁的组件（默认 cosmic-comp）用构建树里打过补丁的二进制覆盖。
#   · pop-launcher 插件做并集合并（避免升级时丢失发行版自带插件）。
#
# 用法：
#   ./scripts/40-package.sh [--version 1.10.0] [--out DIR] [--no-icons]
#
# 输入：<build-dir>/cosmic-sysext/usr（由 30-build.sh 的 `just sysext` 产出）
# 输出：out/debs/*.deb
set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$HERE/.." && pwd)
if [ -t 1 ]; then c_red=$'\033[31m'; c_grn=$'\033[32m'; c_yel=$'\033[33m'; c_off=$'\033[0m'
else c_red=; c_grn=; c_yel=; c_off=; fi
say()  { printf '\n%s== %s%s\n' "$c_off" "$*" "$c_off"; }
ok()   { printf '%s[+]%s %s\n' "$c_grn" "$c_off" "$*"; }
warn() { printf '%s[!]%s %s\n' "$c_yel" "$c_off" "$*" >&2; }
die()  { printf '%s[x]%s %s\n' "$c_red" "$c_off" "$*" >&2; exit 1; }

VERSION="1.10.0"
OUT_DIR="$REPO_ROOT/out/debs"
WITH_ICONS=1
while [ $# -gt 0 ]; do
    case "$1" in
        --version) VERSION="$2"; shift 2 ;;
        --out)     OUT_DIR="$2"; shift 2 ;;
        --no-icons) WITH_ICONS=0; shift ;;
        -h|--help) sed -n '2,22p' "$0"; exit 0 ;;
        *) die "未知参数: $1" ;;
    esac
done

BUILD_DIR="${COSMIC_BUILD_DIR:-}"
[ -z "$BUILD_DIR" ] && BUILD_DIR=$(cat "$REPO_ROOT/state/build-dir" 2>/dev/null)
[ -z "$BUILD_DIR" ] && die "未设置构建目录：写入 state/build-dir 或设置 COSMIC_BUILD_DIR"
SX="$BUILD_DIR/cosmic-sysext"
[ -d "$SX/usr/bin" ] || die "缺少 $SX/usr/bin（先运行 30-build.sh）"
command -v dpkg-deb >/dev/null || die "缺少 dpkg-deb"

STAGE="$REPO_ROOT/out/stage"
rm -rf "$OUT_DIR" "$STAGE"; mkdir -p "$OUT_DIR" "$STAGE"

declare -A BINS=(
    [cosmic-comp]="cosmic-comp"
    [cosmic-panel]="cosmic-panel"
    [cosmic-settings]="cosmic-settings"
    [cosmic-settings-daemon]="cosmic-settings-daemon"
    [cosmic-session]="cosmic-session start-cosmic"
    [cosmic-applets]="cosmic-applets cosmic-files-applet cosmic-files-thumbnailer"
    [cosmic-app-library]="cosmic-app-library"
    [cosmic-bg]="cosmic-bg"
    [cosmic-edit]="cosmic-edit cosmic-viewer"
    [cosmic-files]="cosmic-files"
    [cosmic-greeter]="cosmic-greeter cosmic-greeter-daemon cosmic-greeter-start"
    [cosmic-idle]="cosmic-idle"
    [cosmic-initial-setup]="cosmic-initial-setup"
    [cosmic-launcher]="cosmic-launcher"
    [cosmic-notifications]="cosmic-notifications"
    [cosmic-osd]="cosmic-osd"
    [cosmic-player]="cosmic-player"
    [cosmic-randr]="cosmic-randr"
    [cosmic-screenshot]="cosmic-screenshot"
    [cosmic-store]="cosmic-store"
    [cosmic-term]="cosmic-term"
    [cosmic-workspaces]="cosmic-workspaces"
    [xdg-desktop-portal-cosmic]="xdg-desktop-portal-cosmic"
)
declare -A COUNT
add_file() {
    local pkg=$1 rel=$2
    mkdir -p "$STAGE/$pkg/$(dirname "$rel")"
    cp -a "$SX/$rel" "$STAGE/$pkg/$rel" 2>/dev/null || return 1
    COUNT[$pkg]=$(( ${COUNT[$pkg]:-0} + 1 ))
}

say "1) 二进制"
for f in "$SX"/usr/bin/*; do
    [ -f "$f" ] || continue
    b=$(basename "$f"); pkg=""
    # pop-launcher 有专门处理（含插件并集），跳过通用映射避免重复打包
    [ "$b" = "pop-launcher" ] && continue
    for p in "${!BINS[@]}"; do
        for x in ${BINS[$p]}; do [ "$x" = "$b" ] && { pkg=$p; break 2; }; done
    done
    [ -z "$pkg" ] && pkg=cosmic-desktop-extras
    add_file "$pkg" "usr/bin/$b" || warn "复制失败: $b"
done
for f in "$SX"/usr/libexec/*; do
    [ -f "$f" ] || continue
    add_file xdg-desktop-portal-cosmic "usr/libexec/$(basename "$f")" || warn "复制失败: $(basename "$f")"
done

say "2) 补丁二进制覆盖"
for repo in ${PATCHED_REPOS:-cosmic-comp}; do
    bin="$BUILD_DIR/$repo/target/release/$repo"
    if [ -x "$bin" ] && [ -d "$STAGE/$repo" ]; then
        cp -f "$bin" "$STAGE/$repo/usr/bin/$repo" && ok "使用带补丁的 $repo"
    fi
done

say "3) 桌面/服务/图标数据"
mapfile -t DATA < <(for d in usr/share/wayland-sessions usr/share/xdg-desktop-portal \
    usr/share/applications usr/share/dbus-1 usr/share/polkit-1 usr/lib/systemd \
    usr/share/cosmic usr/share/cosmic-themes usr/share/cosmic-layouts usr/share/metainfo; do
    [ -d "$SX/$d" ] && find "$SX/$d" -type f 2>/dev/null
done)
if [ "${#DATA[@]}" -gt 0 ] && command -v dpkg >/dev/null; then
    declare -A OWNER
    args=(); for f in "${DATA[@]}"; do args+=("/${f#"$SX"/}"); done
    while IFS= read -r line; do
        pkg="${line%%:*}"; paths="${line#*: }"
        for p in $paths; do OWNER["$p"]="$pkg"; done
    done < <(dpkg -S "${args[@]}" 2>/dev/null)
    for f in "${DATA[@]}"; do
        rel="${f#"$SX"/}"; owner="${OWNER[/$rel]:-}"
        case "$owner" in
            cosmic-*|xdg-desktop-portal-cosmic) add_file "$owner" "$rel" || true ;;
            *) case "$rel" in
                   usr/share/wayland-sessions/*) add_file cosmic-session "$rel" || true ;;
                   usr/share/xdg-desktop-portal/*) add_file xdg-desktop-portal-cosmic "$rel" || true ;;
               esac ;;
        esac
    done
fi
for d in com.system76.CosmicMonitor.desktop com.system76.CosmicViewer.desktop \
         com.system76.CosmicAppletOsk.desktop; do
    [ -f "$SX/usr/share/applications/$d" ] && add_file cosmic-desktop-extras "usr/share/applications/$d"
done
if [ "$WITH_ICONS" = 1 ]; then
    for src in "$SX/usr/share/icons/Cosmic" "$SX/usr/share/icons/hicolor"; do
        [ -d "$src" ] || continue
        mkdir -p "$STAGE/cosmic-icons/usr/share/icons"
        cp -a "$src" "$STAGE/cosmic-icons/usr/share/icons/" 2>/dev/null || true
    done
    [ -d "$SX/usr/share/backgrounds" ] && {
        mkdir -p "$STAGE/cosmic-wallpapers/usr/share"
        cp -a "$SX/usr/share/backgrounds" "$STAGE/cosmic-wallpapers/usr/share/" 2>/dev/null || true
    }
fi
PL_DST="$STAGE/pop-launcher/usr/lib/pop-launcher"
mkdir -p "$PL_DST"
[ -d /usr/lib/pop-launcher ] && cp -a /usr/lib/pop-launcher/. "$PL_DST/" 2>/dev/null
[ -d "$SX/usr/lib/pop-launcher" ] && cp -a "$SX/usr/lib/pop-launcher/." "$PL_DST/" 2>/dev/null
[ -x "$SX/usr/bin/pop-launcher" ] && add_file pop-launcher "usr/bin/pop-launcher"

say "4) 生成 .deb（版本 $VERSION）"
# 遍历 staging 目录而不是 COUNT（数据包 cosmic-icons/wallpapers 不走 add_file）
for pkg in $(ls "$STAGE" 2>/dev/null); do
    [ -d "$STAGE/$pkg" ] || continue
    sd="$STAGE/$pkg"; mkdir -p "$sd/DEBIAN"
    deps=""; command -v dpkg >/dev/null && deps=$(dpkg -s "$pkg" 2>/dev/null | sed -n 's/^Depends: //p' | head -1)
    arch=loongarch64
    case "$pkg" in cosmic-icons|cosmic-wallpapers) arch=all ;; esac
    {
        echo "Package: $pkg"
        echo "Version: $VERSION"
        echo "Architecture: $arch"
        echo "Maintainer: ${PACKAGE_MAINTAINER:-cosmic-loongarch <noreply@example.com>}"
        echo "Installed-Size: $(du -sk "$sd" | cut -f1)"
        echo "Depends: ${deps:-}"
        echo "Section: COSMIC"
        echo "Priority: optional"
        echo "Description: COSMIC component (epoch $VERSION, local build)"
        echo " Built from upstream cosmic-epoch $VERSION sources by cosmic-loongarch."
    } > "$sd/DEBIAN/control"
    if dpkg-deb --root-owner-group -Zxz --build "$sd" "$OUT_DIR/${pkg}_${VERSION}_${arch}.deb" >/dev/null 2>&1; then
        ok "$(printf '%-30s %-12s %4s 文件' "$pkg" "$VERSION" "${COUNT[$pkg]:-0}")"
    else
        warn "打包失败: $pkg"
    fi
done

say "完成"
echo "  输出: $OUT_DIR（$(ls "$OUT_DIR"/*.deb 2>/dev/null | wc -l) 个包，$(du -sh "$OUT_DIR" 2>/dev/null | cut -f1)）"
echo "  下一步: sudo ./scripts/50-install.sh"
