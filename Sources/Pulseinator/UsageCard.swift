import SwiftUI

struct UsageCard: View {
    let title: String
    let value: String
    let subtitle: String
    var accentColor: Color = .blue

    var body: some View {
        RoundedRectangle(cornerRadius: 10)
            .fill(Color(NSColor.controlBackgroundColor))
            .overlay(
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Spacer()

                    Text(value)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundStyle(accentColor)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer()

                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .padding(10)
            )
            .frame(height: 80)
    }
}
