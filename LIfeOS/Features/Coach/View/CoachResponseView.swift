import SwiftUI
import Insights
import DesignSystem

/// A reply drawn from its content: a sentence stays a sentence, two metrics
/// become cells, a comparison becomes a hairline table, steps are numbered.
/// On paper, in ink; nothing about it is a card unless it holds a figure.
struct CoachResponseView: View {
    let text: String
    /// How many blocks may show, from the top; nil shows them all. The voice
    /// raises it as each passage starts, so a section arrives with the
    /// sentence about it.
    var revealed: Int? = nil
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dynamicTypeSize) private var typeSize

    private var ink: Color { LifeOSTokens.primaryText.resolve(scheme) }
    private var quiet: Color { Editorial.quietInk(scheme) }

    var body: some View {
        let blocks = CoachResponse(text).blocks
        let shown = revealed.map { Array(blocks.prefix($0)) } ?? blocks
        return VStack(alignment: .leading, spacing: Space.x2) {
            ForEach(Array(shown.enumerated()), id: \.offset) { index, block in
                blockView(block)
                    .modifier(BlockReveal(index: index))
            }
        }
        .foregroundStyle(ink)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: CoachResponse.Block) -> some View {
        switch block {
        case .paragraph(let text):
            richText(text)
                .font(LifeOSType.secondary)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        case .heading(let text):
            richText(text)
                .font(LifeOSType.sectionTitle)
                .padding(.top, Space.half)
                .accessibilityAddTraits(.isHeader)
        case .list(let items):
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .firstTextBaseline, spacing: Space.x2) {
                        IndexPill(index + 1)
                        richText(item).font(LifeOSType.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.vertical, 12)
                    if index < items.count - 1 { Hairline() }
                }
            }
        case .table(let headers, let rows):
            if headers.count == 2 && rows.count <= 6 {
                metricCells(headers: headers, rows: rows)
            } else {
                comparisonTable(headers: headers, rows: rows)
            }
        }
    }

    private func richText(_ value: String) -> Text {
        Text((try? AttributedString(markdown: value, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(value))
    }

    /// Two columns, six rows or fewer: each row is a figure with its label
    /// above, on a hairline card, two to a row.
    private func metricCells(headers: [String], rows: [[String]]) -> some View {
        VStack(alignment: .leading, spacing: Space.x1) {
            Text(headers.joined(separator: " · ")).editorialEyebrow()
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .leading),
                                     count: typeSize.isAccessibilitySize ? 1 : 2), spacing: Space.x1) {
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: Space.half) {
                        richText(row[0]).editorialEyebrow()
                        richText(row[1])
                            .font(Editorial.figure(28)).tracking(Editorial.figureTracking(28))
                            .monospacedDigit().lineLimit(1).minimumScaleFactor(0.6)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .editorialCard(padding: Space.x2)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }

    /// Wider or longer: a ruled table. Headers as eyebrows, rows separated
    /// by hairlines, scrolling sideways when the columns do not fit.
    private func comparisonTable(headers: [String], rows: [[String]]) -> some View {
        ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                Grid(alignment: .leading, horizontalSpacing: 0, verticalSpacing: 0) {
                    GridRow {
                        ForEach(Array(headers.enumerated()), id: \.offset) { _, header in
                            richText(header).editorialEyebrow()
                                .frame(minWidth: 92, maxWidth: 160, alignment: .leading)
                                .padding(.horizontal, 12).padding(.vertical, 10)
                        }
                    }
                    Divider().gridCellUnsizedAxes(.horizontal).overlay(Editorial.rule(scheme))
                    ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                        GridRow {
                            ForEach(Array(row.enumerated()), id: \.offset) { column, value in
                                richText(value).font(LifeOSType.secondary)
                                    .frame(minWidth: 92, maxWidth: 160, alignment: .leading)
                                    .padding(.horizontal, 12).padding(.vertical, 12)
                                    .accessibilityLabel("\(headers[column]): \(value)")
                            }
                        }
                        if index < rows.count - 1 {
                            Divider().gridCellUnsizedAxes(.horizontal).overlay(Editorial.rule(scheme))
                        }
                    }
                }
            }
        }
        .accessibilityHint("Scroll horizontally for additional columns")
    }
}

/// Each block comes up a beat after the one above it.
///
/// The answer is held until the voice starts, then arrives while it is
/// speaking; a screen that fills in one frame under a voice still on its
/// first sentence reads as two things happening, and a screen that fills in
/// step with it reads as one. State lives on the block, so a block already
/// on screen is never re-animated when the text under it streams on.
private struct BlockReveal: ViewModifier {
    let index: Int
    @State private var shown = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : 10)
            .onAppear {
                let delay = Double(min(index, 5)) * 0.14
                withAnimation(.easeOut(duration: 0.4).delay(delay)) { shown = true }
            }
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
