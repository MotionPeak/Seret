#if DEBUG
import SwiftUI
import DebridUI

/// Live readout of what the Siri Remote actually delivers to `PlayerInputSurface`.
///
/// Why this exists: the player's whole input design rests on one undocumented bet — that a
/// **non-focusable** UIKit view still receives `.indirect` touches, so touch-scrub and directional
/// clicks can coexist. Apple documents no routing rule for indirect touches, the tvOS simulator
/// cannot synthesise them at all, and `ace8740` is the standing precedent for an input fix that
/// passed in the simulator and was dead on the real remote. So the bet cannot be settled by
/// reasoning or by the sim — only by watching real hardware.
///
/// This turns that into a 30-second test: every recogniser reports here, and the HUD shows which
/// pipelines are alive. If TOUCH stays at 0 while PRESS climbs, the bet is wrong and the surface
/// must become focusable (with all the trade-offs that reopens). If both climb, input is arriving
/// and any remaining problem is threshold/gain, which the live dx readout tunes.
///
/// Enable with `-inputHUD` (DEBUG builds only); it is inert otherwise.
@MainActor
@Observable
final class InputProbe {
    static let shared = InputProbe()

    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-inputHUD") }

    /// Counts per channel, so a dead pipeline is obvious at a glance.
    private(set) var touchEvents = 0     // .indirect gestures: the wake long-press and the pan
    private(set) var pressEvents = 0     // button presses: arrows and select
    private(set) var lastEvent = "—"
    private(set) var lastDX: Double = 0
    private(set) var maxDX: Double = 0
    private(set) var scrubStarts = 0

    private init() {}

    func touch(_ name: String, dx: Double? = nil) {
        guard Self.isEnabled else { return }
        touchEvents += 1
        lastEvent = name
        if let dx {
            lastDX = dx
            maxDX = max(maxDX, abs(dx))
        }
    }

    func press(_ name: String) {
        guard Self.isEnabled else { return }
        pressEvents += 1
        lastEvent = name
    }

    func scrubBegan() {
        guard Self.isEnabled else { return }
        scrubStarts += 1
    }
}

/// Corner overlay. Deliberately dumb and non-interactive so it cannot perturb what it measures.
struct InputProbeHUD: View {
    @State private var probe = InputProbe.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("INPUT PROBE").font(.caption2.weight(.bold)).foregroundStyle(.yellow)
            row("TOUCH (.indirect)", "\(probe.touchEvents)",
                ok: probe.touchEvents > 0)
            row("PRESS (buttons)", "\(probe.pressEvents)", ok: probe.pressEvents > 0)
            row("scrub starts", "\(probe.scrubStarts)", ok: probe.scrubStarts > 0)
            row("last", probe.lastEvent, ok: true)
            row("dx now / max", String(format: "%.0f / %.0f", probe.lastDX, probe.maxDX), ok: true)
            Text(probe.touchEvents == 0
                 ? "no indirect touches yet — swipe the touchpad"
                 : "indirect touches ARE arriving")
                .font(.caption2)
                .foregroundStyle(probe.touchEvents == 0 ? .orange : .green)
        }
        .font(.system(size: 20, weight: .medium).monospaced())
        .padding(16)
        .background(.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 12))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(60)
        .allowsHitTesting(false)
    }

    private func row(_ label: String, _ value: String, ok: Bool) -> some View {
        HStack(spacing: 10) {
            Text(label).foregroundStyle(.white.opacity(0.7))
            Spacer(minLength: 20)
            Text(value).foregroundStyle(ok ? .green : .orange)
        }
        .frame(width: 420, alignment: .leading)
    }
}
#endif
