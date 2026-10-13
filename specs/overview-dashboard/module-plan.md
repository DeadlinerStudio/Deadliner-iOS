# Overview Dashboard Module Plan

## 模块拆分
- Bridge：共享月份、独立专注加载及错误回调，复用 Core 投影和更正/删除用例。
- OverviewViewModel：月份与加载状态、生命周期刷新、同期比较。
- MonthlyInsightRepository：按月文件持久化、尝试记录、成功固化、并发合并。
- Components：月历、状态饼图、管理双卡、趋势预览、全文洞察。
- Details：任务统计、趋势、复盘导出、专注全量管理；归档复用 ArchiveView。

## 平台映射
业务投影对应共享 OverviewViewModel/FocusStatistics；iOS 适配在 Features/Overview 与 Data/Repositories。Android 模块参考产品目录 TRD，不移植 Compose。

## 文件拆分策略
各组件、日期比较、缓存和页面独立文件，本轮修改文件不超过1000有效行。

## 风险点
月报与月历口径不同；AI缓存不冻结指标；管理不随月份切换；全局专注栏和导航沿用宿主安全区。现有未提交工作保留，不变更公共数据合同。

## 实际文件落点
- `Features/Overview/OverviewView.swift`：根看板、月份导航与宿主标题回调。
- `OverviewPeriod.swift`：本地 Gregorian 月份与同期比较；时区变更按月键保持选择。
- `Components/OverviewDashboardCards.swift`：月历、语义饼图、72pt预览、全文关键词与错误组件。
- `OverviewViewModel.swift`：KMP投影、原始持久化通知刷新、跨午夜/前台刷新、年度贡献月投影拼接。
- `OverviewDetailViews.swift`：任务/趋势/复盘独立 NavigationStack 路由。
- `OverviewFocusManagement.swift`：全部保存记录、全部目标和分类分配、校正及删除确认。
- `OverviewReviewExportView.swift`：背景图/文字颜色、图片预览、Photos添加权限、系统分享与保存。
- `Data/Repositories/Overview/MonthlyInsightRepository.swift`：按月JSON原子写入、尝试记录及应用级并发合并。
- 相邻 Core `shared/src/iosMain/kotlin/com/deadliner/bridge/IosOverviewStateBridge.kt`：新增月度/专注安全读取与专注管理用例回调。共享数据库和同步协议未改。

- `DeadlinerUITests/OverviewDashboardUITests.swift` 与独立 `DeadlinerOverviewValidation.xcscheme`：模拟器实际导航、月份边界、导出图片与辅助字号回归，截图及 UI 层级保留在 xcresult。
