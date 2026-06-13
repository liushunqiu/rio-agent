import SwiftUI
import AppKit

// MARK: - Content Segment

enum ContentSegment: Identifiable {
    case text(id: String, content: String)
    case codeBlock(id: String, language: String, code: String)

    var id: String {
        switch self {
        case .text(let id, _), .codeBlock(let id, _, _):
            return id
        }
    }
}

// MARK: - Markdown Parser

struct MarkdownParser {
    static func parse(_ text: String) -> [ContentSegment] {
        var segments: [ContentSegment] = []
        var remaining = text[..<text.endIndex]
        var segmentIndex = 0

        while !remaining.isEmpty {
            let idx = segmentIndex
            segmentIndex += 1

            if let codeBlockStart = remaining.range(of: "```") {
                let beforeCode = remaining[..<codeBlockStart.lowerBound]
                if !beforeCode.isEmpty {
                    segments.append(.text(id: "t\(idx)", content: String(beforeCode)))
                }

                let afterBackticks = remaining[codeBlockStart.upperBound...]
                let lineEnd = afterBackticks.firstIndex(of: "\n") ?? afterBackticks.endIndex
                let language = String(afterBackticks[..<lineEnd]).trimmingCharacters(in: .whitespaces)

                let codeStart = lineEnd < afterBackticks.endIndex ? afterBackticks.index(after: lineEnd) : afterBackticks.endIndex
                let afterCodeStart = afterBackticks[codeStart...]

                if let codeBlockEnd = afterCodeStart.range(of: "```") {
                    let code = String(afterCodeStart[..<codeBlockEnd.lowerBound])
                    let trimmedCode = code.hasSuffix("\n") ? String(code.dropLast()) : code
                    segments.append(.codeBlock(id: "c\(idx)", language: language, code: trimmedCode))
                    remaining = afterCodeStart[codeBlockEnd.upperBound...]
                } else {
                    let code = String(afterCodeStart)
                    let trimmedCode = code.hasSuffix("\n") ? String(code.dropLast()) : code
                    segments.append(.codeBlock(id: "c\(idx)", language: language, code: trimmedCode))
                    remaining = remaining[remaining.endIndex...]
                }
            } else {
                segments.append(.text(id: "t\(idx)", content: String(remaining)))
                remaining = remaining[remaining.endIndex...]
            }
        }

        return segments
    }
}

// MARK: - Markdown Renderer View

struct MarkdownRenderer: View {
    let text: String
    @State private var segments: [ContentSegment] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(segments) { segment in
                switch segment {
                case .text(_, let content):
                    InlineMarkdownView(text: content)
                case .codeBlock(_, let language, let code):
                    CodeBlockView(language: language, code: code)
                }
            }
        }
        .task(id: text) {
            segments = MarkdownParser.parse(text)
        }
    }
}

// MARK: - Inline Markdown View

struct InlineMarkdownView: View {
    let text: String
    @State private var attributedString: AttributedString?

    var body: some View {
        Text(attributedString ?? plainText)
            .font(.system(size: 14))
            .foregroundColor(Theme.textPrimary)
            .textSelection(.enabled)
            .lineSpacing(6)
            .fixedSize(horizontal: false, vertical: true)
            .task(id: text) {
                let parsed = MarkdownParser.parseMarkdownFull(text)
                attributedString = parsed
            }
    }

    private var plainText: AttributedString {
        AttributedString(text)
    }
}

// MARK: - Markdown Parser Extension

extension MarkdownParser {
    static func parseMarkdownFull(_ text: String) -> AttributedString {
        do {
            var attrStr = try AttributedString(
                markdown: text,
                options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
            )
            for run in attrStr.runs {
                if run.inlinePresentationIntent == .code {
                    attrStr[run.range].foregroundColor = Theme.accentPrimary
                    attrStr[run.range].font = .system(size: 13, design: .monospaced)
                }
            }
            for run in attrStr.runs {
                if run.link != nil {
                    attrStr[run.range].foregroundColor = Theme.accentSecondary
                }
            }
            return attrStr
        } catch {
            return AttributedString(text)
        }
    }
}

// MARK: - Code Block View

struct CodeBlockView: View {
    let language: String
    let code: String
    @State private var isCopied = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                if !language.isEmpty {
                    Text(language)
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(Theme.textTertiary)
                        .textCase(.uppercase)
                }

                Spacer()

                Button(action: copyCode) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                            .font(.system(size: 11))
                        Text(isCopied ? "已复制" : "复制")
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(isCopied ? Theme.statusSuccess : Theme.textTertiary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 4)
                            .fill(isHovered ? Theme.bgElevated : Color.clear)
                    )
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    isHovered = hovering
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 10)
            .padding(.bottom, 8)
            .background(Theme.bgSecondary.opacity(0.8))

            Divider()
                .overlay(Theme.borderSubtle)

            ScrollView(.horizontal, showsIndicators: false) {
                Text(code)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundColor(Theme.textPrimary.opacity(0.9))
                    .textSelection(.enabled)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .lineSpacing(3)
            }
        }
        .background(Theme.codeBackground)
        .cornerRadius(Theme.radiusLG)
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusLG)
                .stroke(Theme.borderSubtle, lineWidth: 1)
        )
    }

    private func copyCode() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(code, forType: .string)
        withAnimation(.easeInOut(duration: 0.15)) {
            isCopied = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation(.easeInOut(duration: 0.15)) {
                isCopied = false
            }
        }
    }
}
