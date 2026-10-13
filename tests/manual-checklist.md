# 人工验收清单（打印/勾选用）

上游 pin: `____________`   补丁集: `____________`   日期: `__________`

## 会话与合成器
- [ ] 桌面正常显示（无黑屏/花屏），面板与壁纸正常
- [ ] 拖动/缩放窗口流畅
- [ ] 自动平铺（Autotile）与窗口堆叠（Stack）可用
- [ ] 工作区切换、总览（Overview）可用
- [ ] 窗口开关/最小化动画正常（若已打动画补丁：改 `speed` 热生效）

## 桌面组件
- [ ] 面板 applet 全部正常（时间/状态区/音量/电池/网络/输入源）
- [ ] `notify-send test hello` 弹出通知
- [ ] Super 打开启动器，可搜索并启动应用
- [ ] `cosmic-settings` 各页可打开、修改生效
- [ ] `cosmic-files` 浏览/复制/打开正常（无 applet 崩溃）
- [ ] `cosmic-term` 可用，resize 重绘正常

## 输入与语言
- [ ] Ctrl+Space 切换输入法；中文可打词、候选窗可见
- [ ] KDE↔COSMIC 切换 VT 后输入法可用（必要时 `60-verify.sh --rebind-ime`）
- [ ] XWayland 应用输入正常

## 系统集成
- [ ] 音频播放/音量调节正常
- [ ] NetworkManager 状态与 applet 一致
- [ ] 截图可用（`cosmic-screenshot` / PrintScreen）
- [ ] 剪贴板 Wayland↔XWayland 双向可用
- [ ] 注销/重启/关机动作可用

## 显示与硬件
- [ ] 多输出/热插拔识别正常（`cosmic-randr list` 佐证）
- [ ] 分辨率/刷新率修改生效并持久化
- [ ]（若可达）挂起/唤醒后无花屏

## 性能（对照 docs/PERFORMANCE.md）
- [ ] 空闲 CPU/内存在基线区间内
- [ ] 交互无明显掉帧；`cosmic-files-applet` 无持续高 CPU
- [ ] 与 KDE 并存切换无残留异常

## 结论
- 通过率: `____ / ____`
- 新发现的问题（追加到 docs/KNOWN-ISSUES.md）: `________________`
