import Foundation

// MARK: - Execution Pipeline Models

/// 执行流水线的整体状态
struct ExecutionPipeline: Identifiable {
    let id: UUID
    var stages: [PipelineStage]
    var startTime: Date
    var endTime: Date?
    var mode: ExecutionMode

    enum ExecutionMode {
        case singleAgent
        case multiAgent
    }

    init(id: UUID = UUID(), mode: ExecutionMode) {
        self.id = id
        self.mode = mode
        self.startTime = Date()
        self.stages = []
    }

    var currentStage: PipelineStage? {
        stages.first { $0.status == .running }
    }

    var overallStatus: PipelineStageStatus {
        if stages.isEmpty {
            return .pending
        }
        if stages.contains(where: { $0.status == .failed }) {
            return .failed
        }
        if stages.contains(where: { $0.status == .cancelled }) {
            return .cancelled
        }
        if stages.contains(where: { $0.status == .running }) {
            return .running
        }
        if stages.allSatisfy({ $0.status == .completed || $0.status == .skipped }) {
            return .completed
        }
        return .pending
    }

    var duration: TimeInterval {
        (endTime ?? Date()).timeIntervalSince(startTime)
    }
}

/// 流水线的单个阶段
struct PipelineStage: Identifiable {
    let id: UUID
    var type: StageType
    var status: PipelineStageStatus
    var startTime: Date?
    var endTime: Date?
    var details: StageDetails
    var substeps: [PipelineSubstep]

    enum StageType {
        case router              // Router 决策
        case taskAnalysis        // 任务分析（Single Agent）
        case dagPlanning         // DAG 规划（Multi-Agent）
        case execution           // 执行阶段
        case errorRecovery       // 错误自愈（Critic）
        case verification        // 验证阶段
        case synthesis           // 结果汇总（Multi-Agent）

        var icon: String {
            switch self {
            case .router: return "arrow.triangle.branch"
            case .taskAnalysis: return "brain.head.profile"
            case .dagPlanning: return "network"
            case .execution: return "gearshape.2.fill"
            case .errorRecovery: return "stethoscope"
            case .verification: return "checkmark.shield.fill"
            case .synthesis: return "arrow.triangle.merge"
            }
        }

        var title: String {
            switch self {
            case .router: return "路由决策"
            case .taskAnalysis: return "任务分析"
            case .dagPlanning: return "DAG 规划"
            case .execution: return "执行阶段"
            case .errorRecovery: return "错误自愈"
            case .verification: return "验证阶段"
            case .synthesis: return "结果汇总"
            }
        }
    }

    init(type: StageType, details: StageDetails = .empty) {
        self.id = UUID()
        self.type = type
        self.status = .pending
        self.details = details
        self.substeps = []
    }

    var duration: TimeInterval? {
        guard let start = startTime else { return nil }
        return (endTime ?? Date()).timeIntervalSince(start)
    }

    var hasExpandableContent: Bool {
        !substeps.isEmpty || details.hasVisibleDetails
    }

    mutating func start() {
        status = .running
        startTime = Date()
    }

    mutating func complete() {
        status = .completed
        endTime = Date()
    }

    mutating func fail(error: String) {
        status = .failed
        endTime = Date()
        details = details.withError(error)
    }

    mutating func skip(reason: String) {
        status = .skipped
        endTime = Date()
        details = details.withSkipReason(reason)
    }

    mutating func cancel(reason: String) {
        status = .cancelled
        endTime = Date()
        details = details.withCancelReason(reason)
    }
}

/// 阶段状态
enum PipelineStageStatus {
    case pending
    case running
    case completed
    case cancelled
    case failed
    case skipped
}

/// 阶段详细信息（联合类型）
enum StageDetails {
    case empty
    case router(decision: String, target: String?, confidence: Double?)
    case taskAnalysis(complexity: String, stepCount: Int, estimatedTime: String?)
    case dagPlanning(subTaskCount: Int, workerCount: Int, maxDepth: Int)
    case execution(
        toolCalls: [String],
        completedCount: Int,
        totalCount: Int,
        failedCount: Int = 0,
        cancelledCount: Int = 0
    )
    case errorRecovery(retryCount: Int, analysisResult: String?)
    case verification(passedChecks: Int, totalChecks: Int, summary: String? = nil)
    case synthesis(workerResults: Int)
    case error(message: String)
    case skipped(reason: String)
    case cancelled(reason: String)

    func withError(_ error: String) -> StageDetails {
        .error(message: error)
    }

    func withSkipReason(_ reason: String) -> StageDetails {
        .skipped(reason: reason)
    }

    func withCancelReason(_ reason: String) -> StageDetails {
        .cancelled(reason: reason)
    }

    var hasVisibleDetails: Bool {
        switch self {
        case .empty, .synthesis:
            return false
        case .verification(_, _, let summary):
            return summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .router(_, let target, _):
            return target?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .taskAnalysis(_, _, let estimatedTime):
            return estimatedTime?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .dagPlanning:
            return true
        case .execution(let toolCalls, _, _, _, _):
            return !toolCalls.isEmpty
        case .errorRecovery(_, let analysisResult):
            return analysisResult?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        case .error(let message), .skipped(let message), .cancelled(let message):
            return !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}

/// 子步骤（用于展示阶段内的细粒度进度）
struct PipelineSubstep: Identifiable {
    let id: UUID
    var title: String
    var status: PipelineStageStatus
    var duration: TimeInterval?
    var metadata: [String: String]

    init(
        id: UUID = UUID(),
        title: String,
        status: PipelineStageStatus = .pending,
        duration: TimeInterval? = nil,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.status = status
        self.duration = duration
        self.metadata = metadata
    }
}

// MARK: - Pipeline Builder

/// 流水线构建器（用于 AgentEngine 和 MultiAgentEngine）
@MainActor
class PipelineBuilder {
    private var pipeline: ExecutionPipeline

    init(mode: ExecutionPipeline.ExecutionMode) {
        self.pipeline = ExecutionPipeline(mode: mode)
    }

    func setMode(_ mode: ExecutionPipeline.ExecutionMode) {
        pipeline.mode = mode
    }

    func addStage(_ type: PipelineStage.StageType, details: StageDetails = .empty) -> UUID {
        let stage = PipelineStage(type: type, details: details)
        pipeline.stages.append(stage)
        return stage.id
    }

    func startStage(_ stageId: UUID) {
        if let index = pipeline.stages.firstIndex(where: { $0.id == stageId }) {
            pipeline.stages[index].start()
        }
    }

    func completeStage(_ stageId: UUID) {
        if let index = pipeline.stages.firstIndex(where: { $0.id == stageId }) {
            pipeline.stages[index].complete()
        }
    }

    func failStage(_ stageId: UUID, error: String) {
        if let index = pipeline.stages.firstIndex(where: { $0.id == stageId }) {
            pipeline.stages[index].fail(error: error)
        }
    }

    func skipStage(_ stageId: UUID, reason: String) {
        if let index = pipeline.stages.firstIndex(where: { $0.id == stageId }) {
            pipeline.stages[index].skip(reason: reason)
        }
    }

    func cancelStage(_ stageId: UUID, reason: String) {
        if let index = pipeline.stages.firstIndex(where: { $0.id == stageId }) {
            pipeline.stages[index].cancel(reason: reason)
        }
    }

    func updateStageDetails(_ stageId: UUID, details: StageDetails) {
        if let index = pipeline.stages.firstIndex(where: { $0.id == stageId }) {
            pipeline.stages[index].details = details
        }
    }

    func stageStatus(_ stageId: UUID) -> PipelineStageStatus? {
        pipeline.stages.first(where: { $0.id == stageId })?.status
    }

    func addSubstep(_ stageId: UUID, substep: PipelineSubstep) {
        if let index = pipeline.stages.firstIndex(where: { $0.id == stageId }) {
            pipeline.stages[index].substeps.append(substep)
        }
    }

    func updateSubstep(_ stageId: UUID, substepId: UUID, status: PipelineStageStatus, duration: TimeInterval? = nil) {
        if let stageIndex = pipeline.stages.firstIndex(where: { $0.id == stageId }),
           let substepIndex = pipeline.stages[stageIndex].substeps.firstIndex(where: { $0.id == substepId }) {
            pipeline.stages[stageIndex].substeps[substepIndex].status = status
            if let duration {
                pipeline.stages[stageIndex].substeps[substepIndex].duration = duration
            }
        }
    }

    func finish() {
        pipeline.endTime = Date()
    }

    func build() -> ExecutionPipeline {
        pipeline
    }
}
