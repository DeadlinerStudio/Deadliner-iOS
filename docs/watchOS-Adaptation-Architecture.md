# Deadliner watchOS 适配架构设计

## 1. 目标与约束

本文档给出 Deadliner 在现有 iOS 工程基础上适配 watchOS 的推荐架构与落地步骤，目标是：

1. 复用现有核心业务模型与规则，避免重复实现。
2. watch 端具备可用离线能力（查看、完成、延期、快速新增）。
3. 同步策略可解释、可恢复、可观测。
4. 不打断现有 iOS 与 Widget 迭代节奏。

## 2. 是否需要新建工程

结论：默认不需要新建工程，优先在现有 `Deadliner.xcodeproj` 中新增 watchOS Target（Watch App + Watch Extension）。

理由：

1. 你当前已经是单工程多 target 结构（主 App、Widget、Tests），延续该组织成本最低。
2. 共享代码（`Core` / `Application` / `Data`）可以直接通过 Target Membership 或逐步抽成 Swift Package 复用。
3. CI、签名、版本号、发布链路都更容易保持一致。

何时考虑新建独立工程：

1. watch 团队和 iOS 团队完全独立开发、独立发布节奏。
2. watch 需要完全不同的依赖图，且会长期与 iOS 分叉。
3. 组织层面要求完全隔离仓库/权限。

对 Deadliner 当前状态，不建议一开始拆工程。

## 3. 推荐分层（在现有代码基础上）

### 3.1 复用层次

1. `Core`（强复用）
- 领域模型：`DDLItem`、`Habit`、`DDLState` 等。
- 领域规则：截止时间计算、状态转换、排序规则。

2. `Application`（中高复用）
- UseCase 与 Ports（读写任务、状态变更、导入转换）。
- 同步编排接口，拆出 watch 友好的同步门面。

3. `Data`（按平台适配）
- Repository 协议保持一致。
- iOS 与 watch 分别实现本地存储与同步通道。

4. `Features`（平台特化）
- iOS 保持现状。
- watch 端单独实现轻量 UI 流程，不复用 iOS 页面。

### 3.2 建议目录蓝图

在现有目录上增量演进：

```text
Deadliner/
  Core/
  Application/
  Data/
  Features/

DeadlinerWatch/
  App/
  Features/
    Today/
    QuickAdd/
    TaskDetail/
  Presentation/
    ViewModels/
  Integration/
    WatchConnectivity/

DeadlinerSharedSync/
  DTO/
  Snapshot/
  Merge/
```

说明：

1. `DeadlinerWatch/` 放 watch 端 UI 与平台集成逻辑。
2. `DeadlinerSharedSync/` 用于承载跨端同步 DTO、版本向量、冲突合并规则（可先目录共享，后续再抽 Swift Package）。

## 4. 同步架构设计

### 4.1 数据主权

采用“iPhone 主源 + Watch 离线缓存 + 双向回放”：

1. iPhone 作为 canonical source（最终一致来源）。
2. watch 本地可改，改动先写本地 Outbox。
3. 连接可用时回放 Outbox 给 iPhone，由 iPhone 归并并下发最新快照。

### 4.2 WatchConnectivity 通道职责

1. `sendMessage`：前台在线的低延迟操作回执（如点完成后即刻反馈）。
2. `updateApplicationContext`：覆盖式状态摘要（例如今日统计、最近任务）。
3. `transferUserInfo`：可靠传输操作事件（离线补偿主通道）。
4. `transferFile`：仅用于较大快照或诊断包（非默认通道）。

### 4.3 事件模型（推荐）

每次 watch 写操作都记录为事件：

1. `eventId`
2. `entityId`
3. `opType`（complete / postpone / create / archive ...）
4. `payload`
5. `logicalTime`（时间戳 + deviceId + counter）

iPhone 归并后回传最新实体版本，watch 用 ack 清理 Outbox。

### 4.4 冲突处理

默认策略：

1. 字段级 Last-Write-Wins（基于 `logicalTime`）。
2. 状态机字段（如 `DDLState`）走显式转移校验，非法转移拒绝并回退。
3. 保留冲突日志（便于 debug 与客服定位）。

## 5. watchOS 交互范围（MVP）

第一阶段仅做高频闭环：

1. `Today`：今日/即将到期列表。
2. `Quick actions`：完成、延期（+1h / +1d）。
3. `Quick add`：语音新增任务。
4. 基础提醒与通知动作。

暂不进入 watch MVP：

1. 复杂筛选与全局搜索。
2. 复杂编辑器（长文本、多子任务批量编辑）。
3. AI 面板等重交互模块。

## 6. 渐进式实施计划

### Phase 0（准备）

1. 新增 watch targets 与最小可运行页面。
2. 梳理 `Core/Application` 中平台耦合代码并隔离。

### Phase 1（共享能力）

1. 抽取/稳定 `TaskReadPort`、`TaskWritePort` 的 watch 可用门面。
2. 建立 `DeadlinerSharedSync` 的 DTO 与事件协议。

### Phase 2（MVP 功能）

1. Today 列表。
2. 完成/延期。
3. 快速新增。
4. Outbox + 回放 + ack。

### Phase 3（体验增强）

1. Complication / Smart Stack 展示关键指标。
2. 失败重试与同步健康状态提示。
3. 性能优化（冷启动、首屏查询、批量合并）。

## 7. 工程与发布建议

1. Target：新增 `DeadlinerWatchApp`、`DeadlinerWatchExtension`。
2. Bundle 与 capability：与主 App 使用同一 App Group（如有共享容器需求）。
3. CI：先加独立 watch build job，再并入主流水线。
4. 测试：
- 单元测试：合并策略、状态机转移、Outbox 回放。
- 集成测试：iPhone-watch 双端同步闭环。

## 8. 风险与规避

1. 风险：把 iOS 复杂 UI 直接搬到 watch，导致性能和可用性差。
- 规避：watch 只保留高频闭环流程。

2. 风险：同步通道混用但无职责边界，导致重复写入或丢事件。
- 规避：明确“实时回执 vs 可靠回放”职责，统一事件幂等键。

3. 风险：冲突规则散落在 UI 层。
- 规避：统一下沉到 `DeadlinerSharedSync/Merge`。

## 9. 最终建议

1. 先在当前 `Deadliner.xcodeproj` 内新增 watch targets，不新建独立工程。
2. 架构上坚持“核心共享、UI 分治、同步协议统一”。
3. 先做 watch MVP（Today + 完成/延期/新增），跑通端到端闭环后再扩展。
