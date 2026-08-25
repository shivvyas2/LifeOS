import SwiftUI

/// The red interruption card: something in the data sits outside the reader's
/// own range. Facts only — the metric and the direction. Never advice.
public struct AlertBanner: View {
    private let messages: [String]
    @Environment(\.colorScheme) private var scheme

    public init(messages: [String]) {
        self.messages = messages
    }

    public var body: some View {
        // No anomalies is silence, not an empty red frame.
        if !messages.isEmpty {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "waveform.path.ecg")
                    .font(.system(size: 18, weight: .semibold))
                    .padding(10)
                    .background(Circle().fill(LifeOSTokens.alertText.resolve(scheme).opacity(0.12)))

                VStack(alignment: .leading, spacing: 4) {
                    ForEach(messages, id: \.self) { message in
                        Text(message)
                            .font(.system(size: 14, weight: .semibold))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(.top, 6)

                Spacer(minLength: 0)
            }
            .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LifeOSTokens.alertBackground.resolve(scheme))
            )
            .accessibilityElement(children: .combine)
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        AlertBanner(messages: ["Resting HR is well above your 2-week baseline",
                               "Skin temp is well above your 2-week baseline"])
        AlertBanner(messages: [])
    }
    .padding()
    .background(LifeOSTokens.canvas.resolve(.light))
}
