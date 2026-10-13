# 上游跟踪与补丁维护（UPSTREAMING）

## 1. `upstream.lock`：可复现的根

`upstream.lock` 逐行记录 `<名称> <commit> <官方 URL>`：1 个 `cosmic-epoch` 本体 + 全部子模块。
任何人用同一份 lock 都能 checkout 到**完全相同的上游代码**，从而保证补丁可应用、构建可复现。

```bash
./scripts/10-fetch.sh --check     # 校验现有构建树与 lock 是否一致（不联网）
./scripts/10-fetch.sh --lock      # 由现有构建树反向生成/更新 lock（通常在解完冲突后）
```

## 2. 升级上游（bump）

```bash
./scripts/10-fetch.sh --update    # git fetch + 子模块更新，并按 lock 切到目标 commit
./scripts/20-apply.sh --check     # 预演补丁是否仍能应用
#   ├─ 无冲突 → 直接进入构建
#   └─ 有冲突 → 见 §5「冲突处理」，解完后 20-apply.sh 记录状态
./scripts/30-build.sh && ./scripts/40-sysext.sh
./scripts/60-verify.sh --report   # 自动冒烟
# 人工：按 docs/TESTING.md §2 清单验收，结果记入 §3 记录表
./scripts/10-fetch.sh --lock      # 把新的 pin 固化进 lock（与补丁集版本一起提交）
```

**建议节奏**：跟随上游两周一小版；只在冒烟 + 人工清单达标后才合并 lock 变更（即「pinned + tested」）。

## 3. 补丁分级（每条补丁必须标注）

| 分级 | 含义 | 处理策略 |
|---|---|---|
| `upstreamable` | 与架构无关的通用改进/修复，上游大概率接受 | 优先向上游提 PR；在本仓库保留一份直到上游合并，合并后删除 |
| `loongarch-only` | 龙芯架构/发行版特有的适配（如 16K 页、SIMD 缺失、包路径差异）| 长期保留；在上游倾向以「可移植写法」提交则也可能升级为 upstreamable |
| `local-hack` | 临时绕过或本地偏好，**带明确回退条件** | 必须在补丁头部写清「何时可以删除」 |

## 4. 补丁规范

**命名**：`patches/<上游仓库名>/NNNN-<短横线-slug>.patch`，例如
`patches/cosmic-comp/0001-animations-config.patch`

**头部字段**（模板见 `patches/templates/patch-header.txt`）：

```
Upstream: pop-os/cosmic-comp@41497b42        # 补丁基于的上游仓库与 commit
Grade: upstreamable | loongarch-only | local-hack
Issue: https://github.com/pop-os/cosmic-comp/issues/376
Evidence: <验证证据：命令输出/journal 片段/性能数字>
Retire-when: <local-hack 必填：什么条件下可删除>
Signed-off-by: H076lik <chzih076@users.noreply.github.com>
```

**生成方式**：建议在构建树的对应仓库里提交后 `git format-patch -1` 导出，保证 diff 干净、可 3-way 应用。

**DCO**：所有补丁与提交需带 `Signed-off-by`（Developer Certificate of Origin）。

## 5. 冲突处理

```bash
cd "$COSMIC_BUILD_DIR/cosmic-comp"
git worktree add --detach /tmp/rebase-check "$(git rev-parse HEAD)"   # 不动主工作树
cd /tmp/rebase-check
git apply --3way /path/to/patch      # 观察冲突文件与冲突块数量
# 解冲突 → 回到主工作树重新生成补丁 → 20-apply.sh --check 确认干净
```

记录冲突面（文件数/冲突块数）有助于判断补丁是否已「过时到该放弃」。

## 6. 与上游协作

- 上游 COSMIC 的 PR 模板明确要求：**若使用大模型辅助且不能完全理解改动，请勿提交 PR**；使用了大模型须在 commit message 中如实声明。本仓库遵循该要求。
- 上游合并后：把对应补丁从 `patches/` 删除，并在 `docs/KNOWN-ISSUES.md` 标注「已由上游修复」。
- 提交上游时只带必要改动，避免把 `local-hack` 混进去。

## 7. 版本与发布建议

- 用 tag 标记补丁集版本，并与上游 pin 绑定，例如 `v0.1.0+cosmic-364341d`；
- Release 说明中列出：上游 pin、补丁清单、已验证平台、已知问题链接；
- **只发布补丁与脚本**，不附带任何上游源码或二进制产物。
