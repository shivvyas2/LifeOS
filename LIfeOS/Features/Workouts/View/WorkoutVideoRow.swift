import SwiftUI
import DesignSystem
import Persistence

/// One catalog video. The thumbnail is fetched from YouTube's own host; when
/// it cannot be, the placeholder is a deliberate tile rather than a gap, so a
/// row offline still reads as a workout.
struct WorkoutVideoRow: View {
    let video: CatalogVideo
    var action: () -> Void = {}
    /// Nil where there is nothing to save to: the row then renders without a
    /// heart rather than with a dead one.
    var isSaved: Bool?
    /// The day this video is scheduled for, when it is. Shown as a chip so a
    /// scheduled row is recognisable in a list of forty.
    var scheduledDay: Date?
    var onToggleSaved: () -> Void = {}
    @Environment(\.colorScheme) private var scheme

    private let thumbnailWidth: CGFloat = 128

    var body: some View {
        // The heart is a sibling of the opening button, never inside it:
        // SwiftUI gives a button nested in a button no defined semantics, and
        // saving a video would also open it.
        HStack(alignment: .top, spacing: 0) {
            Button(action: action) { content }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(video.title), \(video.channel), \(video.durationMinutes) minutes, \(video.split), intensity \(video.intensity) of 3")
                .accessibilityHint("Opens the workout")
            if let isSaved { saveButton(isSaved) }
        }
        .padding(.vertical, 12)
        .padding(.leading, 12)
        // The heart's own 44pt box is the right-hand gutter; a second 12pt
        // beside it would cost the title a word for no visible margin.
        .padding(.trailing, isSaved == nil ? 12 : 0)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(LifeOSTokens.cardSurface.resolve(scheme))
        )
    }

    private var content: some View {
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
                    // A long channel name used to push the minutes off the end
                    // once the heart took its 44pt: shrink the line instead of
                    // dropping the one number a person scans for.
                    .minimumScaleFactor(0.85)
                // Dots and chips keep their own lines: three chips and a
                // scale do not both fit beside a thumbnail, and a chip
                // truncated to "Dum…" is worse than a taller row.
                intensityDots
                chips
            }
            Spacer(minLength: 0)
        }
    }

    /// A 44pt target on a row that is already a button, so the two never
    /// compete for the same tap.
    private func saveButton(_ saved: Bool) -> some View {
        Button(action: onToggleSaved) {
            Image(systemName: saved ? "heart.fill" : "heart")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LifeOSTokens.accent)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(saved ? "Saved" : "Save")
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
            if let scheduledDay { dayChip(scheduledDay) }
            chip(video.split)
            // The day takes the equipment's place rather than crowding it:
            // four chips beside a thumbnail truncate to "T…" and "Dum…", and
            // which day this is matters more here than which dumbbells.
            if scheduledDay == nil {
                ForEach(video.equipment.prefix(2), id: \.self) { chip($0) }
            }
        }
        .lineLimit(1)
    }

    /// "Mon 15": the weekday carries the meaning, the number settles which one.
    private func dayChip(_ day: Date) -> some View {
        HStack(spacing: 3) {
            Image(systemName: "calendar").font(.system(size: 9, weight: .semibold))
            Text(day.formatted(.dateTime.weekday(.abbreviated).day()))
                .font(LifeOSType.eyebrow.weight(.semibold))
        }
        .foregroundStyle(LifeOSTokens.accent)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(LifeOSTokens.accent.opacity(0.12), in: Capsule())
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
