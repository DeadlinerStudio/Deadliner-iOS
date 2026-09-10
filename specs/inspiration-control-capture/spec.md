# Inspiration Control Capture

## 背景

- 创建日期：2026-08-12
- 功能标识：`inspiration-control-capture`
- 需求来源：现有 iOS 控制中心“灵感”按钮只负责打开灵感页；当 Rich 首页隐藏灵感 Tab 时，路由会退回主页，而且用户仍需进入完整页面后才能输入。
- 系统约束：WidgetKit Control 只有按钮/开关交互；Apple 明确说明从控制中心 Control 执行的 App Intent 不能展示 interactive snippet，因此第三方 Control 无法直接承载自定义文本输入弹窗。

## 目标

- 点击 Deadliner 自带的“灵感”控制后，稳定拉起一个自动聚焦的极简灵感编辑 Sheet，不依赖灵感 Tab 是否可见。
- 新增“创建灵感” App Intent，让用户可以在快捷指令中把文本传给 Deadliner，并在不打开主界面的情况下保存。
- 保留“打开灵感列表”的旧路由语义，避免内部路由值混用。
- 两个入口最终写入同一 Capture 持久化仓储，灵感列表能够观察到新增内容。

## 非目标

- 不尝试从第三方 Control 展示 SwiftUI snippet 或任意文本框；系统不支持该能力。
- 不自动替用户创建或安装个人快捷指令；用户仍需在“快捷指令”中组合“询问输入”和 Deadliner 动作，并选择系统“快捷指令”控制。
- 不修改灵感的数据模型、同步协议或其他平台入口。
- 不让 Widget Extension 直接打开 KMP 数据库。

## 用户场景

1. 用户从任意 App 拉下控制中心，点击 Deadliner“灵感”，Deadliner 打开后立即显示简洁输入 Sheet；保存后灵感出现在列表中。
2. 用户在 Rich 首页隐藏了灵感 Tab，点击控制中心按钮仍显示编辑 Sheet，而不是落到主页且无后续动作。
3. 用户创建个人快捷指令“询问输入 → Deadliner 创建灵感”，再把它放进控制中心；运行时在系统界面输入文字，Deadliner 不切到前台也能保存。
4. 用户取消应用内 Sheet、输入空白文本或给 App Intent 传入空白文本时，不创建空灵感。

## 验收标准

- Deadliner 自有 Control 写入独立路由 `open_inspiration_composer` 并拉起 App。
- Focus 与 Rich 两种主页壳层都能消费新路由并展示同一个极简 Sheet。
- Sheet 出现后文本输入自动获得焦点；空白内容时保存按钮不可用；保存会去除首尾空白、创建一次灵感并关闭。
- 原 `open_inspiration` 路由仍打开灵感列表，不改变已有深链行为。
- `CreateInspirationIntent` 有必填 String 参数、`openAppWhenRun = false`，成功与空输入均返回明确系统反馈。
- 新 Intent 可在快捷指令动作列表中找到，并作为 Deadliner App Shortcut 暴露给 Siri/Spotlight 等系统入口。
- App Intent 通过主 App 的 Capture 仓储写入，不加入 Widget Extension target，不在扩展进程打开 KMP driver。
- 新增或修改的核心 Swift 文件不超过 1000 行；规格校验、静态检查与统一 Xcode 构建有记录。

## 风险与约束

- App Intent 的后台执行环境与前台 UI 生命周期不同，不得依赖 `CaptureStore.shared` 的 `@MainActor` 投影；应直接调用 `PersistenceStores.captures`。
- KMP 数据库位于 App Group；后台 Intent 写入前需执行共享数据库 bootstrap，并让现有仓储负责变更通知与同步调度。
- 当前工作区已有用户未提交的分类与 Capture 日期解析修改，本功能必须保留这些改动，不做无关清理。
- App Shortcut 的应用外文本弹窗由系统“快捷指令”的“询问输入”动作提供，不宣称 Deadliner Control 本身能弹窗。
