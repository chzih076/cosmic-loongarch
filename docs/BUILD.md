# 构建指南（BUILD）

> 目标平台：**LoongArch64 + AOSC OS**（其它发行版思路相同，依赖包名可能不同）
> 本仓库只提供补丁与脚本；**上游源码由本流程从官方渠道获取**。

## 0. 前置检查

```bash
./scripts/00-deps.sh --check     # 只体检，不改系统
./scripts/00-deps.sh             # 缺什么补什么（libseat 会从官方源码编译，需要 sudo）
```

需要：`git`、`rustc/cargo`（或 rustup）、`just`、`meson` + `ninja`、`cmake`、`pkg-config`、`sed/awk`、`systemd-sysext`。
运行期还需要：`libxkbcommon`、`libinput`、`libdrm`、`gbm`、`wayland`、`libdisplay-info`、`pipewire`、`NetworkManager`、`accountsservice`、`upower-glib`（AOSC 默认已具备）。

## 1. 环境变量（都可覆盖）

| 变量 | 默认 | 作用 |
|---|---|---|
| `COSMIC_BUILD_DIR` | `$HOME/cosmic-build` | 上游源码与构建产物目录（**建议放在大容量盘**，产物约 37 GB）|
| `GH_PROXY` | 空 | 上游镜像/代理前缀，例如 `https://v6.gh-proxy.org/https://github.com`（网络受限时使用）|
| `CARGO_BUILD_JOBS` | `8` | 并发编译数（防 15 GB 内存被 24 并发打爆）|
| `PKG_CONFIG_PATH` | 自动追加 `/usr/local/lib/pkgconfig` | **必须**：libseat 装在 `/usr/local`（见 K-001）|
| `TURBOJPEG_SOURCE` | `pkg-config` | **必须**：绕开 libjpeg-turbo 对 loongarch64 的 SIMD 拒绝（见 K-002）|
| `RUSTC_WRAPPER` / `SCCACHE_DIR` | sccache / `~/.cache/sccache` | 跨组件编译缓存，重复构建提速明显 |
| `SCCACHE_MAXSIZE` | `20G` | 缓存上限 |

以上除前两个外，`scripts/30-build.sh` 都会自动导出，一般无需手工设置。

## 2. 流水线

| 脚本 | 作用 | 幂等性 / 参数 |
|---|---|---|
| `00-deps.sh` | 依赖体检；缺 libseat 时从官方源码编译并安装（logind 后端，无需 seatd 守护进程）| `--check` 只体检；`--yes` 跳过确认 |
| `10-fetch.sh` | 按 `upstream.lock` 获取上游：缺失则克隆，存在则**只校验**（不联网）；`--update` 才增量 fetch 并切到 lock 的 commit | `--check`（仅校验）、`--update`、`--lock`（由现有树重新生成 lock）|
| `20-apply.sh` | 对每个仓库应用 `patches/<repo>/*.patch` | `--check` 预演、`--list` 列出、`--revert` 撤销（`git checkout -- .`）|
| `30-build.sh` | `just sysext`（含全部环境变量与缓存设置）；完成后校验产物 | `--jobs N`、`--slim`（清理各 target/ 释放约 37 GB）|
| `40-sysext.sh` | 定位并校验 `cosmic-sysext/`（元数据 + 离线 `systemd-sysext --root` 校验），输出路径与校验和 | 只读检查 |
| `50-install.sh` | 复制到 `/var/lib/extensions/` 并 `systemctl start systemd-sysext`（**不改系统文件**）| `--yes` |
| `60-verify.sh` | 冒烟验证：扩展已合并、会话文件、关键二进制与动态库、协议字符串、输入法协议 | `--rebind-ime` 重绑 fcitx5；`--report` 输出报告 |
| `99-uninstall.sh` | 停止并移除扩展；必要时重启登录管理器 | `--yes` |

## 3. 关键坑（必读）

- **K-001 libseat 的 pkg-config 路径** → 不设置会在第 1 个组件就构建失败；
- **K-002 libjpeg-turbo 拒绝 loongarch64** → 不设置会在第 26 个组件（cosmic-viewer）失败。

两条都已内置到 `30-build.sh`；详细原理与证据见 [`KNOWN-ISSUES.md`](KNOWN-ISSUES.md)。

## 4. 耗时与磁盘

| 项 | 数值 |
|---|---|
| 首次构建 | 约 1.5–4 小时（30 个组件各自编译；公共依赖会被重复编译——上游 justfile 的设计如此）|
| 使用 sccache 后 | 重复构建显著加快（历史命中率约 25%，后续构建更高）|
| 上游源码 + git | 约 1.2 GB（其中全历史 git 约 110 MB）|
| 各组件 `target/` | 合计约 **37 GB**（`30-build.sh --slim` 可清理）|
| 产物 `cosmic-sysext/` | 约 1.1 GB |

## 5. 安装方式与回滚

```bash
./scripts/50-install.sh      # 放入 /var/lib/extensions 并合并（/usr 变为只读叠加层）
# 进入 COSMIC：
#   A) 登录管理器里选 "COSMIC"（需先重启 greeter，或在已合并后重启系统）
#   B) 或从 TTY：Ctrl+Alt+F3 登录后执行 start-cosmic（可与 KDE 会话并存，Ctrl+Alt+F2 返回）
./scripts/99-uninstall.sh    # 一键摘除，回到原桌面
```

> ⚠️ sysext 生效期间 `/usr`、`/opt` 为只读叠加层，**不要用包管理器装/升级软件**；需要装包先 `99-uninstall.sh`。

## 6. 排障速查

```bash
tail -f "$COSMIC_BUILD_DIR/build.log"                       # 构建日志（30-build.sh 写入）
systemd-sysext status                                       # 扩展合并状态
journalctl -b | grep -iE 'cosmic|input.?method' | tail -50  # 会话日志
coredumpctl list --since '-30min'                           # 崩溃记录
sudo coredumpctl info <PID> | tail -30                      # 崩溃线程栈（定位到具体库）
ldd /usr/bin/cosmic-comp | grep 'not found'                 # 动态库缺失
```
