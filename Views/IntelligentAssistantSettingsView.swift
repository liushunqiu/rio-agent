import SwiftUI

/// Settings view for intelligent assistant features
struct IntelligentAssistantSettingsView: View {
    
    @ObservedObject private var configManager = IntelligentAssistantConfigManager.shared
    @State private var showingResetConfirmation = false
    @State private var selectedPreset: PresetType = .balanced
    
    enum PresetType: String, CaseIterable {
        case conservative = "保守"
        case balanced = "均衡"
        case aggressive = "激进"
        
        var description: String {
            switch self {
            case .conservative:
                return "最小化学习和分析"
            case .balanced:
                return "适度学习和分析"
            case .aggressive:
                return "最大化学习和分析"
            }
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header
            HStack {
                Image(systemName: "brain.head.profile")
                    .font(.title)
                    .foregroundColor(.accentColor)
                Text("智能助手设置")
                    .font(.title2)
                    .fontWeight(.bold)
            }
            
            // Preset Selection
            GroupBox(label: Label("预设", systemImage: "slider.horizontal.3")) {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("预设", selection: $selectedPreset) {
                        ForEach(PresetType.allCases, id: \.self) { preset in
                            VStack(alignment: .leading) {
                                Text(preset.rawValue)
                                Text(preset.description)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            .tag(preset)
                        }
                    }
                    .pickerStyle(.menu)
                    
                    Button("应用预设") {
                        applyPreset(selectedPreset)
                    }
                    .buttonStyle(.borderedProminent)
                }
                .padding(.vertical, 8)
            }
            
            // Learning Settings
            GroupBox(label: Label("学习", systemImage: "brain")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用用户行为学习", isOn: $configManager.config.enableLearning)
                    Toggle("启用工具推荐", isOn: $configManager.config.enableToolRecommendations)
                    Toggle("启用任务规划", isOn: $configManager.config.enableTaskPlanning)
                    Toggle("启用长期记忆", isOn: $configManager.config.enableLongTermMemory)
                }
                .padding(.vertical, 8)
            }
            
            // Analysis Settings
            GroupBox(label: Label("分析", systemImage: "chart.bar")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("启用代码质量分析", isOn: $configManager.config.enableCodeAnalysis)
                    Toggle("启用上下文感知", isOn: $configManager.config.enableContextAwareness)
                    Toggle("启用实时代码分析", isOn: $configManager.config.enableRealTimeAnalysis)
                    
                    Divider()
                    
                    HStack {
                        Text("最大行长度：")
                        Spacer()
                        TextField("", value: $configManager.config.maxLineLength, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("最大函数长度：")
                        Spacer()
                        TextField("", value: $configManager.config.maxFunctionLength, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("最大嵌套深度：")
                        Spacer()
                        TextField("", value: $configManager.config.maxNestingDepth, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Display Settings
            GroupBox(label: Label("显示", systemImage: "eye")) {
                VStack(alignment: .leading, spacing: 12) {
                    Toggle("显示任务计划", isOn: $configManager.config.showTaskPlan)
                    Toggle("显示代码分析结果", isOn: $configManager.config.showCodeAnalysis)
                    Toggle("显示工具推荐", isOn: $configManager.config.showToolRecommendations)
                    Toggle("显示学习进度", isOn: $configManager.config.showLearningProgress)
                }
                .padding(.vertical, 8)
            }
            
            // Memory Settings
            GroupBox(label: Label("记忆", systemImage: "memorychip")) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("最大近期文件数：")
                        Spacer()
                        TextField("", value: $configManager.config.maxRecentFiles, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("最大近期命令数：")
                        Spacer()
                        TextField("", value: $configManager.config.maxRecentCommands, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                    
                    HStack {
                        Text("最大错误模式数：")
                        Spacer()
                        TextField("", value: $configManager.config.maxErrorPatterns, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                    }
                }
                .padding(.vertical, 8)
            }
            
            // Reset Button
            HStack {
                Spacer()
                Button("重置为默认") {
                    showingResetConfirmation = true
                }
                .foregroundColor(.red)
            }
        }
        .padding()
        .frame(width: 500)
        .onChange(of: configManager.config) { oldValue, newValue in
            configManager.save()
        }
        .alert("重置设置", isPresented: $showingResetConfirmation) {
            Button("取消", role: .cancel) { }
            Button("重置", role: .destructive) {
                configManager.resetToDefaults()
            }
        } message: {
            Text("您确定要将所有智能助手设置重置为默认值吗？")
        }
    }
    
    private func applyPreset(_ preset: PresetType) {
        switch preset {
        case .conservative:
            configManager.applyPreset(.conservative)
        case .balanced:
            configManager.applyPreset(.balanced)
        case .aggressive:
            configManager.applyPreset(.aggressive)
        }
    }
}

// MARK: - Preview

struct IntelligentAssistantSettingsView_Previews: PreviewProvider {
    static var previews: some View {
        IntelligentAssistantSettingsView()
    }
}
