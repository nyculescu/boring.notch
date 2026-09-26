//
//  AlbumArtHoverGlow.swift
//  boringNotch
//
//  Created by Catalin Niculescu on 2026-09-26.
//
//  A soft glow in the artwork's own colors while the pointer is over the
//  album art, a hint that it opens the player. Each hover opens with a short
//  flash that settles into the dimmer steady glow. It's only in the view
//  while hovered, so nothing extra is drawn the rest of the time.
//

import SwiftUI

/// The glow itself: the same artwork, blurred, behind the real one.
struct AlbumArtGlow: View {
    let image: NSImage
    let cornerRadius: CGFloat
    let radius: CGFloat
    var isFlashing = false

    /// The flash is brighter and reaches a little further than the steady glow.
    static let flashBrightness = 0.25
    static let flashReach = 1.2
    /// The steady glow is a full blurred copy plus a quarter of another: 25%
    /// stronger than one copy, which is already fully opaque.
    static let steadyBoost = 0.25

    var body: some View {
        ZStack {
            blurredArt
            blurredArt.opacity(Self.steadyBoost)
        }
        .allowsHitTesting(false)
    }

    private var blurredArt: some View {
        Image(nsImage: image)
            .resizable()
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
            .saturation(1.3)
            .brightness(isFlashing ? 0.04 + Self.flashBrightness : 0.04)
            .blur(radius: isFlashing ? radius * Self.flashReach : radius)
    }
}

private struct AlbumArtHoverGlowModifier: ViewModifier {
    let image: NSImage
    let cornerRadius: CGFloat
    let radius: CGFloat
    @State private var isHovering = false
    @State private var isFlashing = false
    @State private var flashTask: Task<Void, Never>?

    /// Up to the peak quickly, 150 ms at the peak, then a gradual fall to the
    /// steady glow: 0.7 s in all.
    private static let flashRise: Duration = .milliseconds(100)
    private static let flashPeak: Duration = .milliseconds(150)
    private static let flashFall: Duration = .milliseconds(450)

    func body(content: Content) -> some View {
        content
            .background {
                if isHovering {
                    AlbumArtGlow(image: image, cornerRadius: cornerRadius, radius: radius, isFlashing: isFlashing)
                        .transition(.opacity)
                }
            }
            .onHover { hovering in
                flashTask?.cancel()
                guard hovering else {
                    withAnimation(.easeOut(duration: 0.2)) {
                        isHovering = false
                        isFlashing = false
                    }
                    return
                }
                withAnimation(.easeOut(duration: Self.seconds(Self.flashRise))) {
                    isHovering = true
                    isFlashing = true
                }
                flashTask = Task { @MainActor in
                    try? await Task.sleep(for: Self.flashRise + Self.flashPeak)
                    guard !Task.isCancelled else { return }
                    withAnimation(.easeInOut(duration: Self.seconds(Self.flashFall))) {
                        isFlashing = false
                    }
                }
            }
            .onDisappear { flashTask?.cancel() }
    }

    private static func seconds(_ duration: Duration) -> Double {
        Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
    }
}

extension View {
    /// Glows around this album art while the pointer is over it. `radius`
    /// is how far the glow reaches, in points; keep it small next to the
    /// notch's edge, which clips anything beyond it.
    func albumArtHoverGlow(_ image: NSImage, cornerRadius: CGFloat, radius: CGFloat) -> some View {
        modifier(AlbumArtHoverGlowModifier(image: image, cornerRadius: cornerRadius, radius: radius))
    }
}
