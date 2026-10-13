# 变更记录

本仓库只分发**补丁与脚本**，版本以「Iteration」划分；每个补丁的动机、分级、证据见 `patches/` 与 `docs/KNOWN-ISSUES.md`。

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

### 协作约定

- `docs/UPSTREAMING.md` 增加红线：不与上游交换 AI 生成内容；上游沟通只用本人话语 + 本机真实数据 + 最小复现。

## Iteration 0 — 2026-10-13

- 初始化仓库骨架：`upstream.lock`（31 条 pin）、`00-deps`→`60-verify`/`99-uninstall` 幂等流水线、
  `docs/`（BUILD/TESTING/KNOWN-ISSUES/PERFORMANCE/UPSTREAMING/REPO-METADATA）、`tests/`、`patches/` 模板与三级分级。
