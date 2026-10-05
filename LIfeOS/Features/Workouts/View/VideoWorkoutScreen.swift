import SwiftUI
import AppSurfaces
import DesignSystem
import Persistence
import Integrations

/// One video, and the session that follows it.
///
/// The rings float over the video in every layout, wherever the person last
/// put them; they start at the top leading edge, the corner farthest from
/// YouTube's control bar and its branding, and a drop onto that bar is moved
/// off it. Portrait keeps the workout's details, the clock and the recorder's
/// controls under the player. Full screen, entered by a button or by turning
/// the phone, hands the screen to the video and puts the controls behind one
/// glass button.
struct VideoWorkoutScreen: View {
    let video: CatalogVideo
    @Bindable var model: ActivityRecorder

    @State private var hudExpanded = true
    @State private var playerFailed = false
    @State private var showControls = false
    /// Full screen chosen by the button, as opposed to by rotation.
    @State private var immersive = false
    /// Full screen left by the button while still in landscape. Only an iPad
    /// can set it: a phone in landscape leaves by turning back upright.
    @State private var leftLandscape = false
    /// Where the letterboxed player sits in full screen portrait, so the
    /// control strip the HUD avoids is the player's, not the screen's.
    @State private var playerFrame = CGRect.zero
    @State private var host = YouTubePlayerHost()
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// The screen's own size, measured behind the content and outside the
    /// safe area. Landscape is wider than tall, which an iPad reports where
    /// the compact vertical size class never would.
    @State private var screen = CGSize.zero
    @Environment(\.colorScheme) private var scheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The split decides what the recorder calls this session. A video is a
    /// strength session unless it plainly is not.
    static func activity(for split: String) -> ActivityType {
        switch split.lowercased() {
        case "cardio": ActivityCatalog.other
        case "mobility": ActivityCatalog.yoga
        default: ActivityCatalog.strength
        }
    }

    private var isLandscape: Bool { screen.width > screen.height }
    private var isWide: Bool { sizeClass == .regular && screen.width >= 900 }
    private var isFullScreen: Bool { (isLandscape && VideoWorkoutLayout.landscapeOverlay && !leftLandscape) || immersive }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(video.youtubeID)") }

    var body: some View {
        Group {
            if isFullScreen {
                fullScreen
            } else {
                portrait
            }
        }
        // Measured behind the content and outside the safe area, so hiding
        // the bars in full screen cannot change the size the layout decision
        // reads; otherwise a near square window would flip between layouts.
        .background {
            Color.clear.ignoresSafeArea()
                .onGeometryChange(for: CGSize.self) { $0.size } action: { screen = $0 }
        }
        .navigationTitle("Workout")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(isFullScreen ? .hidden : .visible, for: .navigationBar)
        .toolbar(isFullScreen ? .hidden : .visible, for: .tabBar)
        .statusBarHidden(isFullScreen)
        .sheet(isPresented: $showControls) { controlsSheet }
        .tint(LifeOSTokens.accent)
        // The one screen on a phone allowed to turn. Handed back on the way
        // out, so the next screen is not asked to draw a landscape it has no
        // layout for.
        .onAppear { if UIDevice.current.userInterfaceIdiom == .phone { OrientationLock.allow(.allButUpsideDown) } }
        .onDisappear { OrientationLock.release() }
        .onChange(of: isLandscape) { _, landscape in if !landscape { leftLandscape = false } }
    }

    // MARK: Portrait

    private var portrait: some View {
        ZStack {
            LifeOSTokens.canvas.resolve(scheme).ignoresSafeArea()
            ScrollView {
                if isWide {
                    HStack(alignment: .top, spacing: 28) {
                        playerCard.frame(maxWidth: .infinity)
                        VStack(alignment: .leading, spacing: 18) { portraitDetails }.frame(width: 360)
                    }
                    .padding(20).padding(.bottom, 24)
                } else {
                    VStack(alignment: .leading, spacing: 18) {
                        playerCard
                        portraitDetails
                    }
                    .frame(maxWidth: 620).frame(maxWidth: .infinity)
                    .padding(20).padding(.bottom, 24)
                }
            }
        }
    }

    /// The player with its rings and the full-screen button.
    private var playerCard: some View {
        player
            .aspectRatio(VideoWorkoutLayout.playerAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay {
                if model.hasSession, let readout = model.readout {
                    DraggableHUD(placement: "compact",
                                 avoiding: { VideoWorkoutLayout.controlStrip(in: $0) }) {
                        rings(readout, repControls: false)
                    }
                }
            }
            .overlay(alignment: .topTrailing) {
                fullScreenButton(entering: true).padding(VideoWorkoutLayout.overlayInset)
            }
    }

    /// Everything under, or beside, the player.
    @ViewBuilder private var portraitDetails: some View {
        openInYouTube
        details
        if model.hasSession || model.saved {
            if model.readout != nil {
                elapsedLine
                if model.selection.countsReps, model.hasSession { repControlsRow }
            }
            ActivityControls(model: model, onDone: { dismiss() })
        } else {
            startButton
        }
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.circle")
                .font(LifeOSType.secondary)
                .foregroundStyle(LifeOSTokens.alertText.resolve(scheme))
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(video.title)
                .font(LifeOSType.sectionTitle)
                .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                .fixedSize(horizontal: false, vertical: true)
            Text("\(video.channel) · \(video.durationMinutes) min")
                .font(LifeOSType.caption.weight(.medium))
                .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            HStack(spacing: 6) {
                chip(video.split)
                chip(intensityName)
                ForEach(video.equipment.prefix(2), id: \.self) { chip($0) }
            }
            .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// The clock on its own line, the way Begin Activity's hero carries it,
    /// so the rings over the video stay small.
    private var elapsedLine: some View {
        TimelineView(.periodic(from: .now, by: 1)) { timeline in
            let elapsed = model.timer?.elapsed(at: timeline.date) ?? 0
            VStack(alignment: .leading, spacing: 2) {
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    .font(.system(size: 34, weight: .medium, design: .rounded)).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.5)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
                Text("Elapsed time")
                    .font(LifeOSType.caption)
                    .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement()
            .accessibilityLabel("Elapsed time, \(Duration.seconds(elapsed).formatted(.units(allowed: [.minutes, .seconds], width: .wide)))")
        }
    }

    private var intensityName: String {
        switch video.intensity {
        case ...1: "Easy"
        case 2: "Moderate"
        default: "Hard"
        }
    }

    private func chip(_ text: String) -> some View {
        Text(text.capitalized)
            .font(LifeOSType.eyebrow.weight(.medium))
            .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(LifeOSTokens.cardSurface.resolve(scheme), in: Capsule())
    }

    private var startButton: some View {
        Button { Task { await start() } } label: {
            HStack(spacing: Space.x1) {
                if model.busy { ProgressView() } else { Image(systemName: "play.fill") }
                Text(model.busy ? "Starting…" : "Start this workout")
            }
        }
        .buttonStyle(.editorial(.primary, fullWidth: true))
        .disabled(model.busy)
    }

    /// Always on the page, not only after a failure. A video the owner has
    /// barred from embedding says so inside the player, where nothing this
    /// screen can see reaches, and someone who simply prefers YouTube's own
    /// app should not have to hit an error first to get there.
    private var openInYouTube: some View {
        VStack(alignment: .leading, spacing: 2) {
            if playerFailed {
                Text("This video will not play here.")
                    .font(LifeOSType.caption)
                    .foregroundStyle(LifeOSTokens.primaryText.resolve(scheme))
            }
            Button("Open in YouTube", systemImage: "arrow.up.forward.app") {
                if let watchURL { openURL(watchURL) }
            }
            .font(LifeOSType.label).frame(minHeight: 44)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Full screen

    /// The video and nothing else, in either orientation.
    ///
    /// Landscape lets the player fill the screen; portrait letterboxes it
    /// across the width. The rings, the start pill and the two glass buttons
    /// sit in one overlay inside the safe area, which is also the space the
    /// rings can be dragged around in.
    private var fullScreen: some View {
        ZStack(alignment: .topLeading) {
            Color.black.ignoresSafeArea()
            if isLandscape {
                player.ignoresSafeArea()
            } else {
                player
                    .aspectRatio(VideoWorkoutLayout.playerAspectRatio, contentMode: .fit)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .ignoresSafeArea(edges: .horizontal)
                    .onGeometryChange(for: CGRect.self) { $0.frame(in: .named(Self.overlaySpace)) } action: {
                        playerFrame = $0
                    }
            }
            ZStack(alignment: .topLeading) {
                if model.hasSession, let readout = model.readout {
                    DraggableHUD(placement: isLandscape ? "landscape" : "fullscreen",
                                 avoiding: { [isLandscape, playerFrame] size in
                                     VideoWorkoutLayout.controlStrip(in: size, player: isLandscape ? nil : playerFrame)
                                 }) {
                        rings(readout)
                    }
                } else if !model.saved {
                    landscapeStart.padding(VideoWorkoutLayout.overlayInset)
                }
                HStack(spacing: 10) {
                    if model.hasSession { controlsButton }
                    if !isLandscape || isPad { fullScreenButton(entering: false) }
                }
                .frame(maxWidth: .infinity, alignment: .topTrailing)
                .padding(VideoWorkoutLayout.overlayInset)
            }
        }
        .coordinateSpace(.named(Self.overlaySpace))
    }

    private nonisolated static let overlaySpace = "videoWorkoutOverlay"

    /// Into full screen from the portrait player, and back out of it. A phone
    /// in landscape leaves by turning upright, so the button is hidden there;
    /// an iPad lives in landscape and keeps it.
    private func fullScreenButton(entering: Bool) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.3)) {
                immersive = entering
                leftLandscape = entering ? false : isLandscape
            }
        } label: {
            Image(systemName: entering ? "arrow.up.left.and.arrow.down.right" : "arrow.down.right.and.arrow.up.left")
                .font(.headline).foregroundStyle(.white)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel(entering ? "Full screen" : "Exit full screen")
    }

    private func rings(_ readout: LiveSessionReadout, repControls: Bool = true) -> some View {
        SessionRings(readout: readout, activity: model.selection, zonesAvailable: model.zonesAvailable,
                     countsAutomatically: model.source == .watch,
                     onAddRep: { model.addRep() }, onRemoveRep: { model.removeRep() },
                     onNextSet: { model.nextSet() }, showsRepControls: repControls, isExpanded: $hudExpanded)
            .fixedSize()
    }

    /// Under the video in portrait, where there is room, so the rings over
    /// the video stay as small as the rings.
    private var repControlsRow: some View {
        HStack(spacing: 10) {
            Button("−1") { model.removeRep() }.accessibilityLabel("Remove one rep")
            Button("+1") { model.addRep() }.accessibilityLabel("Add one rep")
            Button("Next set") { model.nextSet() }
        }
        .buttonStyle(.editorial(.secondary, size: .compact))
    }

    /// Pause, finish and discard live in a sheet in full screen, behind one
    /// glass button, so nothing but the rings sits over the video.
    private var controlsButton: some View {
        Button { showControls = true } label: {
            Image(systemName: "ellipsis").font(.headline).foregroundStyle(.white)
                .frame(width: 44, height: 44).contentShape(Circle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: Circle())
        .accessibilityLabel("Session controls")
    }

    private var landscapeStart: some View {
        Button { Task { await start() } } label: {
            Label(model.busy ? "Starting…" : "Start this workout", systemImage: "play.fill")
                .font(LifeOSType.label)
                .padding(.horizontal, 14)
                .frame(height: VideoWorkoutLayout.overlayMaxHeight)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .background(LifeOSTokens.accent, in: Capsule())
        .disabled(model.busy)
    }

    private var controlsSheet: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Following: \(video.title) · \(video.channel)")
                        .font(LifeOSType.caption)
                        .foregroundStyle(LifeOSTokens.secondaryText.resolve(scheme))
                    ActivityControls(model: model, onDone: { showControls = false; dismiss() })
                    openInYouTube
                }
                .frame(maxWidth: 620).frame(maxWidth: .infinity)
                .padding(20)
            }
            .background(LifeOSTokens.canvas.resolve(scheme))
            .navigationTitle("Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { showControls = false } }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: Pieces

    private var player: some View {
        YouTubePlayerView(videoID: video.youtubeID, host: host) { playerFailed = true }
            .background(Color.black)
            .accessibilityLabel("\(video.title), YouTube player")
    }

    private func start() async {
        model.selection = Self.activity(for: video.split)
        // Passed to `start`, not set before it: a start that bails must not
        // leave this video stamped on whatever session comes next.
        await model.start(following: (id: video.youtubeID, split: video.split,
                                      title: video.title, channel: video.channel))
    }
}
