import AVFoundation
import SwiftUI
import UIKit

/// The supplied onboarding film replaces the former scripted ledger tour.
/// It is purely decorative: account controls remain the only interactive and
/// VoiceOver-visible elements on this screen.
struct AuthBackdropVideo: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isActive: Bool
    let isMuted: Bool
    let dockHeight: CGFloat

    @State private var player = AVQueuePlayer()
    @State private var looper: AVPlayerLooper?

    var body: some View {
        ZStack(alignment: .top) {
            Color.black
                .ignoresSafeArea()

            GeometryReader { proxy in
                AuthVideoLayer(player: player)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    // The sign-in dock gets taller when more actions or larger
                    // accessibility text are present. Keep four deliberate
                    // placements so the face moves clearly higher with each
                    // taller dock instead of lingering low in the frame.
                    .offset(y: -safeZoneLift(in: proxy.size))
                    .frame(width: proxy.size.width, height: proxy.size.height, alignment: .top)
                    .clipped()
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear(perform: updatePlayback)
        .onChange(of: isActive) { _, _ in updatePlayback() }
        .onChange(of: isMuted) { _, _ in updatePlayback() }
        .onChange(of: reduceMotion) { _, _ in updatePlayback() }
        .onDisappear { player.pause() }
    }

    private func safeZoneLift(in size: CGSize) -> CGFloat {
        guard size.height > 0 else { return 0 }

        switch dockHeight / size.height {
        case ..<0.38:
            // A compact dock leaves the video as the full establishing shot.
            return 0
        case ..<0.48:
            // A medium action set needs a small, visible lift.
            return size.height * 0.22
        case ..<0.60:
            // The regular signed-out panel has several provider buttons.
            return size.height * 0.32
        default:
            // Accessibility text or an unusually long action stack gets the
            // highest placement, keeping the subject above the controls.
            return size.height * 0.40
        }
    }

    private func updatePlayback() {
        player.isMuted = isMuted

        if looper == nil,
           let url = Bundle.main.url(forResource: "earnline-onboarding", withExtension: "mov") {
            looper = AVPlayerLooper(player: player, templateItem: AVPlayerItem(url: url))
        }

        guard isActive, !reduceMotion else {
            player.pause()
            return
        }

        player.play()
    }
}

struct AuthVideoAudioButton: View {
    @Binding var isMuted: Bool

    var body: some View {
        Button {
            isMuted.toggle()
        } label: {
            Image(systemName: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                .font(.title3.weight(.semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.white)
                // The tap target remains comfortably usable even though the
                // control itself is only a bare symbol over the video.
                .frame(width: 44, height: 44)
                .contentShape(.circle)
                .shadow(color: .black.opacity(0.68), radius: 2, y: 1)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isMuted ? "Enable sound" : "Mute sound")
        .accessibilityIdentifier("auth.videoSound")
    }
}

private struct AuthVideoLayer: UIViewRepresentable {
    let player: AVPlayer

    func makeUIView(context: Context) -> AuthVideoLayerView {
        AuthVideoLayerView(player: player)
    }

    func updateUIView(_ view: AuthVideoLayerView, context: Context) {
        view.playerLayer.player = player
    }
}

private final class AuthVideoLayerView: UIView {
    override class var layerClass: AnyClass { AVPlayerLayer.self }

    /// Guaranteed by `layerClass` above — UIKit builds this view's backing
    /// layer from that type, so the cast cannot fail.
    // swiftlint:disable:next force_cast
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }

    init(player: AVPlayer) {
        super.init(frame: .zero)
        playerLayer.player = player
        playerLayer.videoGravity = .resizeAspectFill
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
