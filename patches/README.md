# 补丁目录（patches/）

本目录是**本仓库的产品**：只包含补丁，不含任何上游源码。

## 约定

```
patches/
├── README.md                 ← 本文件
├── templates/
│   └── patch-header.txt       ← 补丁头部模板
└── <上游仓库名>/              ← 例如 cosmic-comp / cosmic-session / cosmic-panel …
    └── NNNN-<slug>.patch      ← NNNN 从 0001 起，按应用顺序排列
```

- 目录名必须与 `upstream.lock` 中的名称一致（`scripts/20-apply.sh` 按此对应关系应用）；
- 补丁基于 `upstream.lock` 中该仓库的 commit 生成，**优先用 `git format-patch` 导出**，保证可 `--3way` 应用；
- 未使用的仓库目录不必创建；空目录不会被提交（git 不跟踪空目录）。

## 分级（必须标注）

| 分级 | 含义 | 期望寿命 |
|---|---|---|
| `upstreamable` | 通用改进/修复，上游大概率接受 | 上游合并后删除 |
| `loongarch-only` | 龙芯/发行版特有适配 | 长期保留 |
| `local-hack` | 临时绕过或本地偏好 | 必须写 `Retire-when:` |

## 头部字段（模板见 `templates/patch-header.txt`）

```
Upstream: <repo>@<commit>           补丁基于的上游仓库与 commit
Grade: upstreamable|loongarch-only|local-hack
Issue: <上游 issue/PR 链接，可多个>
Evidence: <验证证据：命令输出、journal 片段、性能数字>
Retire-when: <local-hack 必填>
Signed-off-by: H076lik <chzih076@users.noreply.github.com>
```

## 操作

```bash
./scripts/20-apply.sh --list     # 列出将要应用的补丁
./scripts/20-apply.sh --check    # 预演（不落盘）
./scripts/20-apply.sh            # 应用并记录到 state/patches-applied.txt
./scripts/20-apply.sh --revert   # 撤销（在各仓库执行 git checkout -- .）
```

## 当前补丁

| 补丁 | 目标仓库 | 分级 | 上游状态 | 内容 | 验证 |
|---|---|---|---|---|---|
| `cosmic-comp/0001-animations-enabled-and-speed.patch` | cosmic-comp | `upstreamable` | 参考 issue #376 / PR #2209（均未合并）| 动画开关 `enabled` + 时长倍率 `speed`；补 `#[serde(default)]`；新增 `src/animations.rs` 全局 | 编译通过；干净 worktree 上 `git apply` 零冲突；16 文件 / 2233 行 |

配置方式：

```ron
// ~/.config/cosmic/com.system76.CosmicComp/v1/animations
(
    enabled: true,   // false = 关闭动画（直接落到终态）
    speed: 2.0,      // 1.0 = 上游默认；2.0 = 快一倍（0.25–8.0）
)
```

改动即刻生效（`cosmic-config` 监听文件变更），无需重启会话。
