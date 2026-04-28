# TaskDetailSheet 实现说明（详细计划模式）

本文档用于沉淀 iOS `TaskDetailSheet` 当前实现，方便后续在 Android 与鸿蒙做同构迁移。

## 1. 目标与范围

`TaskDetailSheet` 当前承担两类能力：

1. 任务详情展示
- 进度卡片（百分比 + 渐变进度条）
- 任务基础信息（名称、开始/截止时间）
- 完整备注

2. 「详细计划模式」（Subtasks）
- 子任务列表加载
- 新增子任务
- 勾选完成/取消完成
- 删除子任务

## 2. 当前代码位置

- 视图层：
  - `Deadliner/Features/Home/Sheets/TaskDetailSheet.swift`
- 详情页子任务 ViewModel：
  - `Deadliner/Features/Home/Sheets/TaskDetailPlanViewModel.swift`
- 子任务仓储接口实现：
  - `Deadliner/Data/Repositories/TaskRepository.swift`
- 子任务持久化实现：
  - `Deadliner/Data/Persistence/DatabaseHelper.swift`

## 3. 页面结构（UI Composition）

`TaskDetailSheetView` 主体结构：

1. `NavigationStack`
2. `ScrollView` + `VStack`
- `progressCard`
- `taskMetaCard`
- `noteCard`
- `planCard`（详细计划模式）
3. 右下角 FAB（overlay）

顶部工具栏：

- 左上：编辑按钮（弹 `EditTaskSheet`）
- 右上：星标切换按钮

背景策略：

- Medium detent：透明背景（`Color.clear`）
- Large detent：`systemGroupedBackground`

## 4. 「详细计划模式」交互定义

### 4.1 子任务列表排序

视图层展示排序规则（`displayedSubTasks`）：

1. 未完成在前、已完成在后
2. 同完成状态按 `sortOrder` 升序
3. 再按 `id` 升序兜底

### 4.2 新增交互（当前版本）

- FAB 语义固定为“新增子任务”（只负责开启输入）
- 点击 FAB 展开输入行（输入行样式与真实子任务行一致）
- 新增触发条件：
  - 键盘回车（`onSubmit`）
  - 输入失焦（`onChange(of: isPlanComposerFocused)`）
- 新增成功后：
  - 清空输入
  - 若是回车提交：保持输入行并维持焦点（连续录入）
  - 若是失焦提交：收起输入行

### 4.3 勾选与删除

- 勾选按钮：切换 `isCompleted`
- 删除按钮：删除当前子任务
- 两者都走 `TaskDetailPlanViewModel`，并受 `isMutating` 防抖保护

## 5. 进度显示与动画

进度来源：

- `TaskDetailSheet` 内部按 `startTime/endTime/now` 动态计算，不依赖 Home 列表展示用 progress

进度动画：

- 页面出现时从 `0 -> targetProgress` 动画
- 百分比文本配合 `numericText + blur` 做过渡模糊
- 当前实现通过 `progressAnimationKey` 避免非必要重播（仅任务核心时间/状态变化时重置）

## 6. 状态模型（iOS）

### 6.1 TaskDetailSheetView 本地状态

- `currentItem`: 当前任务快照
- `editSheetItem`: 控制编辑 sheet
- `isSavingStar`: 星标保存保护
- `errorText`: 错误弹窗文本
- `animatedProgress`, `isProgressAnimating`, `progressAnimTask`: 进度动画状态
- `showPlanComposer`, `draftSubTask`, `isPlanComposerFocused`: 详细计划输入状态
- `hasLoadedPlan`: 首次加载保护

### 6.2 TaskDetailPlanViewModel 状态

- `subTasks`: 子任务数组
- `isLoading`: 初次/刷新加载中
- `isMutating`: 新增/勾选/删除中的互斥保护

## 7. 分层与数据流

### 7.1 分层职责

1. View（`TaskDetailSheetView`）
- 负责展示、交互事件、错误反馈
- 不直接操作 DB

2. ViewModel（`TaskDetailPlanViewModel`）
- 管理子任务状态
- 封装增删改查动作与互斥逻辑

3. Repository（`TaskRepository`）
- 聚合业务动作：写 DB、触发 Sync、发通知、刷新 Widget

4. Persistence（`DatabaseHelper`）
- SwiftData 实体读写
- `subTasksJSON` 编解码与版本戳更新

### 7.2 写操作标准流程

以新增为例（勾选/删除同理）：

1. View 调用 ViewModel 方法
2. ViewModel 调用 Repository
3. Repository 调用 DatabaseHelper 落库
4. Repository 触发：
- `SyncCoordinator.scheduleSync()`
- `NotificationCenter .ddlDataChanged`
- `WidgetCenter.reloadAllTimelines()`
5. ViewModel 刷新/更新本地 `subTasks`

## 8. 持久化数据约定（SubTask）

`InnerTodo` 字段：

- `id: String`
- `content: String`
- `isCompleted: Bool`
- `sortOrder: Int`
- `createdAt: String?`
- `updatedAt: String?`

存储方式：

- 挂载在 `DDLItemEntity.subTasksJSON`（JSON 编码数组）

## 9. 错误处理策略

- 所有失败路径统一落到 `errorText`
- 通过 `.alert("提示", ...)` 向用户展示
- 星标失败会回滚 `currentItem.isStared`

## 10. 跨平台同构建议（Android / 鸿蒙）

建议保持以下“行为等价”：

1. 输入行外观与真实子任务行一致（无额外边框输入框）
2. FAB 只负责“开启新增”
3. 提交触发：回车 + 失焦
4. 列表排序：未完成优先，再 `sortOrder`
5. 子任务写操作后统一触发：
- 列表刷新信号（等价于 iOS 的 `ddlDataChanged`）
- 同步调度
- Widget/卡片刷新（若平台支持）
6. 详情进度使用内部计算，不复用首页展示进度

## 11. 待扩展点（后续可选）

1. 子任务拖拽排序（更新 `sortOrder`）
2. 子任务编辑内容（重命名）
3. 子任务批量操作
4. 统计联动（子任务完成率影响任务卡片展示策略）
5. 统一错误码（便于三端对齐）

---

如果后续你要，我可以再补一版「跨端接口契约文档（DTO + UseCase + 事件总线约定）」作为 Android/鸿蒙的直接开发模板。
