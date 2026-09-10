# Inspiration Control Capture Tasks

## 阶段 1：规格冻结

- [x] 完成 `spec.md`
- [x] 完成 `module-plan.md`
- [x] 完成系统能力与现有实现自检

## 阶段 2：基础设施

- [x] 确认 App Group 路由、Capture persistence port 与 KMP 数据结构可复用
- [x] 新增应用内快速灵感 Sheet
- [x] 新增后台创建灵感 App Intent

## 阶段 3：功能实现

- [x] 改造 Deadliner Control 使用 composer 路由
- [x] Focus/Rich 主壳层消费 composer 路由
- [x] 暴露“创建灵感”快捷指令动作与 App Shortcut
- [x] 补充关键文本校验测试
- [x] 大型改动完成后统一编译

## 阶段 4：验证与回写

- [x] 执行规格校验
- [x] 执行大文件扫描
- [x] 回写最终实现状态

## 验证记录

- `git diff --check`：通过。
- 规格校验：`validate_feature_spec.py specs/inspiration-control-capture` 通过。
- 技能大文件扫描：`check_large_core_files.py` 通过；提供的后缀清单仅覆盖 `.ets`，因此额外统计本轮 Swift 文件有效行数：`MainView.swift` 455、`RichMainView.swift` 715、`QuickInspirationCaptureSheet.swift` 65、`CreateInspirationIntent.swift` 30，其余新增文件均低于 20，全部低于 1000 行。
- Swift parse：本轮新增和修改的主壳层、Control、Intent、Sheet、规则与测试文件通过。
- iOS 26 SDK 隔离 typecheck：`CreateInspirationIntent`、`DeadlinerShortcutsProvider` 与 `QuickInspirationCaptureSheet` 通过；使用临时最小依赖桩，不修改项目配置。
- 文本规则可执行检查：首尾空白裁剪、内部换行保留、纯空白拒绝三项通过；同样添加了 `InspirationCaptureTextTests` 供项目测试目标执行。
- Widget Extension：`xcodebuild -target DeadlinerWidgetExtension` 构建成功；仅有既有 `Text + Text` 弃用警告。
- 完整 `Deadliner` Scheme：仍在 Swift 编译前被既有 `actool` / Watch App `DeadlinerDefault` icon 异常阻断；本轮未修改或规避图标资源配置。构建输出为 `Exception while running actool` / `None of the input catalogs contained ... DeadlinerDefault`。
