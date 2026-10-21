import SwiftUI

/// Documentation page: numbered editorial topics.
struct HelpView: View {
    @Binding var expandedID: String?

    @Environment(\.palette) private var palette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                PageHeading(
                    title: "Документация",
                    subtitle: "Трей, потоки, жанры и горячие клавиши"
                )

                ForEach(HelpGuide.topics) { topic in
                    topicRow(topic)
                }
            }
            .padding(Space.xxl)
        }
    }

    private func topicRow(_ topic: HelpTopic) -> some View {
        let isExpanded = expandedID == topic.id

        return VStack(alignment: .leading, spacing: 0) {
            Hairline()

            Button {
                withAnimation(reduceMotion ? nil : Motion.content) {
                    expandedID = isExpanded ? nil : topic.id
                }
            } label: {
                HStack(spacing: Space.m) {
                    Text(topic.title)
                        .font(Typeface.section)
                        .foregroundStyle(palette.textPrimary)
                    Spacer(minLength: Space.s)
                    Image(systemName: isExpanded ? "minus" : "plus")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.vertical, Space.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])

            if isExpanded {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Array(topic.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(paragraph)
                            .font(Typeface.callout)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.bottom, Space.m)
            }
        }
    }
}
