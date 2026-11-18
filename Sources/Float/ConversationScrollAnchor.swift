import AppKit
import FloatCore
import SwiftUI

/// Follows the laid-out scroll document across history loads and viewport resizes.
struct ConversationScrollAnchor: NSViewRepresentable {
    let thread: ChatSwitcherEntry.ID?
    let latestRequest: Int
    @Binding var followsLatest: Bool

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ view: Probe, context: Context) {
        view.update(thread: thread, latestRequest: latestRequest, followsLatest: $followsLatest)
    }

    final class Probe: NSView {
        private weak var scrollView: NSScrollView?
        private var thread: ChatSwitcherEntry.ID?
        private var latestRequest: Int?
        private var followsLatest: Binding<Bool>?
        private var pinned = true
        private var needsScroll = true
        private var updateQueued = false
        private var previousGeometry: Geometry?

        private struct Geometry {
            let viewport: NSRect
            let document: NSRect
        }

        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if window == nil {
                NotificationCenter.default.removeObserver(self)
                scrollView = nil
            } else {
                scheduleUpdate()
            }
        }

        func update(thread: ChatSwitcherEntry.ID?, latestRequest: Int, followsLatest: Binding<Bool>) {
            self.followsLatest = followsLatest
            guard self.thread != thread || self.latestRequest != latestRequest else { return }
            self.thread = thread
            self.latestRequest = latestRequest
            needsScroll = true
            scheduleUpdate()
        }

        @objc private func scrollViewChanged(_ notification: Notification) {
            // Read the user's scroll position before a streamed reply can resize the document.
            if notification.name == NSScrollView.didLiveScrollNotification, let clip = scrollView?.contentView {
                pinned = atBottom(clip, bottom: bottomBounds(in: clip))
            }
            scheduleUpdate()
        }

        private func scheduleUpdate() {
            guard !updateQueued else { return }
            updateQueued = true
            // AppKit can post several notifications before SwiftUI finishes sizing the document.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                updateQueued = false
                reconcile()
            }
        }

        private func reconcile() {
            guard window != nil, let scroll = enclosingScrollView, let document = scroll.documentView else { return }
            let clip = scroll.contentView
            if scrollView !== scroll {
                let center = NotificationCenter.default
                center.removeObserver(self)
                clip.postsBoundsChangedNotifications = true
                document.postsFrameChangedNotifications = true
                center.addObserver(self, selector: #selector(scrollViewChanged(_:)),
                                   name: NSView.boundsDidChangeNotification, object: clip)
                center.addObserver(self, selector: #selector(scrollViewChanged(_:)),
                                   name: NSView.frameDidChangeNotification, object: document)
                center.addObserver(self, selector: #selector(scrollViewChanged(_:)),
                                   name: NSScrollView.didLiveScrollNotification, object: scroll)
                scrollView = scroll
                needsScroll = true
            }

            let geometry = Geometry(viewport: clip.bounds, document: clip.documentRect)
            let layoutChanged = geometry.viewport.size != previousGeometry?.viewport.size
                || geometry.document != previousGeometry?.document
            let bottom = bottomBounds(in: clip)
            if needsScroll || (pinned && layoutChanged) {
                needsScroll = false
                pinned = true
                clip.scroll(to: bottom.origin)
                scroll.reflectScrolledClipView(clip)
            } else if !pinned || (!layoutChanged && geometry.viewport.origin != previousGeometry?.viewport.origin) {
                pinned = atBottom(clip, bottom: bottom)
            }
            previousGeometry = Geometry(viewport: clip.bounds, document: clip.documentRect)
            if let followsLatest, followsLatest.wrappedValue != pinned {
                followsLatest.wrappedValue = pinned
            }
        }

        private func bottomBounds(in clip: NSClipView) -> NSRect {
            var bounds = clip.bounds
            bounds.origin.y = clip.isFlipped ? clip.documentRect.maxY : clip.documentRect.minY - bounds.height
            return clip.constrainBoundsRect(bounds)
        }

        private func atBottom(_ clip: NSClipView, bottom: NSRect) -> Bool {
            let distance = clip.isFlipped ? bottom.minY - clip.bounds.minY : clip.bounds.minY - bottom.minY
            return distance <= 3
        }
    }
}
