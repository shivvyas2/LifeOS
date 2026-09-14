import SwiftUI
import Insights
import DesignSystem

/// Chooses native cells and tables from the reply's content, while keeping a
/// short answer short. No fixed dashboard or placeholder values.
struct CoachResponseView: View {
    let text: String
    var onAura = false
    var style: CoachScreenStyle = .text
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if onAura {
                Label("LIFO", systemImage: "sparkle")
                    .font(.caption.weight(.semibold)).tracking(1)
                    .foregroundStyle(onAura ? style.cardAccent : LifeOSTokens.accent)
            }
            ForEach(Array(CoachResponse(text).blocks.enumerated()), id: \.offset) { _, block in
                switch block {
                case .paragraph(let text):
                    richText(text)
                        .font(.subheadline)
                        .lineSpacing(4)
                case .heading(let text):
                    richText(text)
                        .font(.headline)
                        .padding(.top, 6)
                        .accessibilityAddTraits(.isHeader)
                case .list(let items):
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)")
                                    .font(.caption.bold())
                                    .foregroundStyle(onAura ? style.cardAccent : LifeOSTokens.accent)
                                    .frame(width: 22, alignment: .leading)
                                richText(item).font(.subheadline)
                            }
                            .padding(14)
                            if index < items.count - 1 { Divider().padding(.horizontal, 14) }
                        }
                    }
                    .background(surface, in: RoundedRectangle(cornerRadius: 16))
                case .table(let headers, let rows):
                    if headers.count == 2 && rows.count <= 6 {
                        metricCells(headers: headers, rows: rows)
                    } else {
                        comparisonTable(headers: headers, rows: rows)
                    }
                }
            }
        }
        .foregroundStyle(LifeOSTokens.primaryText.resolve(onAura ? .light : scheme))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(onAura ? 20 : 0)
        .background {
            if onAura {
                RoundedRectangle(cornerRadius: 20)
                    .fill(style.card)
                    .shadow(color: .black.opacity(0.16), radius: 18, y: 8)
            }
        }
        .environment(\.colorScheme, onAura ? .light : scheme)
    }

    private var surface: Color { onAura ? style.cell : LifeOSTokens.cardSurface.resolve(scheme) }

    private func richText(_ value: String) -> Text {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
    }

    private func metricCells(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(headers.joined(separator: " · "))
                .font(.caption).foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 10) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 8) {
                        richText(row[0]).font(.caption).foregroundStyle(.secondary)
                        richText(row[1]).font(.title3.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(14)
                    .background(surface, in: RoundedRectangle(cornerRadius: 16))
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    private func comparisonTable(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                GridRow {
                    ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                        richText(header).font(.caption.bold())
                            .frame(minWidth: 92, maxWidth: 160, alignment: .leading)
                            .padding(12)
                    }
                }
                .background(onAura ? style.cell.opacity(0.8) : LifeOSTokens.accent.opacity(0.10))
                ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                    GridRow {
                        ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                            richText(value).font(.subheadline)
                                .frame(minWidth: 92, maxWidth: 160, alignment: .leading)
                                .padding(12)
                                .accessibilityLabel("\(headers[column]): \(value)")
                        }
                    }
                    .background(index.isMultiple(of: 2) ? surface : surface.opacity(0.6))
                }
            }
        }
        .background(surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .accessibilityHint("Scroll horizontally for additional columns")
    }
}

#Preview("Coach · metrics and actions") {
    ScrollView {
        CoachResponseView(text: """
        Your sleep is more consistent this week. Keep the same wake-up time.

        ## This week
        | Metric | Value |
        | --- | --- |
        | Average sleep | 7 h 24 min |
        | Recovery | 72% |

        ## Next step
        - Start winding down 30 minutes before your usual bedtime.
        """)
        .padding(24)
    }
    .background(LifeOSTokens.canvas.light)
}
