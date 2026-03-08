//
//  AIService.swift
//  Deadliner
//
//  Created by Aritx 音唯 on 2026/2/21.
//

import Foundation

public final class AIService {

    public static let shared = AIService()
    private init() {}

    // MARK: - Agent Core (Intent + Content + Memory)
    public func processInput(
        text: String,
        preferredLang: String = "zh-CN",
        sessionContext: String = "",
        sessionSummary: String = ""
    ) async throws -> MixedResult {

        let longTerm = MemoryBank.shared.getLongTermContext()

        let systemPrompt = buildAgentSystemPrompt(
            preferredLang: preferredLang,
            longTermContext: longTerm,
            sessionSummary: sessionSummary,
            sessionContext: sessionContext
        )

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
        ]

        let content = try await fetchFromProvider(messages: messages)
        print("[AIService] Raw Response: \(content)")

        let jsonData = try extractJsonData(from: content)
        let result = try makeDecoder().decode(MixedResult.self, from: jsonData)

        if let newMemories = result.newMemories, !newMemories.isEmpty {
            let filtered = filterMemories(newMemories, result: result, userText: text)
            for mem in filtered {
                MemoryBank.shared.saveMemory(content: mem, category: "Auto-Extracted")
            }
        }

        if let profile = result.userProfile, !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MemoryBank.shared.saveUserProfile(profile)
        }

        return result
    }
    
    // MARK: - Agent Continue (after tool result)
    public func continueAfterTool(
        originalUserText: String,
        toolResult: AIToolResult,
        preferredLang: String = "zh-CN",
        sessionContext: String = "",
        sessionSummary: String = ""
    ) async throws -> MixedResult {

        let longTerm = MemoryBank.shared.getLongTermContext()

        let systemPrompt = buildAgentSystemPrompt(
            preferredLang: preferredLang,
            longTermContext: longTerm,
            sessionSummary: sessionSummary,
            sessionContext: sessionContext,
            toolHint: """
            你正在进行二段对话（工具结果已提供）。
            - 不要再次请求 readTasks（除非用户明确要求刷新/再查）。
            - 你可以基于工具结果输出新的 tasks/habits proposal（用于新增/补全/纠错），但必须避免重复已存在任务。
            """
        )

        // 把 toolResult 编码成稳定 JSON 字符串
        let toolJson = try encodeToolResult(toolResult)

        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: originalUserText),
            ChatMessage(role: "user", content: "TOOL_RESULT_JSON:\n\(toolJson)")
        ]

        let content = try await fetchFromProvider(messages: messages)
        print("[AIService] Raw Response (after tool): \(content)")

        let jsonData = try extractJsonData(from: content)
        let result = try makeDecoder().decode(MixedResult.self, from: jsonData)

        // 二段也允许更新记忆/画像（但一般会少很多）
        if let newMemories = result.newMemories, !newMemories.isEmpty {
            let filtered = filterMemories(newMemories, result: result, userText: content)
            for mem in filtered {
                MemoryBank.shared.saveMemory(content: mem, category: "Auto-Extracted")
            }
        }

        if let profile = result.userProfile, !profile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            MemoryBank.shared.saveUserProfile(profile)
        }

        return result
    }

    // MARK: - Legacy APIs (keep)
    public func extractTasks(text: String, preferredLang: String = "zh-CN") async throws -> [AITask] {
        let systemPrompt = buildTaskSystemPrompt(preferredLang: preferredLang)
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
        ]

        let content = try await fetchFromProvider(messages: messages)
        print("[AIService] Raw Response: \(content)")

        let jsonData = try extractJsonData(from: content)
        let resultObj = try makeDecoder().decode(MixedResult.self, from: jsonData)
        return resultObj.tasks ?? []
    }

    public func extractHabits(text: String, preferredLang: String = "zh-CN") async throws -> [AIHabit] {
        let systemPrompt = buildHabitSystemPrompt(preferredLang: preferredLang)
        let messages = [
            ChatMessage(role: "system", content: systemPrompt),
            ChatMessage(role: "user", content: text)
        ]

        let content = try await fetchFromProvider(messages: messages)
        print("[AIService] Raw Response: \(content)")

        let jsonData = try extractJsonData(from: content)
        let resultObj = try makeDecoder().decode(MixedResult.self, from: jsonData)
        return resultObj.habits ?? []
    }
    
    public func validateConfig(apiKey: String, baseUrl: String, modelId: String) async throws {
        let messages = [
            ChatMessage(role: "user", content: "Ping")
        ]
        
        // 直接使用传入的参数构建请求，不读取 LocalValues
        let endpoint = normalizeChatCompletionsEndpoint(baseUrl: baseUrl)
        guard let url = URL(string: endpoint) else {
            throw AIError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = ChatRequest(model: modelId, messages: messages, temperature: 0.1)
        request.httpBody = try JSONEncoder().encode(chatRequest)

        let (data, response) = try await URLSession.shared.data(for: request)

        if let httpResponse = response as? HTTPURLResponse,
           !(200...299).contains(httpResponse.statusCode) {
            print("[AIService] Validation HTTP Error \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
            throw AIError.networkError(URLError(.badServerResponse))
        }
        
        _ = try makeDecoder().decode(ChatResponse.self, from: data)
    }

    // MARK: - Networking (基本不动，仅更稳拼接)
    private func fetchFromProvider(messages: [ChatMessage]) async throws -> String {
        let apiKey = await LocalValues.shared.getAIApiKey()
        let baseUrl = await LocalValues.shared.getAIBaseUrl()
        let modelId = await LocalValues.shared.getAIModel()

        guard !apiKey.isEmpty else { throw AIError.missingAPIKey }

        let endpoint = normalizeChatCompletionsEndpoint(baseUrl: baseUrl)
        guard let url = URL(string: endpoint) else {
            throw AIError.networkError(URLError(.badURL))
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let chatRequest = ChatRequest(model: modelId, messages: messages, temperature: 0.1)
        request.httpBody = try JSONEncoder().encode(chatRequest)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                print("[AIService] HTTP Error \(httpResponse.statusCode): \(String(data: data, encoding: .utf8) ?? "")")
                throw AIError.networkError(URLError(.badServerResponse))
            }

            let chatResponse = try makeDecoder().decode(ChatResponse.self, from: data)
            guard let content = chatResponse.choices.first?.message.content, !content.isEmpty else {
                throw AIError.emptyResponse
            }
            return content

        } catch let error as AIError {
            throw error
        } catch {
            throw AIError.networkError(error)
        }
    }

    private func normalizeChatCompletionsEndpoint(baseUrl: String) -> String {
        let trimmed = baseUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let noTailSlash = trimmed.hasSuffix("/") ? String(trimmed.dropLast()) : trimmed
        return "\(noTailSlash)/chat/completions"
    }

    // MARK: - JSON extraction (更鲁棒：支持混杂文本)
    private func extractJsonData(from raw: String) throws -> Data {
        let cleaned = stripCodeFence(raw)

        if let direct = cleaned.data(using: .utf8), isLikelyJsonObject(cleaned) {
            return direct
        }

        if let extracted = extractFirstJsonObject(from: cleaned),
           let data = extracted.data(using: .utf8) {
            return data
        }

        throw AIError.parsingFailed
    }

    private func stripCodeFence(_ str: String) -> String {
        var s = str.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("```json") { s = String(s.dropFirst(7)) }
        else if s.hasPrefix("```") { s = String(s.dropFirst(3)) }
        if s.hasSuffix("```") { s = String(s.dropLast(3)) }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func isLikelyJsonObject(_ s: String) -> Bool {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.first == "{" && t.last == "}"
    }

    private func extractFirstJsonObject(from s: String) -> String? {
        let chars = Array(s)
        guard let start = chars.firstIndex(of: "{") else { return nil }

        var depth = 0
        var inString = false
        var escape = false

        for i in start..<chars.count {
            let c = chars[i]

            if inString {
                if escape { escape = false }
                else if c == "\\" { escape = true }
                else if c == "\"" { inString = false }
                continue
            } else {
                if c == "\"" { inString = true; continue }
                if c == "{" { depth += 1 }
                if c == "}" { depth -= 1 }
                if depth == 0 { return String(chars[start...i]) }
            }
        }
        return nil
    }

    private func makeDecoder() -> JSONDecoder {
        JSONDecoder()
    }

    // MARK: - Prompt builders (时间精度修复 + Agent规则)
    private func buildAgentSystemPrompt(
        preferredLang: String,
        longTermContext: String,
        sessionSummary: String,
        sessionContext: String,
        toolHint: String? = nil
    ) -> String {
        let now = isoNowString()
        let tz = TimeZone.current.identifier

        let summary = String(sessionSummary.prefix(600))
        let ctx = String(sessionContext.prefix(1200))
        let ltm = String(longTermContext.prefix(900))

        return """
    你是 Deadliner AI，一个“日程/习惯/闲聊”全能解析器（Agent Core）。
    
    \(toolHint.map { "【工具阶段提示】\n\($0)\n" } ?? "")
    
    【当前时间】\(now)
    【当前时区】\(tz)
    【用户语言】\(preferredLang)

    【长期记忆（画像+少量事实）】
    \(ltm)

    【会话摘要（上一轮累计，<=600字符）】
    \(summary)

    【短期对话窗口（最近内容，<=1200字符）】
    \(ctx)

    要求：保持连续性。若与“短期窗口/会话摘要”冲突，优先以短期为准；若与“用户画像”冲突，优先以短期为准并可在 newMemories/userProfile 中修正。

    必须输出纯 JSON（禁止 markdown/解释文字），字段规则如下：

    你必须输出：
    1) primaryIntent：只能是 "ExtractTasks" / "ExtractHabits" / "Chat"
    2) tasks：当 primaryIntent="ExtractTasks" 时填充，否则可以省略或空数组
    3) habits：当 primaryIntent="ExtractHabits" 时填充，否则可以省略或空数组
    4) newMemories：抽取新的稳定偏好/事实（短句数组；可为空）
    5) chatResponse：仅当 primaryIntent="Chat" 时给一句简短回复（否则可省略或空）
    6) sessionSummary：必须输出。用 5-10 条要点总结“当前会话状态/未完成事项/确认流程”，总长度 <= 600 字符
    7) userProfile：仅当你认为需要更新画像时输出（1段话，<= 420 字符）；否则可以省略或输出空字符串
    8) toolCalls：当你需要读取用户真实任务列表才能回答时，输出 toolCalls（数组）。否则省略或输出空数组。

    toolCalls 规则：
    - tool 目前只能是 "readTasks"
    - args 必须是：
        - timeRangeDays: Int（默认 7）
        - status: "OPEN" | "DONE" | "ALL"（默认 "OPEN"）
        - keywords: string[]（最多 3 个；每个最多 12 字；可为空）
        - limit: Int（默认 20，最大 50）
        - sort: "DUE_ASC" | "UPDATED_DESC"（默认 "DUE_ASC"）
    - reason: 用 1 句话解释为什么要读任务（给用户授权卡展示）
    
    【关键词强规则（必须遵守）】：
    - toolCalls.args.keywords 只能来自“用户本轮输入 text”中明确出现的词或短语。
    - 禁止从长期记忆、会话摘要、短期窗口中推断/补充 keywords。
    - 若用户输入是泛查询（如“这周/最近/有哪些任务/列出任务”）且未指定主题词，则 keywords 必须是空数组或省略。

    【二段工具回灌规则】：
    - 如果你在用户消息中看到以 "TOOL_RESULT_JSON:" 开头的工具结果，表示任务数据已提供。
      你必须基于工具结果直接给出最终 JSON 输出。
    - 你可以输出新的 tasks/habits proposal（用于新增、补全或纠错），但必须遵循：
      1) 除非用户明确要求“刷新/再查”，否则不要再次输出 toolCalls。
      2) 若工具结果中已存在高度相似的任务（同名或同义，且截止时间接近），不要重复输出同一任务；可以在 chatResponse 里提示“已存在，是否需要调整/合并”。
      3) 若用户的请求是“列出/查看/总结”，优先给 chatResponse；proposal 仅在确实需要用户确认新增/变更时输出。
    
    【记忆抽取强规则】：
    - newMemories 只能包含“长期稳定偏好/事实/约束”（例如：时间格式偏好、语言偏好、工作流偏好、长期项目背景）。
    - 禁止把任何“待办/任务/提醒/本次要做的事”写入 newMemories（包括用户说的任务、你解析出的 tasks、你从 repo 读到的 tasks）。
    - 如果用户输入是“提取任务/列出任务/这周有什么任务/添加任务”等任务相关请求，则 newMemories 必须为空数组或省略。

    【时间推算强规则】：
    - dueTime 必须严格是 "yyyy-MM-dd HH:mm" 或 ""。
    - 若用户给了日期/相对日期但无具体时刻：必须补全默认时刻：
      - 早上/上午 -> 09:00
      - 中午 -> 12:00
      - 下午 -> 15:00
      - 晚上/夜里 -> 20:00
      - 只说“明天/下周/周三”等无时段词 -> 09:00
    - 若用户明确说“不确定时间/到时候再说” -> dueTime = ""

    【任务字段规则】：
    - name：2-8字最佳，不超过15字；去冗词。
    - note：细节补充；无则 ""。
    
    【去重规则（强制）】：
    - 若 readTasks 返回的 tasks 列表中存在 name 与新任务 name 相同或非常相似（编辑距离很近/同义），且 dueTime 相差 <= 6 小时：
      - 不要输出新的 tasks proposal
      - 在 chatResponse 中询问是否要“修改原任务的截止时间/备注”或“合并”

    【习惯字段规则】：
    - period：只能 "DAILY"/"WEEKLY"/"MONTHLY"，未提及默认 "DAILY"
    - timesPerPeriod：整数，未提及默认 1
    - goalType：只能 "PER_PERIOD"/"TOTAL"，默认 "PER_PERIOD"
    - totalTarget：仅当 goalType="TOTAL" 时给整数

    返回 JSON 示例（结构，不是固定值）：
    {
      "primaryIntent": "ExtractTasks | ExtractHabits | Chat",
      "tasks": [{"name":"","dueTime":"yyyy-MM-dd HH:mm","note":""}],
      "habits": [{"name":"","period":"DAILY","timesPerPeriod":1,"goalType":"PER_PERIOD","totalTarget":300}],
      "newMemories": ["..."],
      "chatResponse": "...",
      "sessionSummary": "...",
      "userProfile": "...",
      "toolCalls": [{"tool":"readTasks","args":{"timeRangeDays":7,"status":"OPEN","keywords":["..."],"limit":20,"sort":"DUE_ASC"},"reason":"..."}]
    }
    """
    }

    private func buildTaskSystemPrompt(preferredLang: String) -> String {
        let now = isoNowString()
        let tz = TimeZone.current.identifier

        return """
你是 Deadliner AI 的任务提取器。
【当前时间】\(now)
【当前时区】\(tz)
【用户语言】\(preferredLang)

只输出纯 JSON。

- name：2-8字最佳，不超过15字；去冗词。
- note：细节补充；无则 ""。
- dueTime：必须严格 "yyyy-MM-dd HH:mm" 或 ""；
  若用户给了日期/相对日期但无时刻：按规则补齐默认时刻（上午09:00/中午12:00/下午15:00/晚上20:00；无时段词默认09:00）。
  若用户明确不确定时间：""。

返回：
{"primaryIntent":"ExtractTasks","tasks":[{"name":"","dueTime":"yyyy-MM-dd HH:mm","note":""}]}
"""
    }

    private func buildHabitSystemPrompt(preferredLang: String) -> String {
        let now = isoNowString()
        let tz = TimeZone.current.identifier

        return """
你是 Deadliner AI 的习惯提取器。
【当前时间】\(now)
【当前时区】\(tz)
【用户语言】\(preferredLang)

只输出纯 JSON。

- name：2-8字
- period：只能 "DAILY"/"WEEKLY"/"MONTHLY"，未提及默认 "DAILY"
- timesPerPeriod：整数，未提及默认 1
- goalType：只能 "PER_PERIOD"/"TOTAL"，默认 "PER_PERIOD"
- totalTarget：仅当 goalType="TOTAL" 时给整数，否则不要返回该字段

返回：
{"primaryIntent":"ExtractHabits","habits":[{"name":"","period":"DAILY","timesPerPeriod":1,"goalType":"PER_PERIOD"}]}
"""
    }

    private func isoNowString() -> String {
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return fmt.string(from: Date())
    }
    
    // MARK: - Tool Result Encode
    private func encodeToolResult(_ toolResult: AIToolResult) throws -> String {
        let enc = JSONEncoder()
        // 统一 ISO8601（否则 Date 默认是 seconds-since-1970，AI 不好读）
        enc.dateEncodingStrategy = .iso8601
        enc.outputFormatting = [.sortedKeys] // 让 diff 更稳定（可选）
        let data = try enc.encode(toolResult)
        guard let s = String(data: data, encoding: .utf8) else {
            throw AIError.parsingFailed
        }
        return s
    }
    
    private func filterMemories(_ mems: [String], result: MixedResult, userText: String) -> [String] {
        let q = userText.lowercased()

        // 1) 任务/待办场景：直接不存记忆（最硬）
        if (result.primaryIntent ?? "").contains("ExtractTasks") ||
           (result.primaryIntent ?? "").contains("ExtractHabits") ||
           looksLikeTaskQuery(q) {
            return []
        }

        // 2) 如果 mem 与 tasks/habits 高度相关，也过滤
        let taskNames = Set((result.tasks ?? []).map { $0.name.lowercased() })
        let habitNames = Set((result.habits ?? []).map { $0.name.lowercased() })

        return mems
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { m in
                let s = m.lowercased()

                // 2.1 过滤“像任务”的句子（含时间、deadline、明天、本周、提交、完成 等）
                if looksLikeTaskMemory(s) { return false }

                // 2.2 过滤与任务名/习惯名重合的
                if taskNames.contains(s) || habitNames.contains(s) { return false }

                // 2.3 过滤包含任何任务名的（防止“记住：交系统论作业”）
                if taskNames.contains(where: { !($0.isEmpty) && s.contains($0) }) { return false }

                return true
            }
    }

    private func looksLikeTaskQuery(_ q: String) -> Bool {
        let patterns = ["有什么任务", "有哪些任务", "任务列表", "这周", "本周", "明天", "今天", "待办", "deadline", "ddl", "to do", "todo", "提醒我"]
        return patterns.contains { q.contains($0) }
    }

    private func looksLikeTaskMemory(_ s: String) -> Bool {
        // 时间/日期痕迹 + 动词痕迹
        let timeHints = ["-", ":", "点", "号", "周", "明天", "今天", "截止", "due", "deadline"]
        let actionHints = ["交", "提交", "完成", "做", "开会", "复习", "写", "买", "打电话", "发送"]

        let hasTime = timeHints.contains { s.contains($0) }
        let hasAction = actionHints.contains { s.contains($0) }

        // 很粗暴但有效：像“任务”的就别存
        return hasTime && hasAction
    }
}
