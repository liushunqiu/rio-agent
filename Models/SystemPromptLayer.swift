import Foundation

enum SystemPromptLayer: String, CaseIterable {
    case responseContract
    case evidenceRequirements
    case toolDiscipline
    case checkableStateRules
    case availableTools
    case routingOutputContract
}
