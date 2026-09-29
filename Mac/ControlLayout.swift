import SwiftUI
import MicodexCore

/// Overlay scrollers fade after scrolling, including when macOS is configured
/// to always show legacy scrollbars. This preference is local to this view.
struct AutoHidingScrollView<Content: View>: NSViewRepresentable {
    @ViewBuilder var content: () -> Content

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = ActivityScrollView()
        scroll.contentView = TopAlignedClipView()
        scroll.drawsBackground = false
        scroll.verticalScroller = ActivityScroller()
        scroll.hasVerticalScroller = true
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.scrollerStyle = .overlay
        let document = NSHostingView(rootView: content())
        document.translatesAutoresizingMaskIntoConstraints = false
        scroll.documentView = document
        NSLayoutConstraint.activate([
            document.leadingAnchor.constraint(equalTo: scroll.contentView.leadingAnchor),
            document.trailingAnchor.constraint(equalTo: scroll.contentView.trailingAnchor),
            document.topAnchor.constraint(equalTo: scroll.contentView.topAnchor)
        ])
        return scroll
    }

    func updateNSView(_ scroll: NSScrollView, context: Context) {
        (scroll.documentView as? NSHostingView<Content>)?.rootView = content()
    }
}

private final class TopAlignedClipView: NSClipView {
    override var isFlipped: Bool { true }
}

private final class ActivityScrollView: NSScrollView {
    override func scrollWheel(with event: NSEvent) {
        (verticalScroller as? ActivityScroller)?.showWhileScrolling()
        super.scrollWheel(with: event)
    }
}

private final class ActivityScroller: NSScroller {
    private var showing = false
    private var hideTask: DispatchWorkItem?

    func showWhileScrolling() {
        showing = true; needsDisplay = true
        hideTask?.cancel()
        let hide = DispatchWorkItem { [weak self] in
            self?.showing = false; self?.needsDisplay = true
        }
        hideTask = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: hide)
    }

    override func draw(_ dirtyRect: NSRect) {
        // macOS's global "Always" preference can keep even overlay scrollers
        // painted. Suppress only this app's idle indicator, not system settings.
        if showing { super.draw(dirtyRect) }
    }

    override func mouseDown(with event: NSEvent) {
        showWhileScrolling()
        super.mouseDown(with: event)
        showWhileScrolling()
    }
}

struct ExpandableSection<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { isExpanded.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 9, weight: .semibold)).frame(width: 10)
                    Text(title)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityValue(isExpanded ? L10n.t("Expanded") : L10n.t("Collapsed"))
            if isExpanded { content() }
        }
    }
}
