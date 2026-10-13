# cosmic-loongarch · COSMIC 桌面龙芯适配补丁集

只分发补丁与脚本，不含上游源码——COSMIC 本体请从官方渠道获取。目标：不止能用，还要好用。

面向 AOSC OS / LoongArch64：
① 构建修复：libseat 的 pkg-config 路径、libjpeg-turbo 不支持 loongarch64；
② 运行改进：动画开关与速度倍率（#376）、renderD128 跨节点纹理花屏、环境串味、fcitx5 重绑；
③ 工程化：upstream.lock 锁定 cosmic-epoch 与 30 子模块 SHA；00-deps→60-verify 幂等流水线（打补丁/构建/打包 sysext/冒烟/回滚）。

补丁分 upstreamable / loongarch-only / local-hack 三级，注明动机与上游 issue。已在 Loongson-3B6000 + AOSC OS 14 + RX 7650 GRE 验证，不影响 KDE、随时可摘。

---

## 这是什么

一个**下游补丁与构建流水线**，让 [COSMIC Desktop](https://github.com/pop-os/cosmic-epoch)（System76 用 Rust 写的桌面环境）在 **LoongArch64 / AOSC OS** 上跑得可用、进而好用。

**分发边界（重要）**：

- 本仓库**只包含补丁、脚本与文档**，**不包含也不分发** COSMIC 上游源码；
- 上游源码由使用者从**官方渠道**获取（见 `upstream.lock` 中的 URL；也可自配镜像/代理）；
- 本仓库与 System76 / Pop!_OS / COSMIC 上游**无隶属关系**，属社区非官方适配。

## 目录结构

```
upstream.lock              锁定 cosmic-epoch 与全部子模块的精确 commit（可复现构建的根）
patches/                   本仓库的"产品"：按上游仓库分目录，三级分类，逐条注明动机与证据
scripts/                   00-deps → 10-fetch → 20-apply → 30-build → 40-sysext → 50-install → 60-verify → 99-uninstall
docs/                      BUILD / TESTING / KNOWN-ISSUES / PERFORMANCE / UPSTREAMING / REPO-METADATA
tests/                     smoke.sh（自动冒烟）+ manual-checklist.md（人工验收清单）
state/                     本机状态记录（已应用补丁、已装 sysext 版本、上次构建的上游 SHA）
```

## 快速开始

```bash
git clone <本仓库> && cd cosmic-loongarch

./scripts/00-deps.sh          # 依赖体检 + 编译 libseat（logind 后端，来自官方 seatd）
./scripts/10-fetch.sh         # 按 upstream.lock 获取上游源码到你指定的构建目录
./scripts/20-apply.sh         # 应用补丁（幂等；--check 只预演，--revert 撤销）
./scripts/30-build.sh         # 构建（sccache + 并发控制 + loongarch64 必要环境变量）
./scripts/40-sysext.sh        # 打包 systemd-sysext 并做离线校验
./scripts/50-install.sh       # 安装并启用（systemd-sysext，随时可回滚）
./scripts/60-verify.sh        # 冒烟验证
./scripts/99-uninstall.sh     # 一键回滚到原桌面
```

构建目录、镜像/代理等均可通过环境变量覆盖，见 `docs/BUILD.md`。

## 设计原则

| 原则 | 说明 |
|---|---|
| **只发补丁** | 仓库几百 KB，可审计、可发布；不背上游包袱 |
| **锁死上游** | `upstream.lock` 记录 cosmic-epoch 与 30 个子模块的精确 commit，构建可复现 |
| **幂等脚本** | 每个脚本可重复执行；`10-fetch.sh` 默认**不联网**（仅校验 lock），只有 `--update` 才增量拉取 |
| **补丁分级** | `upstreamable` / `loongarch-only` / `local-hack`，每条标注动机、上游 issue 与测试证据、回退条件 |
| **零风险试用** | 用 systemd-sysext 安装，不替换系统文件；`99-uninstall.sh` 一键摘除 |
| **可验证** | 改动都要有证据：journal / coredumpctl 栈 / 设备号解码 / 性能数字，写进补丁说明 |

## 补丁清单

| 编号 | 目标仓库 | 标题 | 分级 | 上游状态 | 说明 |
|---|---|---|---|---|---|
| 0001 | cosmic-comp | 动画开关与速度倍率 | `upstreamable` | 参考 [#376](https://github.com/pop-os/cosmic-comp/issues/376) / PR [#2209](https://github.com/pop-os/cosmic-comp/pull/2209)（未合并）| `animations = (enabled, speed)`；补 `#[serde(default)]`；新增 `src/animations.rs` 全局。配置热生效 |
| 0002 | cosmic-comp | DMABUF 跨渲染节点纹理导入（花屏）| 待定 | — | 见 `docs/KNOWN-ISSUES.md` K-003（规划中）|
| 0004 | — | *(K-010 磨砂效率：已知限制，暂不做补丁)* | — | 上游 #2650 / #2795 | 记录见 `docs/KNOWN-ISSUES.md` |
| 0003 | libcosmic/iced | 表格控件文本缺中文脚本回退（System Monitor 豆腐块）| 待评估 | — | 见 `docs/KNOWN-ISSUES.md` K-009（需 vendoring libcosmic）|

## 已知问题

见 [`docs/KNOWN-ISSUES.md`](docs/KNOWN-ISSUES.md)：收录构建期与运行期的实测问题（含证据与规避方式）。

## 已验证平台

| 项 | 值 |
|---|---|
| CPU / 架构 | Loongson-3B6000 (12C/24T @2.2GHz) / loongarch64 |
| 系统 | AOSC OS 14.0.0，内核 7.1.13，systemd |
| 显卡 / 驱动 | AMD RX 7650 GRE（RADV / Mesa 26.1.5）|
| 会话 | KDE Plasma (Wayland) 并存；COSMIC 以 systemd-sysext 方式启用 |
| 输入法 | fcitx5 + RIME（cosmic-comp 支持 `zwp_input_method_v2`）|

## 署名与贡献

- 维护者：**chzih076**；提交身份 `chzih076 <chzih076@users.noreply.github.com>`（仓库级 git 配置，不污染其它项目）；
- 提交规范：每条补丁与提交需带 `Signed-off-by`（DCO）；补丁头部注明 `Upstream:` / `Grade:` / `Issue:` / `Evidence:`；
- 若提交使用了大模型辅助，须在 commit message 中**如实声明**（遵循上游 COSMIC 的 PR 要求）；
- 详细流程见 [`docs/UPSTREAMING.md`](docs/UPSTREAMING.md) 与 [`patches/README.md`](patches/README.md)。

## 许可

- 本仓库的补丁与脚本：**GPL-3.0**（与上游 COSMIC 同许可，补丁作为衍生作品沿用）；见 [`LICENSE`](LICENSE)；
- 上游项目及其许可署名见 [`NOTICE`](NOTICE)；
- 本仓库不含上游源码，也不对上游代码做再分发。
