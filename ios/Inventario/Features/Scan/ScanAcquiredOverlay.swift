import SwiftUI
import UIKit

// Transient "checkout ping" shown right after a valid enqueue.
// T5 integration (do NOT add here, ScannerView stays untouched):
//   @State private var acquired = ScanAcquiredController()
//   .overlay {
//       if let pill = acquired.pill {
//           ScanAcquiredOverlay(barcode: pill.barcode)
//               .id(pill.id)
//       }
//   }
//   on valid enqueue: acquired.show(barcode: code)
// Glass lives only on the overlay container via pantryGlassChrome()
// (ultraThinMaterial fallback < iOS 26 inside the helper); content
// inside uses plain Terra tokens.
@Observable
@MainActor
final class ScanAcquiredController {
    struct Pill: Identifiable {
        let id = UUID()
        let barcode: String
    }

    private(set) var pill: Pill?
    /// Same throttle as ScanSessionStore.cooldown: one announcement per enqueue.
    var announcementCooldown: TimeInterval = 1.5
    /// Time the pill stays fully visible before the 600ms fade-out.
    var visibleDuration: TimeInterval = 0.9

    private var dismissTask: Task<Void, Never>?
    private var lastAnnouncement = Date.distantPast

    // Immediate (<300ms) feedback: haptic + show, no awaits before them.
    // Empty input is ignored so T5 can call it straight from a valid enqueue.
    @discardableResult
    func show(barcode: String?) -> Bool {
        guard let code = barcode?.trimmingCharacters(in: .whitespacesAndNewlines),
              !code.isEmpty
        else { return false }
        dismissTask?.cancel()
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        announce(code)
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        withAnimation(reduceMotion ? .linear(duration: 0.2) : .spring(duration: 0.35, bounce: 0.4)) {
            pill = Pill(barcode: code)
        }
        dismissTask = Task { @MainActor [visibleDuration] in
            try? await Task.sleep(for: .seconds(visibleDuration))
            guard !Task.isCancelled else { return }
            self.dismiss()
        }
        return true
    }

    func dismiss() {
        dismissTask?.cancel()
        dismissTask = nil
        let reduceMotion = UIAccessibility.isReduceMotionEnabled
        withAnimation(reduceMotion ? .linear(duration: 0.2) : .easeOut(duration: 0.6)) {
            pill = nil
        }
    }

    // Single announcement per enqueue, throttled like the scan cooldown.
    private func announce(_ code: String) {
        guard UIAccessibility.isVoiceOverRunning else { return }
        let now = Date()
        guard now.timeIntervalSince(lastAnnouncement) >= announcementCooldown else { return }
        lastAnnouncement = now
        UIAccessibility.post(notification: .announcement, argument: "Codice acquisito \(code)")
    }
}

struct ScanAcquiredOverlay: View {
    let barcode: String

    @State private var appeared = false

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(Color.statusFresh)
                .accessibilityHidden(true)
                .scaleEffect(appeared ? 1 : 0.5)
                .opacity(appeared ? 1 : 0)
            Text("Acquisito")
                .font(.headline)
                .foregroundStyle(Color.textPrimary)
            Text(barcode)
                .font(.subheadline.monospaced())
                .foregroundStyle(Color.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
        .pantryGlassChrome()
        .transition(.opacity.combined(with: .scale(scale: 0.85)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Codice acquisito \(barcode)")
        .dynamicTypeSize(.xSmall ... .accessibility2)
        .onAppear {
            let reduceMotion = UIAccessibility.isReduceMotionEnabled
            withAnimation(reduceMotion ? .linear(duration: 0.2) : .spring(duration: 0.35, bounce: 0.4)) {
                appeared = true
            }
        }
        .onDisappear {
            appeared = false
        }
    }
}
