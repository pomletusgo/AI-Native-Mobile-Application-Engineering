import SwiftUI

/// 名片列表行：展示缩略信息（缩略图、姓名、公司/职位、首选电话、标签）。
struct CardRowView: View {

    let card: BusinessCard

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            thumbnail

            VStack(alignment: .leading, spacing: 4) {
                Text(card.name)
                    .font(.headline)

                if let subtitle = card.subtitle {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                if let phone = card.primaryPhone {
                    Label(phone, systemImage: "phone")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if !card.tags.isEmpty {
                    TagChipsView(tags: card.tags)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    private var thumbnail: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(Color.secondary.opacity(0.15))
            .frame(width: 48, height: 48)
            .overlay {
                Image(systemName: "person.text.rectangle")
                    .foregroundStyle(.secondary)
            }
    }
}

/// 标签小标签组（名片行、详情页共用）。
struct TagChipsView: View {

    let tags: [String]

    var body: some View {
        HStack(spacing: 6) {
            ForEach(tags, id: \.self) { tag in
                Text(tag)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(Color.accentColor.opacity(0.15))
                    )
                    .foregroundStyle(Color.accentColor)
            }
        }
    }
}

#Preview {
    List {
        CardRowView(card: BusinessCardMockData.sampleCards[0])
        CardRowView(card: BusinessCardMockData.sampleCards[1])
    }
}
