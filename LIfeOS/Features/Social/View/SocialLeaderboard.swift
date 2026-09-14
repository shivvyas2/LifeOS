import SwiftUI
import DesignSystem
import Integrations

/// Server ranks are kept intact, including ties. Large type uses a single readable list.
struct SocialLeaderboard: View {
    let entries: [LeaderboardEntry]
    let metric: LeaderboardMetric
    let myID: UUID?
    var select: (SocialProfile) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    private var podium: [LeaderboardEntry] {
        let top = Array(entries.prefix(3))
        // Do not arbitrarily feature only some people from a tie across the podium boundary.
        guard entries.count <= 3 || entries[3].position != top.last?.position else { return [] }
        return top.count == 3 && Set(top.map(\.position)).count == 3 ? [top[1], top[0], top[2]] : top
    }
    private var distinctRanks: Bool { Set(podium.map(\.position)).count == podium.count }
    private var unit: String { "out of 100" }
    private func profile(_ entry: LeaderboardEntry) -> SocialProfile {
        SocialProfile(userID: entry.userID, displayName: entry.displayName, avatarPath: entry.avatarPath)
    }

    var body: some View {
        VStack(spacing: 26) {
            if !typeSize.isAccessibilitySize && !podium.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(podium) { entry in
                        Button { select(profile(entry)) } label: {
                            podiumPerson(entry)
                        }.buttonStyle(.plain).frame(maxWidth: .infinity)
                    }
                }.padding(.top, 8).padding(.bottom, 4)
            }
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("The lineup").lifeOSText(.sectionTitle)
                    Spacer()
                    Text("\(entries.count) sharing").lifeOSText(.caption).foregroundStyle(.secondary)
                }.padding(.bottom, 6)
                ForEach(entries) { entry in
                    Button { select(profile(entry)) } label: { rankedRow(entry) }
                        .buttonStyle(.plain)
                    if entry.id != entries.last?.id { Divider().padding(.leading, 40) }
                }
            }
            Text("Equal scores share a rank. Compare the same day; devices and personal goals can differ.")
                .lifeOSText(.caption).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func podiumPerson(_ entry: LeaderboardEntry) -> some View {
        let first = entry.position == 1
        return VStack(spacing: 10) {
            SocialAvatar(profile: profile(entry), size: first && distinctRanks ? 94 : 76)
                .overlay(alignment: .bottom) {
                    Text("\(entry.position)").font(.caption.bold()).monospacedDigit()
                        .foregroundStyle(SocialTheme.ink).frame(width: 28, height: 28)
                        .background(first ? SocialTheme.yellow : SocialTheme.color(for: entry.id), in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2)).offset(y: 10)
                }.padding(.bottom, 10)
            Text(entry.displayName).lifeOSText(.rowTitle).foregroundStyle(.primary)
                .multilineTextAlignment(.center).lineLimit(2).frame(minHeight: 24, alignment: .top)
            Text("\(entry.score.formatted())/100").lifeOSText(.caption).foregroundStyle(.secondary)
        }
        .padding(.top, distinctRanks && !first ? 24 : 0)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(entry.position), \(entry.displayName), \(entry.score) \(unit), \(entry.sourceName)")
        .accessibilityHint("View profile")
    }

    private func rankedRow(_ entry: LeaderboardEntry) -> some View {
        HStack(spacing: 10) {
            Text("\(entry.position)").lifeOSText(.rowTitle).monospacedDigit()
                .foregroundStyle(.secondary).frame(width: 24)
            SocialAvatar(profile: profile(entry), size: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.displayName).lifeOSText(.rowTitle).foregroundStyle(.primary)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.userID == myID { Text("You").font(.caption.bold()).foregroundStyle(LifeOSTokens.accent) }
                Text(entry.sourceName).lifeOSText(.caption).foregroundStyle(.secondary)
                Text("Synced \(entry.updatedAt.formatted(.relative(presentation: .named)))").lifeOSText(.caption).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Text(entry.score.formatted()).font(.headline).monospacedDigit()
                .foregroundStyle(SocialTheme.ink).padding(10).frame(minWidth: 44, minHeight: 44)
                .background(SocialTheme.color(for: entry.id), in: RoundedRectangle(cornerRadius: 24))
        }
        .padding(.vertical, 10).contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Rank \(entry.position), \(entry.displayName)\(entry.userID == myID ? ", you" : ""), \(entry.score) \(unit), \(entry.sourceName), updated \(entry.updatedAt.formatted(.relative(presentation: .named)))")
        .accessibilityHint("View profile")
    }
}
