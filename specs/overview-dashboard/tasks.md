# Overview Dashboard Tasks

## 阶段 1：规格冻结
- [x] 阅读现行 PRD、Android TRD、视觉参考和原型源码，确认 iOS 范围。

## 阶段 2：基础设施
- [x] 月投影桥接、独立错误状态、日期/时区变化与同期比较。
- [x] AI 按月持久化与并发合并。

## 阶段 3：功能实现
- [x] 根看板及独立详情页、全量专注管理、归档入口。
- [x] 复盘分享、背景/文字色调、预览及保存图库。

## 阶段 4：验证与回写
- [x] 大批次完成后统一构建和边界验证（初轮不启动模拟器；后续按用户要求增加模拟器验收）。
- [x] 规格及文件规模检查，记录实机视觉限制。

## 验证记录 · 2026-10-13
- Shared XCFramework：新增 iOS bridge 已完成全架构 Release 构建、部署及字节一致性校验。
- iOS：Xcode 27.1，generic/platform=iOS，Release，CODE_SIGNING_ALLOWED=NO，最终 BUILD SUCCEEDED。应用、Widget 和 Watch 依赖一并构建。验证阶段用临时适配器调用原 Core 部署脚本的 --no-build，复用本轮已构建校验的产物；项目构建脚本保持原样。
- 新增月份工具/AI结果明确 nonisolated/Sendable，最终构建中 Overview/MonthlyInsight 没有新增警告。工程其他既有警告不属于本轮。
- `bash scripts/validation/check_overview_dashboard.sh` 通过：实际日期工具和实际缓存仓储以 Swift 6 + MainActor 默认隔离编译执行，不启动模拟器。覆盖本月同日截止、短月/闰月、跨年、零基数/增长/减少/持平、时区跨日、重启缓存、并发合并、失败显式重试、成功不覆盖、当前月门禁、调用方取消不中断、存储失败不调用 AI。
- built app Info.plist 已验证 NSPhotoLibraryAddUsageDescription；项目 plist、git diff whitespace、规格校验通过；本轮 Overview/Core桥接文件最大503有效行，低于1000。
- 真实任务状态/月报/专注更正规则复用 Core；本轮未另运行 Core 单测。AI测试使用明确的本地 fixture，不调用真实 AI。

## 验收范围与剩余项目
- [x] iPhone 17 Pro 亮/暗主题与最大辅助字号视觉验收。
- [ ] 极窄宽度/iPad 分屏验收。
- [x] 原生大标题/subtitle折叠和返回月份/滚动恢复（模拟器截图核对）。
- [ ] 运行中的全局专注栏避让验收。
- [ ] 真机图库授权/保存/系统分享、背景图渲染及更正/删除返回刷新。
初轮未启动模拟器或设备；后续模拟器记录如下，真机项目仍需验收。原型通过源码读取核对层级/尺寸/交互；浏览器 file:// 预览被工具 URL 策略阻止。

## 模拟器验收 · 2026-10-13
- 用户追加要求“启动模拟器验证”，覆盖初轮不启动模拟器的约束。
- iPhone 17 Pro / iOS 26.2，复用 DeadlinerFocusValidation 模拟器，保留现有数据。
- 默认方案遇到既有 `ToolCallExecutorBatchCompatTests` 编译错误；新增 `DeadlinerOverviewValidation` 方案仅运行 UI 测试，不修改既有单测。
- 模拟器必须使用 `CODE_SIGNING_ALLOWED=YES CODE_SIGN_IDENTITY=-` 本地签名，保留 App Group 权限；无签名构建会在启动数据库初始化时断言。
- 浅色两个 XCTest 用例已通过：月份前后切换/未来月禁用、当日摘要、专注/归档/任务/趋势/复盘独立导航、历史月份保留、导出表单与实际 ImageRenderer 图片预览，以及最大辅助字号下所有卡片可访问。
- 实际发现并修复：辅助字号两位数日期换行；AI 不可用时复盘标题空白区域不响应。日期保持单行且统一高度，复盘标题及底部链接扩展完整的至少 44pt 点击区域。
- 本轮未配置真实 AI，验证的是明确的不可用状态；管理当前为空，未执行有记录的更正/删除。未触发图库写入或对外分享。
- 最终深色两个 XCTest 用例通过，增加日期格子高度一致性断言，确认辅助字号单/双位数字均不换行。
- 用户追加要求：月份切换按钮保留 iOS 柔光玻璃 toolbar 材质；移除 `.sharedBackgroundVisibility(.hidden)`，使用系统默认导航玻璃。
- 最终柔光玻璃版本：`/tmp/OverviewDashboardGlass.xcresult` 两项 UI 测试全部通过；最终深色：`/tmp/OverviewDashboardDarkFinal.xcresult` 两项通过。截图保存在 `build/overview-validation/glass` 与 `build/overview-validation/dark`。规格校验与 `git diff --check` 通过。
- CoreSimulator 已启动，最新应用已重新 launch 并保持运行。当前安装的 Xcode 包不含 Simulator.app，无法打开独立模拟器窗口；验证通过 simctl + XCTest 及实际截图完成。
