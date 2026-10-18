# 原生包安装（.deb）与版本号陷阱

本文记录把 COSMIC 构建产物安装到 **AOSC OS（LoongArch）** 上的推荐方式，以及踩过的坑。

---

## 1. 为什么不用 systemd-sysext

COSMIC 早期用 `systemd-sysext` 部署：把构建产物做成 `/usr` 的只读叠加层。

- 优点：不改系统文件、摘除简单
- 致命缺点：**合并后 `/usr` 变只读**，`oma install` / `dpkg -i` / `pacman` 等全部失败
  （实测报 `只读文件系统`），相当于把包管理器废掉

对一台日常使用的桌面机这是不可接受的，故改用原生 `.deb`。

---

## 2. 版本号陷阱（最重要）

发行版仓库里的 COSMIC 包版本形如 **`1.0.14`**，但这是 **crate 版本号**，不代表上游 epoch 版本。

| 事实 | 值 |
|---|---|
| 发行版包版本（AOSC） | `1.0.12` ~ `1.0.14` |
| 对应上游 epoch | **1.0.x**（约 2025 年初） |
| 上游最新 epoch | **1.10.0**（2026-10-08） |
| 判定证据 | `cosmic-settings --version`：发行版 = `1.0.12`，自建 = `1.10.0`；发行版二进制里**没有** 1.10 才有的磨砂设置字符串（`frosted.thickness` 为 0） |

> 结论：装发行版的包 = **降级 9 个 epoch**，会丢失主题 schema、磨砂 UI、面板配置等大量特性。

---

## 3. 方法：同名包 + 更高版本号

`dpkg` 判断升级看**版本号**（`1.10.0` > `1.0.14`），不关心二进制里装的是什么。
因此只要：

1. **包名沿用发行版**（`cosmic-comp`、`cosmic-panel`、`pop-launcher`、`xdg-desktop-portal-cosmic` …）
2. **版本号用上游 epoch**（如 `1.10.0`，补丁包可加 `+cosmic-loongarch1`）

`dpkg -i` 就会把它当作**升级替换**：不产生文件冲突、旧包文件被接管、包管理器数据库保持一致，
`/usr` 保持可写。

---

## 4. 打包规则（`scripts/40-package.sh` 实现）

| 规则 | 说明 |
|---|---|
| 只放必要文件 | 二进制 + 该包原属的桌面/服务/图标文件；**不镜像**发行版的 `doc`/`license`/`man`（一个包里常有数千文件，曾一次写出 **62 GB** 垃圾） |
| 数据文件按归属分配 | 用**一次** `dpkg -S` 批量查询「该路径原本属于哪个包」，把数据文件放进**同一个包**；否则升级会删掉它们 |
| 缺文件即被删 | dpkg 升级时会删除「新包不包含」的旧文件 —— 所以**二进制一个都不能漏**（漏打包 applet 会导致面板小组件全消失），图标/桌面条目同理 |
| 补丁二进制优先 | 从构建树 `target/release/<repo>` 取打过补丁的二进制覆盖（默认 `cosmic-comp`，见 `PATCHED_REPOS`） |
| 插件并集合并 | `pop-launcher` 插件同时保留发行版已有的与本次构建的，避免升级丢插件 |
| 数据包分离 | `cosmic-icons` / `cosmic-wallpapers` 做独立数据包（Architecture: all），否则 1.10 应用图标会退化成通用图标 |
| 全部在磁盘操作 | **不要**把 GB 级产物放到 `/tmp`（tmpfs = 内存，会直接撑爆系统） |

---

## 5. 安装与校验

```bash
./scripts/40-package.sh --version 1.10.0    # → out/debs/*.deb
sudo ./scripts/50-install.sh                # dpkg --dry-run 预检 → dpkg -i → 刷新图标/桌面缓存
./scripts/60-verify.sh                      # 只读校验
sudo ./scripts/99-uninstall.sh              # 降级回发行版（apt-get --allow-downgrades）
```

`60-verify.sh` 检查项：

1. 所有组件包版本 = 目标 epoch 版本
2. 构建产物与 `/usr/bin` 逐字节比对（补丁组件单独校验特征串 `animations: enabled`）
3. `/usr` 不是 overlay 且无 sysext 合并
4. `cosmic-comp` 含补丁特征、`cosmic-settings` 含磨砂 UI

安装完成后需要**注销并重新登录**（或重启），让 compositor、面板、会话组件全部换成新版本。

---

## 6. 回滚

```bash
sudo ./scripts/99-uninstall.sh   # apt-get install --allow-downgrades <包列表>
```

这会从发行版仓库重装同名包（降级到 `1.0.x`），并移除本项目独有的包
（`cosmic-desktop-extras` / `cosmic-icons` / `cosmic-wallpapers`）。

---

## 7. 跟踪上游更新

上游每约 **2 周**发布一个 epoch（间隔中位数 ≈ 13 天）。发版信号是各组件出现
`Epoch X.Y.Z version update` 提交（通常提前 2–3 天）。

```bash
curl -s https://api.github.com/repos/pop-os/cosmic-epoch/releases/latest
curl -s "https://api.github.com/repos/pop-os/cosmic-comp/commits?per_page=5"
```

发布后：bump `upstream.lock` → `10-fetch.sh --update` → `20-apply.sh`（补丁可能需要 rebase）
→ `30-build.sh` → `40-package.sh --version <新版本>` → `50-install.sh`。

> 若上游合并了动画开关 PR #2209，则 `0001` 补丁可以退役。

---

## 8. 已验证组合

| 项目 | 值 |
|---|---|
| 发行版 | AOSC OS 14.0.0 "Naïve" / `loongarch64` |
| 上游 | `cosmic-epoch` `epoch-1.10.0`（pin `364341d`） |
| 包数量 | 37 个 `1.10.x`（含 `cosmic-comp 1.10.0+cosmic-loongarch1`） |
| 二进制覆盖 | 47/47，46 个逐字节一致 + 1 个（cosmic-comp）为补丁版 |
| 包管理器 | `dpkg`/`oma` 正常，`/usr` 可写 |
