# 已知问题（KNOWN ISSUES）

本文件记录在 **LoongArch64 / AOSC OS** 上实测到的问题。每条都附**证据**与**规避/修补状态**，
格式统一为：现象 → 影响 → 根因 → 规避或修补 → 证据 → 状态。

状态取值：`已内置规避`（脚本里已处理）、`待修（计划补丁）`、`观察中`、`仅记录`。

---

## 构建期

### K-001 · `libseat-sys` 编译失败（libseat 找不到）

- **现象**：`cosmic-comp` 构建时报 `error: failed to run custom build command for 'libseat-sys v0.2.0'`
- **影响**：构建中断（第 1/30 个组件就挂）
- **根因**：libseat 由 `scripts/00-deps.sh` 安装到 `/usr/local`，而 pkg-config 的默认搜索路径只有 `/usr/lib/pkgconfig:/usr/share/pkgconfig`
- **规避**：构建时导出 `PKG_CONFIG_PATH=/usr/local/lib/pkgconfig:$PKG_CONFIG_PATH`（同时补 `LIBRARY_PATH` / `LD_LIBRARY_PATH`）
- **证据**：
  ```
  $ pkg-config --libs libseat
  Package libseat was not found in the pkg-config search path.
  $ PKG_CONFIG_PATH=/usr/local/lib/pkgconfig pkg-config --modversion libseat
  0.9.3
  ```
- **状态**：`已内置规避`（`scripts/30-build.sh`）

### K-002 · libjpeg-turbo 的 CMake 拒绝 loongarch64

- **现象**：`cosmic-viewer` 构建到 `turbojpeg-sys v1.2.0` 时报
  `CMake Error at simd/CMakeLists.txt:3 (message): SIMD extensions not available for this CPU (loongarch64).`
- **影响**：构建中断（第 26/30 个组件）
- **根因**：`turbojpeg-sys` 默认启用 `require-simd` 特性 → build.rs 硬加 `-DREQUIRE_SIMD=ON`；上游 libjpeg-turbo 3.x **没有 loongarch64 的 SIMD 实现**，CMake 因此直接报错
- **规避**：`TURBOJPEG_SOURCE=pkg-config` → 改用系统 `libturbojpeg`（AOSC 已提供 `3.2.0` 与 `/usr/lib/pkgconfig/libturbojpeg.pc`）
- **证据**：构建日志（`turbojpeg-sys` 的 CMake 输出）+ `ldconfig -p | grep turbojpeg`
- **状态**：`已内置规避`（`scripts/30-build.sh`）
- **可上游化**：`turbojpeg-sys` 的 `require-simd` 应有「架构自动检测」或可关闭路径，值得提 issue

---

## 运行期

### K-003 · `renderD128` 跨节点纹理导入失败 → 偶发花屏

- **现象**：`cosmic-comp` 日志反复出现
  `Failed to render texture 0x…, import for wrong devices DrmNode { dev: 57984, ty: Render }? MultiTextureInternal {…}`
- **影响**：偶发花屏/局部不刷新；疑与 K-004 同源
- **根因（已解码）**：`57984 = makedev(226,128) = renderD128`（渲染节点），而本机 KMS 主节点是 `card1 = makedev(226,1)`；
  即**纹理在渲染节点分配、却按主节点导入**（DMABUF 跨节点），本机只有一张卡，属 cosmic-comp 在该配置下的处理问题
- **规避**：暂无；`cosmic-comp` 近期上游提交有相关改动（`backend: dmabuf: ensure primary render node is preffered`）
- **证据**：
  ```
  卡片: /dev/dri/card1 (226,1) amdgpu 0x7480 ; /dev/dri/renderD128 (226,128)
  journal: DrmNode { dev: 57984, ty: Render }
  python: 57984 → major=226 minor=128 → renderD128
  ```
- **状态**：`待修（计划补丁 0002）`

### K-004 · `cosmic-files-applet` 崩溃（tiny_skia）

- **现象**：`cosmic-files-applet exited with error 101`，panic 于 `iced/tiny_skia …`（`Create pixel map`）
- **影响**：桌面图标 applet 短暂消失后由 `cosmic-session` 自动重启；不影响其它组件
- **根因**：疑与 K-003 同源（无有效 pixel map 时仍在合成）
- **证据**：`journalctl` 中 `cosmic-files-applet exited with error 101` + scope 记录 `593.2M memory peak`
- **状态**：`观察中`（若 K-003 修好仍复现，再单独跟）

### K-005 · 从 TTY 启动会话时 KDE 环境变量串味

- **现象**：COSMIC 会话的子进程带着 `KDE_FULL_SESSION=true`、`DESKTOP_SESSION=/usr/share/wayland-sessions/plasma.desktop` 等变量
- **影响**：部分应用误判桌面环境（主题/Qt 平台主题/会话行为异常）
- **根因**：`start-cosmic` 会把当前环境导入 systemd 用户会话；从 TTY 启动时，KDE 先前导入的变量仍在用户级 systemd 环境中
- **规避**：启动 COSMIC 前清理这些变量（或改由登录管理器直接进入 COSMIC，见 `docs/BUILD.md`）
- **证据**：`systemctl --user show-environment | grep -E 'KDE_FULL_SESSION|DESKTOP_SESSION'`
- **状态**：`仅记录`（可脚本化）

### K-006 · 动画参数全部硬编码，无配置项

- **现象**：窗口开关/最小化/工作区切换/tab 滚动等动画时长与曲线均不可调
- **影响**：默认动画偏慢，无法按喜好加速或关闭（社区长期诉求）
- **根因**：`CosmicCompConfig` 中**没有**任何动画键；相关参数是源码常量：
  ```
  shell/layout/floating/mod.rs : ANIMATION_DURATION = 200ms, MINIMIZE_ANIMATION_DURATION = 320ms
  shell/layout/tiling          : ANIMATION_DURATION
  shell/element/stack/tabs.rs  : SCROLL_ANIMATION_DURATION = 200ms, TAB_ANIMATION_DURATION = 150ms
  shell/grabs/moving.rs        : RESCALE_ANIMATION_DURATION = 150.0
  ```
- **上游状态**：issue **#376**（open，社区活跃）；PR **#2209**（open，`mergeable_state: dirty`，最后活动 2026-07-29）
  - #2209 与当前 master 的冲突面：5 文件 7 处（config 结构体 1、`src/config/mod.rs` 1、`backend/render/mod.rs` 1、`shell/workspace.rs` 1、`shell/zoom.rs` 3）
  - #2209 缺少 `#[serde(default)]`（上游 2026-09 才为同类问题立规矩：缺字段会**重置用户配置**）
- **计划**：补丁 0001 —— `{ enabled: bool, speed: f32 }`，补 `#[serde(default)]`，并在动画采样处应用倍率
- **状态**：`待修（计划补丁 0001）`

### K-007 · 内存占用偏高 / applet CPU 偶高

- **现象**：COSMIC 全量进程常驻约 **1.7–1.9 GB**；`cosmic-files-applet` CPU 偶发 15–20%
- **影响**：在 15 GB 内存机器上可接受，但与"Rust 省内存"的直觉不符（与社区评测结论一致）
- **证据**：`ps -eo comm,rss | grep cosmic` 汇总；`cosmic-files-applet.scope` 记录 593 MB peak
- **状态**：`仅记录`（`docs/PERFORMANCE.md` 建立基线后跟踪）

### K-008 · fcitx5 需按合成器重新绑定

- **现象**：fcitx5 是「每个合成器一份」的：在 KDE(Ctrl+Alt+F2) 与 COSMIC(Ctrl+Alt+F3) 之间切换后，中文输入失效
- **影响**：切换会话后需重绑输入法
- **规避**：`scripts/60-verify.sh --rebind-ime`（等价脚本），自动识别当前活动会话并重绑
- **证据**：fcitx5 日志 `Using Wayland native input method protocol: 1`（说明 cosmic-comp 的 `zwp_input_method_v2` 已被使用，协议本身没问题）
- **状态**：`已内置规避`

---

## 运维提示（非缺陷）

| 项 | 说明 |
|---|---|
| 首次构建耗时长 | 约 1.5–4 小时（30 个组件各自编译）；用 `sccache` 后重复构建大幅缩短 |
| 磁盘占用 | 各组件 `target/` 合计约 37 GB；`scripts/30-build.sh --slim` 可清理（保留 sccache）|
| 首次拉取工具链 | 各组件 `rust-toolchain.toml` 会触发 rustup 下载对应版本（如 1.93.1）|
| sysext 生效期间 | `/usr`、`/opt` 为只读叠加层，此时**不要用包管理器装/升级软件**（先卸载扩展）|
