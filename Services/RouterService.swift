import Foundation

enum RoutingDecision {
    case skip(reason: String)
    case routeToTarget(target: String, params: [String: Any], confidence: Double, reasoning: String)

    var mode: String {
        switch self {
        case .skip: return "skip"
        case .routeToTarget(let target, _, _, _): return target
        }
    }
}

enum RouterService {
    static func route(
        input: String,
        service: AIService,
        model: String,
        config: RouterConfig
    ) async -> RoutingDecision? {
        // 如果启用了 Qwen3.5-4B 路由器，使用专用路由逻辑
        if config.enableQwenRouter {
            return await routeWithQwen(input: input, config: config)
        }
        
        // 否则使用原有的通用路由逻辑
        let systemPrompt = SystemPromptComposer.compose(
            basePrompt: config.prompt,
            scope: .router,
            availableTools: ToolRegistry.shared.getAllTools()
        )
        let messages = [
            Message.system(systemPrompt),
            Message.user(input)
        ]

        do {
            let response = try await service.sendMessage(
                messages,
                tools: [],
                model: model,
                maxTokens: config.maxTokens
            )

            guard let content = response.content else { return nil }

            return parseRoutingResponse(content)
        } catch {
            RioLogger.service.error("路由调用失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    // MARK: - Qwen3.5-4B 专用路由
    
    private static func routeWithQwen(
        input: String,
        config: RouterConfig
    ) async -> RoutingDecision? {
        guard let url = URL(string: "\(config.qwenBaseUrl)/v1/chat/completions") else {
            RioLogger.service.error("Qwen 路由 URL 无效: \(config.qwenBaseUrl, privacy: .public)")
            return nil
        }
        
        // 构建路由提示词
        let systemPrompt = buildQwenRoutingPrompt(targets: config.routingTargets)
        
        let messages: [[String: Any]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": input]
        ]
        
        // 构建请求体，参考用户提供的 Python 代码
        var body: [String: Any] = [
            "model": config.qwenModel,
            "messages": messages,
            "max_tokens": config.maxTokens,
            "temperature": config.temperature,
            "top_p": config.topP,
            "top_k": config.topK,
            "presence_penalty": config.presencePenalty,
            "repetition_penalty": 1.0,
            "stream": false
        ]
        
        // 关闭思考模式（核心铁律）
        if config.disableThinking {
            body["chat_template_kwargs"] = ["enable_thinking": false]
        }
        
        // 强制结构化输出
        body["guided_json"] = RouterConfig.qwenRoutingSchema
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse,
                  httpResponse.statusCode == 200 else {
                RioLogger.service.error("Qwen 路由请求失败")
                return nil
            }
            
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let choices = json["choices"] as? [[String: Any]],
                  let firstChoice = choices.first,
                  let message = firstChoice["message"] as? [String: Any],
                  let content = message["content"] as? String else {
                RioLogger.service.error("Qwen 路由响应解析失败")
                return nil
            }
            
            return parseQwenRoutingResponse(content)
        } catch {
            RioLogger.service.error("Qwen 路由调用失败: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }
    
    private static func buildQwenRoutingPrompt(targets: [RoutingTarget]) -> String {
        let enabledTargets = targets.filter { $0.isEnabled }
        let targetDescriptions = enabledTargets.map { "- \($0.name): \($0.description)" }.joined(separator: "\n")
        
        return """
        你是一个任务路由器。分析用户输入，输出 JSON 决定如何处理。
        
        可用的目标节点：
        \(targetDescriptions)
        
        输出格式：
        {
          "target_node": "目标节点名称",
          "extracted_params": {},
          "confidence": 0.0-1.0,
          "reasoning": "简短理由"
        }
        
        只输出 JSON，不要额外文字。
        """
    }
    
    private static func parseQwenRoutingResponse(_ text: String) -> RoutingDecision? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        
        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let targetNode = json["target_node"] as? String else {
            return nil
        }
        
        let params = json["extracted_params"] as? [String: Any] ?? [:]
        let confidence = json["confidence"] as? Double ?? 0.5
        let reasoning = json["reasoning"] as? String ?? ""
        
        // 映射到原有的路由决策
        switch targetNode {
        case "skip", "chitchat":
            return .skip(reason: reasoning)
        default:
            return .routeToTarget(
                target: targetNode,
                params: params,
                confidence: confidence,
                reasoning: reasoning
            )
        }
    }

    // MARK: - 原有路由逻辑
    
    private static func parseRoutingResponse(_ text: String) -> RoutingDecision? {
        let cleaned = text
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let data = cleaned.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let mode = json["mode"] as? String else {
            return nil
        }

        let reasoning = json["reasoning"] as? String ?? ""
        let confidence = json["confidence"] as? Double ?? 0.5

        switch mode {
        case "skip":
            return .skip(reason: reasoning)
        default:
            return .routeToTarget(
                target: mode,
                params: [:],
                confidence: confidence,
                reasoning: reasoning
            )
        }
    }
}
