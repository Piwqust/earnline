#if DEBUGMENU
import AVFoundation
import SwiftUI
import UIKit

/// The supplied account-onboarding film is retained only for the Dev account
/// preview. The release app opens directly to the ledger and never compiles
/// this surface.
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
        case ..<0.38: return 0
        case ..<0.48: return size.height * 0.22
        case ..<0.60: return size.height * 0.32
        default: return size.height * 0.40
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

    // Guaranteed by `layerClass` above.
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
#endif
