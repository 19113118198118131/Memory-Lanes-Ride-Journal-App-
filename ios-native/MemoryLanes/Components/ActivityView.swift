import SwiftUI
import UIKit

// MARK: - ActivityView
//
// A thin bridge to `UIActivityViewController` so a rendered share image can be
// handed to the system share sheet. Used by Ride Detail's one-tap export.

struct ActivityView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

/// A shareable image wrapper that is `Identifiable` so it can drive `.sheet(item:)`.
struct ShareableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}
