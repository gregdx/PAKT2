import SwiftUI
import UIKit

/// Wraps a SwiftUI view (typically DeviceActivityReport) in a UIKit container
/// that forces `isUserInteractionEnabled = false` on the underlying UIView tree.
/// This lets the parent ScrollView handle scroll gestures instead of the DAR
/// remote view stealing them.
struct PassthroughDAR<Content: View>: UIViewRepresentable {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    func makeUIView(context: Context) -> PassthroughContainerView {
        let host = UIHostingController(rootView: content)
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false

        let container = PassthroughContainerView()
        container.addSubview(host.view)

        NSLayoutConstraint.activate([
            host.view.topAnchor.constraint(equalTo: container.topAnchor),
            host.view.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            host.view.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        // Force disable interaction on ALL subviews recursively
        disableInteraction(host.view)

        return container
    }

    func updateUIView(_ uiView: PassthroughContainerView, context: Context) {
        // Re-disable on update in case the remote view reloads
        disableInteraction(uiView)
    }

    private func disableInteraction(_ view: UIView) {
        view.isUserInteractionEnabled = false
        for sub in view.subviews {
            disableInteraction(sub)
        }
    }
}

/// A UIView that always passes touch events through to the superview.
class PassthroughContainerView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        // Return nil = "I don't handle this touch, pass it up"
        return nil
    }
}
