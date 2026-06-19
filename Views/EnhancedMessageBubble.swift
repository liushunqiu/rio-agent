import SwiftUI

// MARK: - Enhanced Message Bubble

struct EnhancedMessageBubble: View {
    let message: Message
    let isToolExecuting: Bool
    let currentToolCallId: String?
    let toolResultsById: [String: ToolResult]

    var body: some View {
        VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 8) {
            MessageSourceHeader(message: message)

            // Thinking card (separate from reply, shown first)
            if let thinking = message.thinkingContent, !thinking.isEmpty {
                ThinkingCard(
                    content: thinking,
                    duration: message.thinkingDuration,
                    isStreaming: message.isStreaming
                )
            }
            
            // Message content
            if !message.content.isEmpty {
                MessageContent(message: message)
            }
            
            // Tool calls
            if let toolCalls = message.toolCalls {
                ForEach(toolCalls) { toolCall in
                    let isCurrentTool = currentToolCallId == toolCall.id
                    let isExecuting = isToolExecuting && isCurrentTool
                    let isCompleted = !isExecuting && toolCallHasResult(toolCall)
                    let result = getToolResult(for: toolCall)

                    if isFileOperationTool(toolCall.name) {
                        FileOperationToolCard(
                            toolCall: toolCall,
                            isExecuting: isExecuting,
                            isCompleted: isCompleted,
                            executionResult: result
                        )
                    } else {
                        EnhancedToolCallCard(
                            toolCall: toolCall,
                            isExecuting: isExecuting,
                            isCompleted: isCompleted,
                            executionResult: result
                        )
                    }
                }
            }
            
            // Tool results (if not already shown in tool cards)
            if let toolResults = message.toolResults {
                ForEach(toolResults, id: \.toolCallId) { result in
                    // Only show results that aren't already displayed in tool cards
                    if Self.shouldDisplayStandaloneToolResult(
                        toolCallId: result.toolCallId,
                        toolCalls: message.toolCalls
                    ) {
                        EnhancedToolResultCard(
                            result: result,
                            toolCallName: getToolCallName(for: result.toolCallId)
                        )
                    }
                }
            }
            
            // Streaming indicator
            if message.isStreaming && message.content.isEmpty && (message.thinkingContent?.isEmpty ?? true) {
                HStack(spacing: 8) {
                    StreamingDots()
                    Text("思考中...")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Theme.textSecondary)
                }
                .padding(.vertical, 6)
            }
            
            // Timestamp & actions
            if !message.content.isEmpty {
                MessageFooter(message: message)
            }
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: message.role == .user ? .trailing : .leading)
    }
    
    // MARK: - Helper Methods

    private func toolCallHasResult(_ toolCall: ToolCall) -> Bool {
        return findToolResult(for: toolCall.id) != nil
    }

    private func toolCallHasResult(for toolCallId: String) -> Bool {
        return findToolResult(for: toolCallId) != nil
    }

    static func shouldDisplayStandaloneToolResult(toolCallId: String, toolCalls: [ToolCall]?) -> Bool {
        !(toolCalls?.contains(where: { $0.id == toolCallId }) ?? false)
    }

    private func getToolResult(for toolCall: ToolCall) -> ToolResult? {
        return findToolResult(for: toolCall.id)
    }

    private func getToolCallName(for toolCallId: String) -> String {
        return message.toolCalls?.first(where: { $0.id == toolCallId })?.name ?? "unknown"
    }

    private func findToolResult(for toolCallId: String) -> ToolResult? {
        toolResultsById[toolCallId]
    }

    private func isFileOperationTool(_ name: String) -> Bool {
        let lower = name.lowercased()
        return lower.contains("write") || lower.contains("edit")
            || lower.contains("create") || lower.contains("patch")
            || lower.contains("delete")
    }
}

struct MessageSourceHeader: View {
    let message: Message

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))

            Text(title)
                .font(.system(size: 11, weight: .semibold))

            if let modelLabel {
                Text(modelLabel)
                    .font(.system(size: 10, design: .monospaced))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(Theme.textTertiary)
            }
        }
        .foregroundColor(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(color.opacity(0.18), lineWidth: 1)
        )
        .frame(maxWidth: message.role == .user ? 620 : 820, alignment: message.role == .user ? .trailing : .leading)
    }

    private var title: String {
        if message.role == .user {
            return "用户"
        }
        if message.isFinalAnswer {
            return "最终答复"
        }
        if let agentName = message.source?.agentName?.trimmingCharacters(in: .whitespacesAndNewlines),
           !agentName.isEmpty {
            return agentName
        }
        return fallbackTitle
    }

    private var modelLabel: String? {
        guard message.role != .user else { return nil }
        let provider = message.source?.providerName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let model = message.source?.modelName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if provider.isEmpty && model.isEmpty { return nil }
        if provider.isEmpty { return model }
        if model.isEmpty { return provider }
        return "\(provider) / \(model)"
    }

    private var fallbackTitle: String {
        if message.isFinalAnswer {
            return "最终答复"
        }
        switch message.role {
        case .user: return "用户"
        case .assistant: return "助手"
        case .system: return "系统"
        }
    }

    private var icon: String {
        if message.isFinalAnswer {
            return "checkmark.seal.fill"
        }
        switch message.role {
        case .user: return "person.fill"
        case .assistant: return "sparkles"
        case .system: return "gearshape.fill"
        }
    }

    private var color: Color {
        if message.isFinalAnswer {
            return Theme.statusSuccess
        }
        switch message.role {
        case .user: return Theme.accentPrimary
        case .assistant: return Theme.statusInfo
        case .system: return Theme.textTertiary
        }
    }
}

// MARK: - Enhanced Chat View

struct EnhancedChatView: View {
    let messages: [Message]
    let isProcessing: Bool
    let currentToolCallId: String?
    let currentPipeline: ExecutionPipeline?
    let singleAgentVerification: VerifierService.VerificationOutcome?
    let currentTaskPlan: TaskPlan?
    let pendingUserDecision: AgentEngine.PendingUserDecision?

    /// 自动滚动跟随开关
    @State private var autoScrollEnabled = true

    /// 距离底部的偏移（越小越接近底部）
    @State private var bottomOffset: CGFloat = 0
    @State private var visibleViewportHeight: CGFloat = 0

    /// 工具结果索引
    private var toolResultsById: [String: ToolResult] {
        var index: [String: ToolResult] = [:]
        for result in messages.flatMap({ $0.toolResults ?? [] }) {
            index[result.toolCallId] = result
        }
        return index
    }

    private var visibleMessages: [Message] {
        messages.filter(\.isVisibleInTranscript)
    }

    private var transcriptEntries: [TranscriptEntry] {
        TranscriptEntry.make(from: visibleMessages)
    }

    /// 流式内容变化信号
    private var streamingSignal: Int {
        (visibleMessages.last?.content.count ?? 0) + (visibleMessages.last?.thinkingContent?.count ?? 0)
    }

    private var hasVisibleFinalAnswer: Bool {
        visibleMessages.contains(where: \.isFinalAnswer)
    }

    /// 是否接近底部（距离底部 < 120pt 视为接近）
    private var isNearBottom: Bool {
        bottomOffset < 120
    }

    var body: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(spacing: 6, pinnedViews: []) {
                        if currentPipeline != nil || pendingUserDecision != nil || singleAgentVerification != nil {
                            TranscriptRuntimeCard(
                                pipeline: currentPipeline,
                                singleAgentVerification: singleAgentVerification,
                                taskPlan: currentTaskPlan,
                                pendingUserDecision: pendingUserDecision
                            )
                            .padding(.horizontal, 28)
                            .padding(.bottom, 10)
                        }

                        ForEach(transcriptEntries) { entry in
                            switch entry {
                            case .message(let message):
                                EnhancedMessageBubble(
                                    message: message,
                                    isToolExecuting: isProcessing && currentToolCallId != nil,
                                    currentToolCallId: currentToolCallId,
                                    toolResultsById: toolResultsById
                                )
                                .id(message.id)

                            case .activity(let messages, let isSupportingDetail):
                                AgentActivityGroupView(
                                    messages: messages,
                                    isProcessing: isProcessing,
                                    currentToolCallId: currentToolCallId,
                                    toolResultsById: toolResultsById,
                                    isSupportingDetail: isSupportingDetail
                                )
                                .id(messages.first?.id)
                            }
                        }

                        // TaskPlan 面板（Multi-Agent 模式）
                        if let taskPlan = currentTaskPlan {
                            TaskPlanView(
                                plan: taskPlan,
                                prefersCondensedCompletedState: hasVisibleFinalAnswer
                            )
                                .padding(.horizontal, 28)
                                .padding(.vertical, 8)
                        }

                        // 底部锚点（用于滚动）
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 28)
                    .background(
                        GeometryReader { geo in
                            Color.clear.preference(
                                key: BottomOffsetPreferenceKey.self,
                                value: geo.frame(in: .named("scroll")).maxY
                            )
                        }
                    )
                }
                .coordinateSpace(name: "scroll")
                .background(
                    GeometryReader { geo in
                        Color.clear.preference(
                            key: ScrollViewportHeightPreferenceKey.self,
                            value: geo.size.height
                        )
                    }
                )
                .onPreferenceChange(BottomOffsetPreferenceKey.self) { contentBottom in
                    let newOffset = Self.distanceFromBottom(
                        contentBottom: contentBottom,
                        viewportHeight: visibleViewportHeight
                    )
                    bottomOffset = newOffset
                    if autoScrollEnabled && newOffset > 140 && !isProcessing {
                        autoScrollEnabled = false
                    }
                }
                .onPreferenceChange(ScrollViewportHeightPreferenceKey.self) { height in
                    visibleViewportHeight = height
                }
                // 新消息到达时滚动
                .onChange(of: messages.count) { oldCount, newCount in
                    if newCount > oldCount && autoScrollEnabled {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                // 流式内容更新时滚动
                .onChange(of: streamingSignal) { _, _ in
                    if autoScrollEnabled && (visibleMessages.last?.isStreaming == true || isProcessing) {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                // 工具调用变化时滚动
                .onChange(of: currentToolCallId) { _, _ in
                    if autoScrollEnabled && isProcessing {
                        scrollToBottom(proxy: proxy, animated: true)
                    }
                }
                .onAppear {
                    // 初始加载滚动到底部
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        scrollToBottom(proxy: proxy, animated: false)
                    }
                }
                
                // 浮动控制按钮
                if !visibleMessages.isEmpty {
                    VStack(spacing: 10) {
                        // 自动跟随开关
                        FloatingButton(
                            icon: autoScrollEnabled ? "arrow.down.circle.fill" : "arrow.down.circle",
                            label: autoScrollEnabled ? "自动跟随" : (isNearBottom ? "恢复跟随" : "回到底部"),
                            isActive: autoScrollEnabled,
                            badge: !isNearBottom ? true : nil
                        ) {
                            if autoScrollEnabled {
                                autoScrollEnabled = false
                            } else {
                                autoScrollEnabled = true
                                scrollToBottom(proxy: proxy, animated: true)
                            }
                        }
                    }
                    .padding(.trailing, 24)
                    .padding(.bottom, 24)
                }
            }
        }
    }

    // MARK: - Helpers

    private func scrollToBottom(proxy: ScrollViewProxy, animated: Bool) {
        let action = {
            proxy.scrollTo("bottom", anchor: .bottom)
        }

        if animated {
            withAnimation(.easeOut(duration: 0.25)) {
                action()
            }
        } else {
            action()
        }
    }

    static func distanceFromBottom(contentBottom: CGFloat, viewportHeight: CGFloat) -> CGFloat {
        max(0, contentBottom - viewportHeight)
    }
}

private struct TranscriptRuntimeCard: View {
    let pipeline: ExecutionPipeline?
    let singleAgentVerification: VerifierService.VerificationOutcome?
    let taskPlan: TaskPlan?
    let pendingUserDecision: AgentEngine.PendingUserDecision?

    private var exceptionalStage: PipelineStage? {
        pipeline?.stages.last(where: { $0.status == .failed || $0.status == .cancelled })
    }

    private var currentStage: PipelineStage? {
        pipeline?.currentStage
    }

    private var completedStageCount: Int {
        pipeline?.stages.filter { $0.status == .completed || $0.status == .skipped }.count ?? 0
    }

    private var actionableSubTaskCount: Int {
        taskPlan?.subTasks.filter(\.needsAttention).count ?? 0
    }

    private var prioritizedBlockedSubTask: SubTask? {
        taskPlan?.subTasks.first(where: { $0.recoveryContext != nil && $0.needsAttention })
    }

    private var prioritizedFailedSubTask: SubTask? {
        taskPlan?.subTasks.first(where: { $0.status == .failed }) ??
            taskPlan?.subTasks.first(where: { $0.verificationStatus == .needsRetry })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("当前流程")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)
                    Text(headline)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                }

                Spacer()

                TranscriptStatusBadge(
                    icon: statusIcon,
                    text: statusText,
                    tone: statusTone
                )
            }

            HStack(spacing: 8) {
                if let pipeline {
                    TranscriptMetaBadge(
                        icon: "list.number",
                        label: "阶段",
                        value: "\(completedStageCount)/\(pipeline.stages.count)"
                    )
                }
                if let taskPlan {
                    TranscriptMetaBadge(
                        icon: "square.stack.3d.up",
                        label: "子任务",
                        value: "\(taskPlan.subTasks.count)"
                    )
                }
                if actionableSubTaskCount > 0 {
                    TranscriptMetaBadge(
                        icon: "exclamationmark.bubble",
                        label: "待处理",
                        value: "\(actionableSubTaskCount)",
                        tone: Theme.statusWarning
                    )
                }
            }

            if let focusText {
                TranscriptInsightRow(
                    icon: focusIcon,
                    title: focusTitle,
                    detail: focusText,
                    tone: focusTone
                )
            }

            TranscriptInsightRow(
                icon: "sparkle.magnifyingglass",
                title: "下一步建议",
                detail: nextActionText,
                tone: nextActionTone
            )
        }
        .padding(14)
        .frame(maxWidth: 820, alignment: .leading)
        .background(Theme.bgSecondary.opacity(0.78))
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(statusTone.opacity(0.20), lineWidth: 1)
        )
    }

    private var headline: String {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return "等待覆盖确认"
            case .chooseExecutionModeForTask:
                return "等待执行模式确认"
            }
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry:
                return "答案需要修订"
            case .unverified:
                return "结果尚未验证"
            case .verified:
                return "进入结果复核"
            }
        }
        if let exceptionalStage {
            return exceptionalStage.status == .failed ? failureHeadline : "流程已停止"
        }
        if pipeline?.overallStatus == .completed {
            return "进入交付复核"
        }
        if let currentStage {
            return currentStage.type.title
        }
        return "等待开始"
    }

    private var statusText: String {
        if pendingUserDecision != nil {
            return "等待确认"
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry: return "需修订"
            case .unverified: return "未验证"
            case .verified: return "已验证"
            }
        }
        switch pipeline?.overallStatus {
        case .pending: return "待开始"
        case .running: return "执行中"
        case .completed: return "已完成"
        case .cancelled: return "已停止"
        case .failed: return "需处理"
        case .skipped: return "已跳过"
        case .none: return "流程"
        }
    }

    private var statusIcon: String {
        if pendingUserDecision != nil {
            return "questionmark.circle.fill"
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry: return "exclamationmark.shield.fill"
            case .unverified: return "questionmark.app.dashed"
            case .verified: return "checkmark.shield.fill"
            }
        }
        switch pipeline?.overallStatus {
        case .pending: return "clock"
        case .running: return "arrow.triangle.2.circlepath"
        case .completed: return "checkmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .failed: return "exclamationmark.triangle.fill"
        case .skipped: return "minus.circle.fill"
        case .none: return "point.3.connected.trianglepath.dotted"
        }
    }

    private var statusTone: Color {
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .verified: return Theme.statusSuccess
            case .unverified: return Theme.statusWarning
            case .needsRetry: return Theme.statusError
            }
        }
        switch pipeline?.overallStatus {
        case .pending: return Theme.textTertiary
        case .running: return Theme.statusInfo
        case .completed: return Theme.statusSuccess
        case .cancelled: return Theme.textTertiary
        case .failed: return Theme.statusError
        case .skipped: return Theme.textTertiary
        case .none: return Theme.accentPrimary
        }
    }

    private var focusTitle: String {
        if pendingUserDecision != nil {
            return "等待输入"
        }
        if singleAgentVerification != nil {
            return "验证摘要"
        }
        if pipeline?.overallStatus == .completed {
            return "交付摘要"
        }
        if let exceptionalStage {
            return exceptionalStage.status == .failed ? failureSourceLabel : "停止原因"
        }
        return "当前焦点"
    }

    private var focusIcon: String {
        if pendingUserDecision != nil {
            return "questionmark.circle"
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .verified:
                return "checkmark.seal"
            case .unverified:
                return "exclamationmark.bubble"
            case .needsRetry:
                return "exclamationmark.triangle"
            }
        }
        if let exceptionalStage {
            return exceptionalStage.status == .failed ? failureSourceIcon : "pause.circle.fill"
        }
        return currentStage?.type.icon ?? "point.3.connected.trianglepath.dotted"
    }

    private var focusTone: Color {
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .verified:
                return Theme.statusSuccess
            case .unverified:
                return Theme.statusWarning
            case .needsRetry:
                return Theme.statusError
            }
        }
        if let exceptionalStage {
            return exceptionalStage.status == .failed ? Theme.statusError : Theme.textTertiary
        }
        return Theme.statusInfo
    }

    private var focusText: String? {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return "系统正在等待你确认是否覆盖已有 AGENT.md。回复“是”继续覆盖，回复其他内容取消覆盖，也可以直接输入新任务。"
            case .chooseExecutionModeForTask:
                return "系统已经完成执行模式判断，正在等待你决定继续多 Agent，还是改为单 Agent。"
            }
        }
        if let singleAgentVerification {
            return singleAgentVerification.summary
        }
        if let exceptionalStage {
            return exceptionalStage.status == .failed ? failedStageFocusText(for: exceptionalStage) : stageSummary(for: exceptionalStage)
        }
        if pipeline?.overallStatus == .completed {
            return "优先核对结果、文件改动和验证状态。"
        }
        if let currentStage {
            return stageSummary(for: currentStage)
        }
        return nil
    }

    private var nextActionText: String {
        if let pendingUserDecision {
            switch pendingUserDecision {
            case .overwriteAgentFile:
                return "先确认是否覆盖 AGENT.md。回复“是”继续覆盖，回复其他内容取消覆盖，也可以直接输入新任务。"
            case .chooseExecutionModeForTask:
                return "先确认执行模式。回复“是”继续多 Agent；回复其他内容改走单 Agent，也可以直接输入新任务，避免继续空等。"
            }
        }
        if let singleAgentVerification {
            switch singleAgentVerification.status {
            case .needsRetry:
                return "当前答案和证据不一致，先根据验证摘要修订结论，再继续输出。"
            case .unverified:
                return "当前缺少足够的完成证据，优先补充读回、测试或命令验证。"
            case .verified:
                return "复核完成后，直接开始下一项任务。"
            }
        }
        if let exceptionalStage {
            switch exceptionalStage.status {
            case .failed:
                if let recoveryContext = prioritizedBlockedSubTask?.recoveryContext {
                    return recoveryContext.recoveryActionDetail
                }
                return failedStageNextActionText
            case .cancelled:
                return "如果停止不是预期行为，恢复上一条任务后重新执行；否则直接开始新任务。"
            default:
                break
            }
        }

        if pipeline?.overallStatus == .completed {
            return "复核无误后，直接开始下一项任务。"
        }

        if let currentStage {
            return "当前正在进行 \(currentStage.type.title)。如果长时间无进展，优先检查该阶段的执行输出与模型配置。"
        }

        return "当前没有活动流程，提交新任务即可开始。"
    }

    private var failureSourceLabel: String {
        guard let subTask = prioritizedFailedSubTask else {
            return "阶段失败"
        }

        switch subTask.resolvedFailureSource {
        case .dependency?:
            return "依赖阻塞"
        case .verification?:
            return "验证未通过"
        case .execution?, .none:
            return "执行失败"
        }
    }

    private var failureHeadline: String {
        guard let subTask = prioritizedFailedSubTask else {
            return "失败阶段待查看"
        }

        switch subTask.resolvedFailureSource {
        case .dependency?:
            return "依赖阻塞待处理"
        case .verification?:
            return "验证未通过待修订"
        case .execution?, .none:
            return "执行失败待修复"
        }
    }

    private var failureSourceIcon: String {
        guard let subTask = prioritizedFailedSubTask else {
            return "bolt.horizontal.circle.fill"
        }

        switch subTask.resolvedFailureSource {
        case .dependency?:
            return "link.badge.plus"
        case .verification?:
            return "checkmark.shield.fill"
        case .execution?, .none:
            return "exclamationmark.triangle.fill"
        }
    }

    private func failedStageFocusText(for stage: PipelineStage) -> String {
        guard let subTask = prioritizedFailedSubTask else {
            return stageSummary(for: stage)
        }

        switch subTask.resolvedFailureSource {
        case .dependency?:
            return "子任务“\(subTask.description)”受前置依赖阻塞，先处理上游失败或补足验证证据。"
        case .verification?:
            return "子任务“\(subTask.description)”验证未通过，先根据验证摘要补证或修订结果。"
        case .execution?, .none:
            return "子任务“\(subTask.description)”执行失败，优先查看失败原因和恢复提示。"
        }
    }

    private var failedStageNextActionText: String {
        guard let subTask = prioritizedFailedSubTask else {
            return "先查看失败阶段和错误摘要；若提示指向模型、路由或 Worker 配置，再进入对应设置修复。"
        }

        switch subTask.resolvedFailureSource {
        case .dependency?:
            return "先处理上游失败或补足验证证据，再重新执行受阻子任务。"
        case .verification?:
            return "先根据验证摘要补证或修订结果，避免把未通过的子任务继续汇总。"
        case .execution?, .none:
            return "先阅读失败原因和验证摘要；如果有恢复提示，优先按提示修复模型、路由或 Worker 配置。"
        }
    }

    private var nextActionTone: Color {
        if pendingUserDecision != nil {
            return Theme.statusWarning
        }
        if singleAgentVerification != nil {
            return statusTone
        }
        if exceptionalStage != nil {
            return statusTone
        }
        if pipeline?.overallStatus == .completed {
            return Theme.statusSuccess
        }
        return Theme.accentPrimary
    }

    private func stageSummary(for stage: PipelineStage) -> String {
        switch stage.details {
        case .empty:
            return "等待阶段细节更新。"
        case .router(let decision, let target, let confidence):
            var parts = [decision]
            if let target, !target.isEmpty {
                parts.append("目标 \(target)")
            }
            if let confidence {
                parts.append("置信度 \(Int((confidence * 100).rounded()))%")
            }
            return parts.joined(separator: " · ")
        case .taskAnalysis(let complexity, let stepCount, let estimatedTime):
            var parts = ["复杂度 \(complexity)", "\(stepCount) 个步骤"]
            if let estimatedTime, !estimatedTime.isEmpty {
                parts.append(estimatedTime)
            }
            return parts.joined(separator: " · ")
        case .dagPlanning(let subTaskCount, let workerCount, let maxDepth):
            return "\(subTaskCount) 个子任务 · \(workerCount) 个 Worker · 深度 \(maxDepth)"
        case .execution(_, let completed, let total, let failed, let cancelled):
            var parts = ["\(completed)/\(total) 已结束"]
            if failed > 0 { parts.append("失败 \(failed)") }
            if cancelled > 0 { parts.append("停止 \(cancelled)") }
            if failed == 0 && cancelled == 0 { parts.append("无阻塞") }
            return parts.joined(separator: " · ")
        case .errorRecovery(let retryCount, let analysis):
            if let analysis, !analysis.isEmpty {
                return "第 \(retryCount) 次重试 · \(analysis)"
            }
            return "第 \(retryCount) 次重试"
        case .verification(let passed, let total, _):
            return "通过 \(passed)/\(total) 项检查"
        case .synthesis(let workerResults):
            return "汇总 \(workerResults) 个结果"
        case .error(let message):
            return message
        case .skipped(let reason):
            return reason
        case .cancelled(let reason):
            return reason
        }
    }
}

private struct TranscriptStatusBadge: View {
    let icon: String
    let text: String
    let tone: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundColor(tone)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(tone.opacity(0.10))
        .cornerRadius(Theme.radiusSM)
    }
}

private struct TranscriptMetaBadge: View {
    let icon: String
    let label: String
    let value: String
    var tone: Color = Theme.accentPrimary

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tone)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(tone.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct TranscriptInsightRow: View {
    let icon: String
    let title: String
    let detail: String
    let tone: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tone)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(detail)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusMD)
    }
}

private enum TranscriptEntry: Identifiable {
    case message(Message)
    case activity(messages: [Message], isSupportingDetail: Bool)

    var id: UUID {
        switch self {
        case .message(let message):
            return message.id
        case .activity(let messages, _):
            return messages.first?.id ?? UUID()
        }
    }

    static func make(from messages: [Message]) -> [TranscriptEntry] {
        var entries: [TranscriptEntry] = []
        var activityBuffer: [Message] = []

        func flushActivity(isSupportingDetail: Bool = false) {
            guard !activityBuffer.isEmpty else { return }
            entries.append(.activity(messages: activityBuffer, isSupportingDetail: isSupportingDetail))
            activityBuffer.removeAll()
        }

        for message in messages {
            if message.isAgentActivity {
                activityBuffer.append(message)
            } else {
                if message.isFinalAnswer && !activityBuffer.isEmpty {
                    entries.append(.message(message))
                    flushActivity(isSupportingDetail: true)
                    continue
                }
                flushActivity()
                entries.append(.message(message))
            }
        }

        flushActivity()
        return entries
    }
}

private extension Message {
    var isAgentActivity: Bool {
        role == .assistant
            && content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && (!(thinkingContent?.isEmpty ?? true) || !(toolCalls?.isEmpty ?? true) || !(toolResults?.isEmpty ?? true))
    }
}

private struct AgentActivityGroupView: View {
    let messages: [Message]
    let isProcessing: Bool
    let currentToolCallId: String?
    let toolResultsById: [String: ToolResult]
    let isSupportingDetail: Bool

    @State private var isExpanded = false
    @State private var hasManualExpansionOverride = false

    private var toolCalls: [ToolCall] {
        messages.flatMap { $0.toolCalls ?? [] }
    }

    private var hasFailure: Bool {
        toolCalls.contains { tool in
            toolResultsById[tool.id]?.status == .error
        }
    }

    private var isRunning: Bool {
        isProcessing && currentToolCallId != nil && toolCalls.contains { $0.id == currentToolCallId }
    }

    private var completedCount: Int {
        toolCalls.filter { toolResultsById[$0.id]?.status == .success }.count
    }

    private var failedCount: Int {
        toolCalls.filter { toolResultsById[$0.id]?.status == .error }.count
    }

    private var cancelledCount: Int {
        toolCalls.filter { toolResultsById[$0.id]?.status == .cancelled }.count
    }

    private var hasCancellation: Bool {
        cancelledCount > 0
    }

    private var isCompletedCleanly: Bool {
        !hasFailure && !hasCancellation && !isRunning && completedCount > 0
    }

    private var isSupportingRecord: Bool {
        isSupportingDetail && isCompletedCleanly
    }

    private var isCompactSupportingRecord: Bool {
        isSupportingRecord && !isExpanded
    }

    private var latestFailedToolCall: ToolCall? {
        toolCalls.last(where: { toolResultsById[$0.id]?.status == .error })
    }

    private var latestFailedResult: ToolResult? {
        guard let latestFailedToolCall else { return nil }
        return toolResultsById[latestFailedToolCall.id]
    }

    private var totalThinkingDuration: TimeInterval {
        messages.compactMap(\.thinkingDuration).reduce(0, +)
    }

    private var summaryText: String {
        if isSupportingRecord {
            var parts = ["\(toolCalls.count) 次工具调用", "\(completedCount) 个完成"]
            if totalThinkingDuration > 0 {
                parts.append(formatDuration(totalThinkingDuration))
            }
            return parts.joined(separator: " · ")
        }

        var parts: [String] = []
        if hasFailure {
            parts.append("有失败项")
        } else if isRunning {
            parts.append("持续执行中")
        } else if hasCancellation {
            parts.append("已停止")
        }
        if !toolCalls.isEmpty {
            parts.append("\(toolCalls.count) 次工具调用")
        }
        if totalThinkingDuration > 0 {
            parts.append(formatDuration(totalThinkingDuration))
        }
        if failedCount > 0 {
            parts.append("\(failedCount) 个失败")
        } else if cancelledCount > 0 {
            parts.append("\(cancelledCount) 个已取消")
            if completedCount > 0 {
                parts.append("\(completedCount) 个完成")
            }
        } else if completedCount > 0 {
            parts.append("\(completedCount) 个完成")
        }
        return parts.isEmpty ? "内部处理" : parts.joined(separator: " · ")
    }

    private var titleText: String {
        if hasFailure { return "执行异常" }
        if isRunning { return "正在执行" }
        if hasCancellation { return "执行已停止" }
        if isSupportingDetail && isCompletedCleanly { return "执行记录" }
        if isCompletedCleanly { return "执行完成" }
        return "内部处理"
    }

    private var statusColor: Color {
        if hasFailure { return Theme.statusError }
        if isRunning { return Theme.statusInfo }
        if hasCancellation { return Theme.textTertiary }
        if isSupportingDetail && isCompletedCleanly { return Theme.textTertiary }
        if isCompletedCleanly { return Theme.textSecondary }
        return Theme.textTertiary
    }

    private var statusIcon: String {
        if hasFailure { return "exclamationmark.triangle.fill" }
        if isRunning { return "arrow.triangle.2.circlepath" }
        if hasCancellation { return "slash.circle" }
        if isSupportingDetail && completedCount > 0 { return "list.bullet.rectangle.portrait" }
        if completedCount > 0 { return "checkmark.circle" }
        return "ellipsis.circle"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: {
                hasManualExpansionOverride = true
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(statusColor)

                    Text(titleText)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(statusColor == Theme.textTertiary ? Theme.textSecondary : statusColor)

                    Text(summaryText)
                        .font(.system(size: 11))
                        .foregroundColor(Theme.textTertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(summaryText)

                    Spacer()

                    if isCompactSupportingRecord {
                        Text("按需展开")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(Theme.textTertiary)
                    }

                    if isRunning {
                        ProgressView()
                            .controlSize(.small)
                            .tint(Theme.statusInfo)
                    }

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Theme.textTertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusMD)
                    .fill(
                        isCompactSupportingRecord
                            ? Theme.bgGlass.opacity(0.14)
                            : (isRunning
                            ? Theme.statusInfo.opacity(0.06)
                            : (isCompletedCleanly && !isExpanded ? Theme.bgGlass.opacity(0.26) : Color.clear))
                    )
            )

            if isExpanded || hasFailure || isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    if hasFailure {
                        ActivityFailureSummaryCard(
                            failedCount: failedCount,
                            cancelledCount: cancelledCount,
                            latestFailedToolName: latestFailedToolCall?.name,
                            latestFailureReason: latestFailedResult.map(ToolResultDisplay.text)
                        )
                    }

                    ForEach(messages) { message in
                        if let thinking = message.thinkingContent, !thinking.isEmpty {
                            ActivityThinkingRow(
                                content: thinking,
                                duration: message.thinkingDuration,
                                isStreaming: message.isStreaming
                            )
                        }

                        ForEach(message.toolCalls ?? []) { toolCall in
                            ActivityToolRow(
                                toolCall: toolCall,
                                result: toolResultsById[toolCall.id],
                                isExecuting: isProcessing && currentToolCallId == toolCall.id
                            )
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 10)
            }
        }
        .frame(maxWidth: 820, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .fill(isCompactSupportingRecord ? Theme.bgSecondary.opacity(0.34) : Theme.bgSecondary.opacity(0.62))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(
                    hasFailure ? Theme.statusError.opacity(0.28) : (isCompactSupportingRecord ? Theme.borderSubtle.opacity(0.7) : (isCompletedCleanly ? Theme.borderDefault : Theme.borderSubtle)),
                    lineWidth: 1
                )
        )
        .padding(.horizontal, 28)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear {
            isExpanded = hasFailure || hasCancellation || isRunning
        }
        .onChange(of: isRunning) { _, running in
            if running {
                hasManualExpansionOverride = false
                isExpanded = true
            } else if isCompletedCleanly && !hasManualExpansionOverride {
                isExpanded = false
            }
        }
        .onChange(of: hasFailure) { _, failed in
            if failed {
                hasManualExpansionOverride = false
                isExpanded = true
            }
        }
        .onChange(of: hasCancellation) { _, cancelled in
            if cancelled {
                hasManualExpansionOverride = false
                isExpanded = true
            }
        }
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        if duration < 1 {
            return String(format: "%.0fms", duration * 1000)
        }
        if duration < 60 {
            return String(format: "%.1fs", duration)
        }
        let minutes = Int(duration / 60)
        let seconds = Int(duration.truncatingRemainder(dividingBy: 60))
        return "\(minutes)m \(seconds)s"
    }
}

private struct ActivityFailureSummaryCard: View {
    let failedCount: Int
    let cancelledCount: Int
    let latestFailedToolName: String?
    let latestFailureReason: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("异常摘要")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)
                    Text(headline)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Theme.textPrimary)
                }

                Spacer()

                ActivitySummaryBadge(
                    icon: "exclamationmark.triangle.fill",
                    text: "\(failedCount) 个失败",
                    tone: Theme.statusError
                )
            }

            HStack(spacing: 8) {
                ActivitySummaryMetric(
                    icon: "wrench.and.screwdriver",
                    label: "失败工具",
                    value: "\(failedCount)",
                    tone: Theme.statusError
                )
                if cancelledCount > 0 {
                    ActivitySummaryMetric(
                        icon: "slash.circle",
                        label: "已取消",
                        value: "\(cancelledCount)",
                        tone: Theme.textTertiary
                    )
                }
            }

            if let latestFailedToolName, !latestFailedToolName.isEmpty {
                ActivityInsightRow(
                    icon: "hammer.circle.fill",
                    title: "最近失败工具",
                    detail: latestFailedToolName,
                    tone: Theme.statusError
                )
            }

            if let latestFailureReason, !latestFailureReason.isEmpty {
                ActivityInsightRow(
                    icon: "text.bubble.fill",
                    title: "失败原因",
                    detail: latestFailureReason,
                    tone: Theme.statusError
                )
            }

            ActivityInsightRow(
                icon: "sparkle.magnifyingglass",
                title: "下一步建议",
                detail: nextActionText,
                tone: Theme.statusWarning
            )
        }
        .padding(10)
        .background(Theme.statusError.opacity(0.08))
        .cornerRadius(Theme.radiusMD)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusMD)
                .stroke(Theme.statusError.opacity(0.18), lineWidth: 1)
        )
    }

    private var headline: String {
        if failedCount == 1 {
            return "有 1 个工具调用失败"
        }
        return "有 \(failedCount) 个工具调用失败"
    }

    private var nextActionText: String {
        if let latestFailureReason {
            if latestFailureReason.localizedCaseInsensitiveContains("权限")
                || latestFailureReason.localizedCaseInsensitiveContains("permission") {
                return "先检查当前工具是否需要额外权限，再决定是否重试。"
            }
            if latestFailureReason.localizedCaseInsensitiveContains("不存在")
                || latestFailureReason.localizedCaseInsensitiveContains("not found") {
                return "先确认目标文件、目录或命令是否存在，再继续执行后续步骤。"
            }
        }
        return "先查看失败工具的参数和输出，再决定是修复输入、切换配置，还是直接重试该步骤。"
    }
}

private struct ActivitySummaryBadge: View {
    let icon: String
    let text: String
    let tone: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundColor(tone)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(tone.opacity(0.10))
        .cornerRadius(Theme.radiusSM)
    }
}

private struct ActivitySummaryMetric: View {
    let icon: String
    let label: String
    let value: String
    let tone: Color

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(tone)
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundColor(Theme.textTertiary)
            Text(value)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Theme.textPrimary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusSM)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusSM)
                .stroke(tone.opacity(0.16), lineWidth: 1)
        )
    }
}

private struct ActivityInsightRow: View {
    let icon: String
    let title: String
    let detail: String
    let tone: Color

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(tone)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Theme.textPrimary)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundColor(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .help(detail)
            }

            Spacer(minLength: 0)
        }
        .padding(8)
        .background(Theme.bgInput)
        .cornerRadius(Theme.radiusSM)
    }
}

private struct ActivityThinkingRow: View {
    let content: String
    let duration: TimeInterval?
    let isStreaming: Bool

    @State private var isExpanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "brain.head.profile")
                        .font(.system(size: 11))
                        .foregroundColor(Theme.thinkingAccent.opacity(0.75))

                    Text("思考")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Theme.textSecondary)

                    if let duration {
                        Text(String(format: "%.0fms", duration * 1000))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(Theme.textTertiary)
                    }

                    if isStreaming {
                        ThinkingDots()
                    }

                    Spacer()
                }
            }
            .buttonStyle(.plain)

            if isExpanded {
                Text(content)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundColor(Theme.textTertiary)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 20)
            }
        }
    }
}

private struct ActivityToolRow: View {
    let toolCall: ToolCall
    let result: ToolResult?
    let isExecuting: Bool

    @State private var isExpanded = false

    private var statusColor: Color {
        if isExecuting { return Theme.statusInfo }
        switch result?.status {
        case .success: return Theme.statusSuccess
        case .error: return Theme.statusError
        case .cancelled: return Theme.textTertiary
        case .none: return Theme.textTertiary
        }
    }

    private var statusIcon: String {
        if isExecuting { return "arrow.triangle.2.circlepath" }
        switch result?.status {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .cancelled: return "slash.circle.fill"
        case .none: return "clock"
        }
    }

    private var statusText: String {
        if isExecuting { return "执行中" }
        switch result?.status {
        case .success: return "执行成功"
        case .error: return "执行失败"
        case .cancelled: return "已取消"
        case .none: return "等待结果"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: {
                withAnimation(.easeInOut(duration: 0.18)) {
                    isExpanded.toggle()
                }
            }) {
                HStack(spacing: 8) {
                    Image(systemName: statusIcon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(statusColor)
                        .frame(width: 14)

                    Text(toolCall.name)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textSecondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(toolCall.name)

                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundColor(statusColor)
                        .lineLimit(1)
                        .help(statusText)

                    Spacer()

                    if !toolCall.arguments.isEmpty || result != nil {
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(Theme.textTertiary)
                    }
                }
            }
            .buttonStyle(.plain)

            if isExpanded || result?.status == .error {
                VStack(alignment: .leading, spacing: 8) {
                    if !toolCall.arguments.isEmpty {
                        ForEach(Array(toolCall.arguments.sorted(by: { $0.key < $1.key })), id: \.key) { key, value in
                            ToolArgumentRow(name: key, value: value.value, keyWidth: 86, fontSize: 10)
                        }
                    }

                    if let result {
                        ToolResultOutputBlock(result: result, fontSize: 10, contentPadding: 8)
                    }
                }
                .padding(.leading, 22)
            }
        }
        .onAppear {
            isExpanded = result?.status == .error || isExecuting
        }
    }
}

// MARK: - Scroll Offset Preference Key

private struct BottomOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ScrollViewportHeightPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Floating Button

struct FloatingButton: View {
    let icon: String
    let label: String
    let isActive: Bool
    let badge: Bool?
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))

                    if badge == true {
                        Circle()
                            .fill(Theme.accentPrimary)
                            .frame(width: 8, height: 8)
                            .offset(x: 4, y: -4)
                    }
                }

                if isHovered {
                    Text(label)
                        .font(.system(size: 12, weight: .medium))
                        .transition(.move(edge: .trailing).combined(with: .opacity))
                }
            }
            .foregroundColor(isActive ? Theme.accentPrimary : Theme.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Theme.bgSecondary)
                    .shadow(color: Theme.shadowStrong.opacity(0.15), radius: 12, x: 0, y: 4)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(isActive ? Theme.accentPrimary.opacity(0.3) : Theme.borderSubtle, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.2)) {
                isHovered = hovering
            }
        }
        .help(isActive ? "点击切换到手动滚动模式" : "点击开启自动跟随最新消息")
    }
}


// MARK: - Processing Animation Overlay

struct ProcessingAnimationOverlay: View {
    let isProcessing: Bool
    let currentToolName: String?
    let progress: Double?

    var body: some View {
        if isProcessing {
            VStack(spacing: 16) {
                HStack(spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Theme.accentPrimary.opacity(0.2))
                            .frame(width: 40, height: 40)

                        Image(systemName: "bolt.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundColor(Theme.accentPrimary)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("正在处理...")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(Theme.textPrimary)

                        if let toolName = currentToolName {
                            Text("执行: \(toolName)")
                                .font(.system(size: 12))
                                .foregroundColor(Theme.textSecondary)
                        }
                    }

                    Spacer()

                    ProgressView()
                        .controlSize(.small)
                        .tint(Theme.accentPrimary)
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusLG)
                        .fill(Theme.bgSecondary)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.radiusLG)
                        .stroke(Theme.accentPrimary.opacity(0.3), lineWidth: 1)
                )
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 8)
            .transition(.opacity)
        }
    }
}

// MARK: - Preview

struct EnhancedMessageBubble_Previews: PreviewProvider {
    static var previews: some View {
        VStack(spacing: 20) {
            EnhancedMessageBubble(
                message: Message(
                    role: .assistant,
                    content: "我来帮你创建一个新文件。",
                    toolCalls: [
                        ToolCall(id: "1", name: "write_file", arguments: [
                            "path": AnyCodable("/path/to/file.swift"),
                            "content": AnyCodable("print(\"Hello\")")
                        ])
                    ],
                    toolResults: [
                        .success(toolCallId: "1", output: "文件写入成功")
                    ]
                ),
                isToolExecuting: false,
                currentToolCallId: nil,
                toolResultsById: [:]
            )

            EnhancedMessageBubble(
                message: Message(
                    role: .assistant,
                    content: "正在编辑文件...",
                    toolCalls: [
                        ToolCall(id: "2", name: "edit_file", arguments: [
                            "path": AnyCodable("/path/to/file.swift"),
                            "old_text": AnyCodable("old"),
                            "new_text": AnyCodable("new")
                        ])
                    ]
                ),
                isToolExecuting: true,
                currentToolCallId: "2",
                toolResultsById: [:]
            )
        }
        .padding()
        .background(Theme.bgPrimary)
        .previewLayout(.sizeThatFits)
    }
}
