# Inspiration Control Capture Module Plan

## 模块拆分

- `control contract`：`OpenInspirationIntent` 只负责写 App Group 路由并拉起主 App；Widget Control 不接触业务数据库。
- `shortcut application`：新增 `CreateInspirationIntent`，校验文本并调用 Capture persistence port，向系统返回执行结果。
- `presentation`：新增独立 `QuickInspirationCaptureSheet`，由 Focus/Rich 两种主壳层通过相同路由展示。
- `persistence`：复用 `CapturePersistenceStore.createCapture` 与现有 `KMPCaptureStore`，不增加表或同步字段。

## 平台映射

- iOS：本轮落地到 `App/Integration/Controls`、`App/Integration/Shortcuts`、`Features/Capture/Sheets` 和两个 Main 壳层。
- HarmonyOS：本轮不改；未来可把系统卡片/服务入口映射到 Capture repository。
- Android：本轮不改；未来可把 Quick Settings Tile/Assistant action 映射到 capture data 层。

## 文件拆分策略

- 单个核心文件尽量不超过 1000 行有效代码
- 若必须逃逸，先申请开发者批准
- Sheet 单独建文件，避免把输入 UI 复制到 `MainView.swift` 与 `RichMainView.swift`。
- 快捷指令写入逻辑独立于 Widget 共用的 `OpenAddEntryIntent.swift`，防止意外加入 Widget target。
- 两个 Main 壳层仅持有展示状态和路由分支，不承载保存规则。

## 风险点

- `RichMainView` 允许隐藏灵感 Tab，因此 composer 路由必须完全独立于 `selectedTab = .inspiration`。
- Intent 后台写库失败时不能静默成功；需返回可理解的失败反馈。
- App Intent 与 `AppShortcutsProvider` 必须属于同一主 App target，且不能错误加入 Widget target。
- 现有 `KMPCaptureStore.swift` 有未提交用户修改，尽量零改动复用。

## 最终实现映射

- `control contract`：`OpenInspirationIntent` 写入 `open_inspiration_composer`；`DeadlinerInspirationControl` 保持静态 Control，不访问 KMP。
- `shortcut application`：`CreateInspirationIntent.swift` 只位于主 App 同步文件组，调用 `PersistenceStores.captures.createCapture`。
- `presentation`：`QuickInspirationCaptureSheet.swift` 是唯一输入 UI；Focus/Rich 壳层仅控制展示状态。
- `domain`：`InspirationCaptureText` 统一处理空白文本与首尾裁剪，应用内和应用外入口共用。
- `persistence`：未修改现有 Capture 表、仓储或同步协议；复用 `KMPCaptureStore` 现有发布变更和同步调度能力。
