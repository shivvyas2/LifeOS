import SwiftUI
import DesignSystem
import Persistence

/// One catalog video. The thumbnail is fetched from YouTube's own host; when
/// it cannot be, the placeholder is a deliberate tile rather than a gap, so a
/// row offline still reads as a workout.
struct WorkoutVideoRow: View {
    let video: CatalogVideo
    var action: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    private let thumbnailWidth: CGFloat = 128

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 14) {
                thumbnail
                VStack(alignment: .leading, spacing: 6) {
                    Text(video.title)
                        .font(LifeOSType.rowTitle)
                        .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                    Text("\(video.channel) · \(video.durationMinutes) min")
                        .font(LifeOSType.caption.weight(.medium))
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                        .lineLimit(1)
                    // Dots and chips keep their own lines: three chips and a
                    // scale do not both fit beside a thumbnail, and a chip
                    // truncated to "Dum…" is worse than a taller row.
                    intensityDots
                    chips
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .fill(LifeOSTokens.cardSurface.resolve(scheme))
            )
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(video.title), \(video.channel), \(video.durationMinutes) minutes, \(video.split), intensity \(video.intensity) of 3")
        .accessibilityHint("Opens the workout")
    }

    private var thumbnail: some View {
        AsyncImage(url: video.thumbnailURL) { image in
            image.resizable().aspectRatio(contentMode: .fill)
        } placeholder: {
            ZStack {
                (scheme == .dark ? ModuleHue.activity.pastelDark : ModuleHue.activity.pastel)
                Image(systemName: "play.rectangle.fill")
                    .font(.system(size: 26, weight: .regular))
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme).opacity(0.45))
            }
        }
        .frame(width: thumbnailWidth, height: thumbnailWidth * 9 / 16)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .accessibilityHidden(true)
    }

    /// Three dots, filled to the video's intensity. A scale with a stated top
    /// says more than a number on its own.
    private var intensityDots: some View {
        HStack(spacing: 4) {
            ForEach(1...3, id: \.self) { step in
                Circle()
                    .fill(step <= video.intensity
                          ? LifeOSTokens.accent
                          : LifeOSTokens.dotOutline.resolve(scheme))
                    .frame(width: 6, height: 6)
            }
        }
        .accessibilityHidden(true)
    }

    private var chips: some View {
        HStack(spacing: 6) {
            chip(video.split)
            ForEach(video.equipment.prefix(2), id: \.self) { chip($0) }
        }
        .lineLimit(1)
    }

    private func chip(_ text: String) -> some View {
        Text(text.capitalized)
            .font(LifeOSType.eyebrow.weight(.medium))
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // The canvas tone, so a chip on a white card is a chip and not a
            // word floating in space.
            .background(LifeOSTokens.canvas.resolve(scheme), in: Capsule())
    }
}
