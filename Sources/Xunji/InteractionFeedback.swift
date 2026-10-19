import SwiftUI

// 悬浮只更新当前行的修饰层，避免将鼠标移动传播为整个结果列表的重建。
struct ResultRowHover: ViewModifier {
    let selected: Bool
    @State private var hovered = false
    func body(content: Content) -> some View {
        content
            .background(hovered && !selected ? Color.primary.opacity(0.045) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .onHover { hovered = $0 }
    }
}

// 仅强调文件名里的匹配词；原生列表继续管理键盘选中与可访问性。
func filenameWithMatches(_ name: String, query: String, selected: Bool) -> AttributedString {
    var result = AttributedString(name)
    for token in query.split(whereSeparator: { $0.isWhitespace }).prefix(12) {
        var remaining = name.startIndex..<name.endIndex
        while let match = name.range(of: String(token), options: [.caseInsensitive, .diacriticInsensitive], range: remaining) {
            if let start = AttributedString.Index(match.lowerBound, within: result),
               let end = AttributedString.Index(match.upperBound, within: result) {
                result[start..<end].font = .system(size: 13, weight: .bold)
                if !selected { result[start..<end].foregroundColor = .accentColor }
            }
            remaining = match.upperBound..<name.endIndex
        }
    }
    return result
}

struct InteractionButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Color.primary.opacity(enabled && (hovered || configuration.isPressed) ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.96 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.12), value: configuration.isPressed)
            .onHover { hovered = $0 }
    }
}

// 筛选标签的整个矩形都是点击目标，包括文字两侧与上下留白。
// 高频切换直接响应，不缩放按钮或改变字体宽度，避免目标随手势移动。
struct FilterChipStyle: ButtonStyle {
    let selected: Bool
    @Environment(\.isEnabled) private var enabled
    @State private var hovered = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? Color.accentColor : Color.primary.opacity(0.75))
            .background(
                selected ? Color.accentColor.opacity(configuration.isPressed ? 0.24 : 0.15)
                    : Color.primary.opacity(configuration.isPressed ? 0.11 : hovered && enabled ? 0.075 : 0.025),
                in: RoundedRectangle(cornerRadius: 7)
            )
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(selected ? Color.accentColor.opacity(0.3) : .clear))
            .contentShape(Rectangle())
            .onHover { hovered = $0 }
    }
}
