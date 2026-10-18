# 变更记录

本仓库只分发**补丁与脚本**，版本以「Iteration」划分；每个补丁的动机、分级、证据见 `patches/` 与 `docs/KNOWN-ISSUES.md`。

## Iteration 2 — 2026-10-19

### 安装方式：systemd-sysext → 原生 .deb

实测发现 AOSC 仓库中的 COSMIC 为 **epoch 1.0.x**（包版本 `1.0.14` 是 crate 版本，不是 epoch 1.10），
systemd-sysext 方案会让 `/usr` 变成只读叠加层、`oma install` 全部失败（"只读文件系统"）。
改为把构建产物打成**同名本地包**（`cosmic-*`，版本 `1.10.0`），`dpkg` 以升级方式安装：

- `scripts/40-package.sh`（新，替代 `40-sysext.sh`）：按组件拆包；带补丁的二进制自动覆盖；
  图标/壁纸/额外桌面条目/launcher 插件并集合并；**不镜像**发行版的 doc/license（曾一次写出 62 GB）
- `scripts/50-install.sh`：`dpkg --dry-run` 预检 → `dpkg -i` → 图标/桌面缓存刷新
- `scripts/60-verify.sh`：包版本、构建产物逐字节比对（补丁组件查特征串）、`/usr` 可写性、无 sysext
- `scripts/99-uninstall.sh`：`--allow-downgrades` 重装回发行版版本
- `state/{epoch-version,build-dir}` 记录目标版本与构建目录

### 验证结果（LoongArch / AOSC OS 14）

- 37 个包全部 `1.10.x`；47/47 构建产物二进制已安装，46 个逐字节一致
- `cosmic-comp` = `1.10.0+cosmic-loongarch1`（含 0001 补丁；`strings` 特征串校验）
- 外观 → 样式页出现磨砂设置（1.10 才有的 UI）；主题/图标/壁纸均为 1.10 资源
- `/usr` 可写、`oma`/`dpkg` 正常

### 问题记录

| 编号 | 内容 | 结果 |
|---|---|---|
| K-013 | 发行版包版本号 `1.0.14` ≠ epoch 1.10（版本号陷阱）| 用「同名包 + 更高版本」规避，见 `docs/NATIVE-PACKAGING.md` |
| K-014 | 升级包若缺少旧包内的文件（如 applet 二进制、桌面条目），dpkg 会删除它们 | 40-package.sh 按组件收集二进制 + 白名单数据，并对 pop-launcher 插件做并集 |

## Iteration 1 — 2026-10-13

### 新增补丁

- **0001 `animations-enabled-and-speed`**（cosmic-comp，`upstreamable`）
  动画开关 `enabled` + 时长倍率 `speed`；补上游 PR 缺失的 `#[serde(default)]`；新增 `src/animations.rs` 全局。
  依据上游 issue #376 / PR #2209（均未合并）。已编译、已部署、真机验证。

### 工程化

- `scripts/20-apply.sh`：`--revert` 增加新增文件清理（`reset` + `checkout` + `clean -fdq`）
- `tests/smoke.sh`：构建目录解析改为「环境变量 → `state/build-dir` → 默认值」；容忍"已记录补丁"状态
- 新增实机截图 `docs/images/cosmic-1.10.0-on-loongarch-aosc.png`（README「截图」章节、TESTING §0）
- `docs/REPO-METADATA.md` 的 Social preview 指向该截图

### 问题记录（`docs/KNOWN-ISSUES.md`）

| 编号 | 内容 | 结果 |
|---|---|---|
| K-005 | 环境串味会让 `cosmic-comp` 误选 winit 后端，**会话直接起不来** | 已归档清环境清单 |
| K-009 | System Monitor 列表中文豆腐块（脚本回退未生效）| 已定性；上游无同类 issue，可新报 |
| K-010 | 磨砂玻璃的 GPU 成本（上游视为预期限制）| 成本模型 + 缓解手段 |
| K-011 | 主题配置缺 `list_button`/`accent_text`/`window_hint` → 回退暗色 | 已修复（明暗两套均补齐，加载错误归零）|
| K-012 | 任务栏不显示 XWayland 应用的窗口图标（`_NET_WM_ICON` 未被消费）| 已定性；上游 cosmic-applets #1464 跟踪；可用桌面文件绕过 |

### 协作约定

- `docs/UPSTREAMING.md` 增加红线：不与上游交换 AI 生成内容；上游沟通只用本人话语 + 本机真实数据 + 最小复现。

## Iteration 0 — 2026-10-13

- 初始化仓库骨架：`upstream.lock`（31 条 pin）、`00-deps`→`60-verify`/`99-uninstall` 幂等流水线、
  `docs/`（BUILD/TESTING/KNOWN-ISSUES/PERFORMANCE/UPSTREAMING/REPO-METADATA）、`tests/`、`patches/` 模板与三级分级。
