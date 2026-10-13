# 仓库元数据（GitHub 填写用）

> 本文件供仓库维护者复制粘贴到 GitHub 仓库设置里，不参与构建。

## Description（仓库简介栏，纯文本单行，上限 350 字符）

### 推荐（151 字符）

```
COSMIC Desktop 的 LoongArch/AOSC OS 适配补丁集与构建流水线：只分发补丁，源码取自官方。修复 libseat、libjpeg-turbo 等构建阻塞，改进动画可配、renderD128 花屏、输入法与环境；upstream.lock + 幂等脚本，可复现构建、一键回滚。
```

### 备选 · 精简（76 字符）

```
COSMIC Desktop 的 LoongArch/AOSC OS 适配补丁集与构建流水线：只分发补丁，源码取自官方。让它在龙芯上不止能用，还要好用。
```

### 备选 · 详尽（301 字符，仍在 350 上限内）

```
COSMIC Desktop 的 LoongArch/AOSC OS 适配补丁集与构建流水线。只分发补丁，源码取自官方渠道。修复 libseat 的 pkg-config 路径、libjpeg-turbo 不支持 loongarch64 等构建阻塞；改进动画开关与速度倍率、renderD128 跨节点纹理花屏、会话环境串味、fcitx5 输入法重绑。upstream.lock 锁定上游与 30 个子模块 SHA，幂等脚本实现校验、打补丁、构建、打包 systemd-sysext、冒烟验证与一键回滚。已在 Loongson-3B6000 + AOSC OS 14 + RX 7650 GRE 验证。
```

## Topics（最多 20 个）

```
cosmic  loongarch  loongarch64  aosc-os  wayland  compositor  systemd-sysext  patching  rust  linux-desktop
```

## 其他建议

- **Website**：留空或填 AOSC OS 官网（本仓库与上游无隶属关系，不建议填上游站点）；
- **Social preview**：可选，放一张 COSMIC 在龙芯上运行的截图（注意截图不包含上游商标争议内容）；
- **About 勾选项**：建议勾选 *Releases*（补丁集发布）、*Issues*；Packages/Deployments 可关；
- **默认分支**：`main`。
