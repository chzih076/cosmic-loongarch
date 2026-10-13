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
- **严重性升级（2026-10-13 实测）**：从带 KDE 环境的上下文（systemd-run / 服务 / 用户 manager 环境）启动时，
  `cosmic-comp` 会因 `WAYLAND_DISPLAY`/`DISPLAY` 存在而**误选 winit（嵌套）后端**并直接失败：
  ```
  WARN  cosmic_comp::backend: Initializing X11 Backend failed.
  ERROR cosmic_comp: Failed to initilize winit backend: EventLoopCreation(Os(OsError { error: NoCompositor }))
  → cosmic-session: cosmic-comp exited with error code 1 / 137
  ```
  实测：**清掉** `WAYLAND_DISPLAY DISPLAY KDE_FULL_SESSION KDE_SESSION_VERSION DESKTOP_SESSION
  SESSION_MANAGER QT_WAYLAND_RECONNECT ICEAUTHORITY KDE_APPLICATIONS_AS_SCOPE QT_QPA_PLATFORMTHEME`
  后即可正常走 DRM/KMS 后端并启动成功（同一 VT、同一 tty3）。
- **规避（已验证）**：① 从干净的 TTY 登录后执行 `start-cosmic`（推荐）；② 自动化时用
  `systemd-run -p PAMName=login -p TTYPath=/dev/tty3 -p StandardInput=tty` 并在命令前清掉上述变量。
  注意：以 root 身份启动的会话会读 `/root/.config`，**配置不生效**，因此不要用 root 跑会话。
- **状态**：`仅记录`（可脚本化；已给出清变量清单）

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
- **已实现**：补丁 [`0001-animations-enabled-and-speed.patch`](../patches/cosmic-comp/0001-animations-enabled-and-speed.patch)
  - 配置：`~/.config/cosmic/com.system76.CosmicComp/v1/animations` = `(enabled: true, speed: 2.0)`
  - `enabled = false`：跳过动画、直接落到终态（沿用 PR #2209 经维护者认可的状态机语义，而非"零时长动画"）
  - `speed`：时长倍率（0.25–8.0 夹取，1.0 = 上游默认），通过进程内全局 `src/animations.rs` 读取，
    覆盖窗口开关/最小化、平铺重排、标签滚动、全屏过渡、拖动缩放、缩放视图等全部时长常量
  - 相对 PR #2209 的增强：补 `#[serde(default)]`（否则以后新增字段会重置用户配置）、新增 `speed`、适配当前 master（原 PR 树冲突 5 文件 7 处）
- **状态**：`已实现（补丁 0001）`
- **验证（2026-10-13）**：`speed` 由 1.5 → 3.0 → 4.0 连续修改，**热生效**（`cosmic-config` 监听文件变更）；
  `enabled: false` 可完全关闭动画；全程 `cosmic-comp` **同一 pid 未重启**，无崩溃。用户确认动画明显加快 ✔

### K-009 · COSMIC System Monitor 进程列表的中文显示异常

- **现象**：`cosmic-monitor` 进程列表中含中文的条目显示不正常
- **影响**：仅影响该视图的观感/可读性；进程本身无异常
- **已排除**：**不是缺字体**。本机 2664 个字体、其中 **100 个支持中文**，且：
  ```
  $ fc-match monospace              → NotoSansMonoCJKsc-Regular.otf "Noto Sans Mono CJK SC"
  $ fc-match 'Noto Sans Mono CJK SC' → 同上
  $ fc-list :lang=zh | wc -l        → 100
  cosmic-monitor 二进制内嵌字体名：Noto Sans CJK SC/TC/HK/KR/JP、Noto Color Emoji、DejaVu Sans Mono
  ```
- **可疑方向**（待定性）：
  1. **字形缺失（豆腐块 □□□）**：iced/cosmic-text 的**脚本回退**在该控件路径上未命中中文族。
     二进制中可见 `cosmic-text-0.19.0/src/font/fallback/mod.rs` 及其错误串
     `Failed to find script fallback for` / `Failed to find preset fallback for` / `Failed to find any fallback for`；
     iced 侧还有 `iced/renderer/src/fallback.rs`。
  2. **编码错乱（乱码如 æ˜Ÿ）**：读取进程名/命令行时按非 UTF-8 解释（`/proc/*/comm`、`cmdline`）。
     `ps -eo comm` 实测**无**非 ASCII 项，因此需确认异常条目来自哪个字段（cmdline？desktop 名称？）。
- **判定方法**：分别看「豆腐块」还是「乱码」——前者查字形回退，后者查编码。
  另可运行：`fc-match 'monospace:lang=zh'`（本机返回 `Droid Sans Fallback`，可作 fontconfig 侧对照）。
- **规避**：暂无（不改变系统字体配置）；可先记录截图与具体条目名
#### 复现与证据（2026-10-13，截图 `/home/lik/图片/Screenshot_20261013_162922.png`）

- **界面文字正常、仅列表项豆腐块**：同一窗口内「应用程序 / 进程 / 详情 / 内存 / 磁盘」等中文正常，
  而表格里的应用名显示为 `COSMIC □□□□□□`、`Discover □□□□` → 问题在**表格单元格的文本绘制路径**
- **数据无误**：`Name[zh_CN]=Discover 软件中心` 等 363 个 `.desktop` 文件**全部为合法 UTF-8**（0 个非 UTF-8）
- **字体齐全**：`cosmic-text-0.19.0/src/font/fallback/unix.rs` 回退表要求的中文族
  `Noto Sans CJK SC/HK/JP/KR/TC` **本机全部已安装**；`fc-match monospace` → `Noto Sans Mono CJK SC`
- **结论（高可信）**：不是缺字体、不是编码，而是 **libcosmic/iced 的表格控件在绘制文本时未走脚本回退**
  （主 UI 文本走正常路径，表格走另一条路径）

- **状态**：`观察中`（已定性：表格文本路径缺回退；候选补丁 0003 = 给 libcosmic 的 table 文本走标准文本管线，
  但 libcosmic 是 git 依赖，需 vendoring/patch 机制，工程量较大）

### K-011 · 打开设置时主题回退成暗色（主题配置缺必填字段）

- **现象**：打开 COSMIC 设置（或相关应用）时界面变成**暗色**，需要在「外观」里点一下才恢复正常
- **根因**（已定位，非用户操作问题）：
  `cosmic-theme` 的 `CosmicTheme` 在处理 1.10.0 新增的 `pub list_button: Component` 字段时
  **没有 `#[serde(default)]`**，而用户主题配置目录里**没有 `list_button` 这个键** →
  `get_entry` 报 `GetKey("list_button", NotFound)` →
  **整个亮色主题加载失败** → 回退到内置默认（暗色）：
  ```
  cosmic-comp[...]: error loading system light theme
  cosmic::theme: error loading system light theme
      error=GetKey("list_button", Os { code: 2, kind: NotFound })
  ```
  「触发一次外观设置」会临时把正确主题广播给所有应用，但只要键仍然缺失，下次启动依旧回退
- **同类**：与补丁 0001 里给 `AnimationConfig` 补 `#[serde(default)]` 是同一类问题
  （上游 2026-09 为"缺字段会重置用户配置"立过规）
- **本地修复（已执行，保留用户配色）**：
  ```bash
  # 用同一主题的 icon_button 作形状模板（两者同为 Component 类型）
  cp ~/.config/cosmic/com.system76.CosmicTheme.Light/v2/icon_button \
     ~/.config/cosmic/com.system76.CosmicTheme.Light/v2/list_button
  cp ~/.config/cosmic/com.system76.CosmicTheme.Dark/v2/icon_button \
     ~/.config/cosmic/com.system76.CosmicTheme.Dark/v2/list_button
  ```
  修复后真实错误数归零（复核时需过滤掉自身命令行产生的日志）
- **上游应做的**：给 `CosmicTheme` 的新增字段补 `#[serde(default)]`，让缺失键回落到默认值而不是整主题失败
- **后续发现（2026-10-13 晚，重启后复核）**：
  - 补 `list_button` 后，**新会话亮色主题 0 报错** ✔（修复生效）
  - 但明暗两套主题的键集不一致：`Light` 有 `accent_text`/`window_hint`（均为 `None`），
    **`Dark` 缺这两个键** → 暗色主题加载时会走同样的失败路径 ✗
  - 这正是"**打开设置有概率变成暗色**"的来源：设置等应用启动时**先按暗色主题加载**，
    暗色加载失败就停在暗色样式；触发一次外观设置后亮色被广播 → 看起来"恢复"
- **完整修复（已执行）**：
  ```bash
  T=~/.config/cosmic/com.system76.CosmicTheme
  cp $T/Light/v2/icon_button $T/Light/v2/list_button      # 亮色补 list_button
  cp $T/Dark/v2/icon_button  $T/Dark/v2/list_button       # 暗色补 list_button
  cp $T/Light/v2/accent_text $T/Dark/v2/accent_text       # None
  cp $T/Light/v2/window_hint $T/Dark/v2/window_hint       # None
  ```
  之后明暗两个分支加载错误均为 **0**（需过滤自身命令行产生的日志）
- **排查手法（可复用）**：
  ```bash
  journalctl -b --since '-5min' | grep -E 'error loading system (light|dark) theme|GetKey\(' \
    | grep -vE 'dsh-subprocess|bash -c'     # 后者会匹配到自身命令行，必须过滤
  ```
- **状态**：`已本地修复（明暗两套主题均已补齐）`

#### 另一个可疑诱因：portal 后端是 KDE 的（双会话共享用户级 portal）

- **现象线索**：主题加载会向 `xdg-desktop-portal` 查询对比度设置；本机日志出现过
  `cosmic::theme::portal > Failed to get the contrast Portal(NotFound("未找到请求的设置"))`
- **本机实况（2026-10-13）**：用户级 `xdg-desktop-portal` 由 **KDE 会话**启动
  （`XDG_CURRENT_DESKTOP=KDE`），后端为 `xdg-desktop-portal-kde`；
  COSMIC 专用后端 `/usr/libexec/xdg-desktop-portal-cosmic` **已安装但未运行**
  → 由于用户级 portal 跨会话共享，**COSMIC 应用拿到的是 KDE 后端** ✗
- **上游同类反馈**：
  - [cosmic-launcher #424](https://github.com/pop-os/cosmic-launcher/issues/424)
    `error loading system dark theme`（评论里有人定位到 portal 未运行）
  - [cosmic-applets #1555](https://github.com/pop-os/cosmic-applets/issues/1555)（标题含 `list_button`）
  - [cosmic-settings #2152](https://github.com/pop-os/cosmic-settings/issues/2152)（Dark palette 缺键）
  - [cosmic-epoch #3712](https://github.com/pop-os/cosmic-epoch/issues/3712)（切换主题报错）
- **后手方案（只改 Settings 接口，对 KDE 影响最小；已验证可行性：
  `cosmic.portal` 声明 `UseIn=COSMIC` 且 `org.freedesktop.impl.portal.desktop.cosmic.service` 可 DBus 激活）**：
  ```bash
  mkdir -p ~/.config/xdg-desktop-portal
  cat > ~/.config/xdg-desktop-portal/portals.conf <<'CONF'
  [preferred]
  org.freedesktop.impl.portal.Settings=cosmic;gtk
  CONF
  systemctl --user restart xdg-desktop-portal
  ```
- **状态**：`待复测`（先验证补键是否已解决；若仍概率性变暗再上 portal 后手）
### K-010 · 磨砂玻璃的效率成本（不是 bug，上游已知的预期限制）

- **现象**：开启磨砂玻璃后，请求模糊的窗口**内部元素**一有动作（滚动、进度动画、列表刷新等），
  GPU 利用率明显上升；窗口本身的移动反而不是主因
- **定性**：**非正确性问题**。上游 issue #2650 中，维护者 Drakulix 明确回复：
  *"This is expected currently, we are aware of the limitations"* ✔ 与本机观察一致
- **机制（代码级，已验证）**：`src/backend/render/wayland/blur_effect.rs`
  - 模糊纹理按 `{renderer_id, offset, passes, region, src}` 做脏判定缓存 →
    **窗口内部内容变化不会触发重新模糊**（`dirty` 五项均未变 → `commit` 不递增）
  - 剩余成本来自**每帧对模糊结果的合成采样**，与「模糊面积 × 通道数(`passes`)」成正比
  - 档位映射：`MAX_STEPS = 15`；`strength = (theme.frosted as u8 + 1)`；
    `BlurStrength` 共 14 档（ExtremelyLow…ExtremelyHigh2），本机当前 `High2`（索引 9）→ `strength = 10`
- **上游相关反馈**：
  - [#2650](https://github.com/pop-os/cosmic-comp/issues/2650) 面板模糊 + 窗口模糊的 GPU 成本 ≈ 两者单独之和的 2 倍（closed，标记为预期限制）
  - [#2795](https://github.com/pop-os/cosmic-comp/issues/2795) 每工作区多个磨砂窗口后性能下降（open；报告者实测**降低 frost 强度后显著改善**，与上表一致）
  - [#2905](https://github.com/pop-os/cosmic-comp/issues/2905) 面板/程序坞模糊 + 副屏视频 → 输入延迟（open）
- **缓解手段（不改代码）**：
  1. 降低档位：`frosted` 从 `High2` → `High`/`Medium2`（成本随 `passes` 近似线性下降）
  2. 只关窗口模糊、保留面板/小部件：`frosted_windows = false`（窗口内元素动作是主要成本来源）
  3. 减少同屏磨砂窗口数量/面积
- **我们的策略**：**暂不做本地优化补丁** —— 上游视为预期限制，方案空间未明；
  若日后要做，须先按 #2795 的方法给出真机可复现数据（见 `UPSTREAMING.md` 的红线）
- **状态**：`已定性（已知效率限制，非缺陷）`

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
