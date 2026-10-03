import Cocoa
import AVFoundation

/// The two visual modes WebcamView can be in.
enum PreviewShape: Equatable {
    /// Small circular peephole, draggable and resizable, lives in a corner.
    case circle
    /// Large rounded rectangle used for talking to the camera.
    case rect
}

// MARK: - PreviewWindow

/// A borderless, always-on-top window that hosts the webcam preview.
///
/// Key behavior vs. Iris:
/// * `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`
///   keeps the preview visible while swiping between Spaces and over fullscreen
///   apps (Iris drops it because it only uses `.floating` level).
/// * Double-click toggles between the small circle and a big rectangular view.
final class PreviewWindow: NSWindow {

    private let camera: CameraManager
    private let previewView = PreviewView(frame: .zero)

    private(set) var shape: PreviewShape = .circle

    /// Right-click context menu builder.
    var onContextMenu: ((NSEvent) -> NSMenu?)?

    init(camera: CameraManager) {
        self.camera = camera

        let size = Preferences.shared.circleSize
        let frame = Self.initialCircleFrame(size: size)

        super.init(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false                         // shadow drawn by the content layer
        isMovableByWindowBackground = false       // dragging is handled manually
        acceptsMouseMovedEvents = true
        isReleasedWhenClosed = false
        level = .floating

        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

        previewView.setPreviewLayer(camera.previewLayer)
        previewView.onToggleShape = { [weak self] in
            self?.toggleShape()
        }
        previewView.onContextMenu = { [weak self] event in
            self?.onContextMenu?(event)
        }
        contentView = previewView
    }

    private static func initialCircleFrame(size: CGFloat) -> NSRect {
        let saved = Preferences.shared.circleOrigin
        if saved.x != 0 || saved.y != 0 {
            let savedRect = NSRect(origin: saved, size: NSSize(width: size, height: size))
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(savedRect) }) {
                return savedRect
            }
        }
        let vf = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let origin = CGPoint(x: vf.midX - size / 2, y: vf.midY - size / 2)
        // Persist the default so collapsing out of the big preview returns here.
        Preferences.shared.circleOrigin = origin
        return NSRect(origin: origin, size: NSSize(width: size, height: size))
    }

    // MARK: - Show / hide

    func show() {
        orderFrontRegardless()
        previewView.setMirrored(Preferences.shared.mirror)
        camera.startSession()
    }

    func hide() {
        orderOut(nil)
        camera.stopSession()
    }

    func setMirrored(_ mirrored: Bool) {
        previewView.setMirrored(mirrored)
    }

    // MARK: - Shape switching

    func toggleShape() {
        switch shape {
        case .circle: expandToPresentation()
        case .rect: collapseToCircle()
        }
    }

    private func expandToPresentation() {
        let target = presentationFrame()
        shape = .rect

        // Animate the growth first, then round the corners once we're big.
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            },
            completionHandler: { [weak self] in
                self?.previewView.shape = .rect
            }
        )
    }

    private func collapseToCircle() {
        previewView.shape = .circle
        shape = .circle

        let target = circleFrame()
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.3
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                animator().setFrame(target, display: true)
            },
            completionHandler: nil
        )
    }

    private func presentationFrame() -> NSRect {
        guard let screen = screen ?? NSScreen.main else { return frame }
        let vf = screen.visibleFrame

        if let saved = Preferences.shared.presentationRect, vf.intersects(saved) {
            return saved
        }

        var w = vf.width * 0.72
        var h = w * (9.0 / 16.0)
        if h > vf.height * 0.8 {
            h = vf.height * 0.8
            w = h * (16.0 / 9.0)
        }
        if w > vf.width * 0.94 {
            w = vf.width * 0.94
            h = w * (9.0 / 16.0)
        }
        return NSRect(x: vf.midX - w / 2, y: vf.midY - h / 2, width: w, height: h)
    }

    private func circleFrame() -> NSRect {
        let size = Preferences.shared.circleSize
        var origin = Preferences.shared.circleOrigin
        guard let screen = screen ?? NSScreen.main else {
            return NSRect(origin: origin, size: NSSize(width: size, height: size))
        }
        let vf = screen.visibleFrame

        // Never saved (or bogus zero origin) → center on the current screen.
        if origin.x == 0 && origin.y == 0 {
            origin = CGPoint(x: vf.midX - size / 2, y: vf.midY - size / 2)
            Preferences.shared.circleOrigin = origin
        }

        let r = NSRect(origin: origin, size: NSSize(width: size, height: size))
        if vf.intersects(r) { return r }

        // Saved circle is off-screen (display unplugged, etc.) → re-center.
        let c = CGPoint(x: vf.midX - size / 2, y: vf.midY - size / 2)
        Preferences.shared.circleOrigin = c
        return NSRect(origin: c, size: NSSize(width: size, height: size))
    }
}

// MARK: - PreviewView

/// The host view for the camera preview.
///
/// Responsibilities:
/// * Owns the `AVCaptureVideoPreviewLayer` and clips it to a circle or a
///   rounded rectangle using a `CAShapeLayer` mask.
/// * Handles move (drag anywhere), resize (circle edge / rectangle borders),
///   and double-click to toggle shape.
final class PreviewView: NSView {

    // MARK: - Mode

    enum Interaction {
        case none, moving, resizing
    }

    enum Shape {
        case circle, rect
    }

    /// Edge zone for rectangular resize: which sides are being dragged.
    struct EdgeZone: OptionSet {
        let rawValue: Int
        static let left   = EdgeZone(rawValue: 1 << 0)
        static let right  = EdgeZone(rawValue: 1 << 1)
        static let top    = EdgeZone(rawValue: 1 << 2)
        static let bottom = EdgeZone(rawValue: 1 << 3)
        static let none: EdgeZone = []

        var isCorner: Bool {
            contains(.left) != contains(.right) && contains(.top) != contains(.bottom)
        }
    }

    // MARK: - Circle resize quadrants

    private enum Quadrant {
        case topRight, topLeft, bottomRight, bottomLeft
    }

    // MARK: - Callbacks

    var onToggleShape: (() -> Void)?
    var onContextMenu: ((NSEvent) -> NSMenu?)?

    // MARK: - Layers

    private var maskLayer = CAShapeLayer()
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var grabLayer: CALayer?   // small bottom-right handle hint in rect mode
    var shape: Shape = .circle {
        didSet { if oldValue != shape { needsLayout = true } }
    }

    // MARK: - Interaction state

    private var interaction: Interaction = .none
    private var dragStartMouse: CGPoint = .zero
    private var dragStartFrame = NSRect.zero

    // Circle resize
    private var resizeQuadrant: Quadrant = .bottomRight
    private var resizeAnchor = CGPoint.zero

    // Rect resize
    private var rectZone: EdgeZone = []

    // Hover state
    private var hoveringCircleEdge = false
    private var hoveringCircleInside = false
    private var hoveringRectZone: EdgeZone = []
    private var hoveringRectVisible = false
    private var cursorPushed = false

    // MARK: - Constraints

    private let circleEdgeThreshold: CGFloat = 18
    private let rectEdgeThreshold: CGFloat = 12
    private let minCircleSize: CGFloat = 100
    private let minRectSize = NSSize(width: 320, height: 180)

    private var maxCircleSize: CGFloat {
        guard let screen = window?.screen ?? NSScreen.main else { return 800 }
        return min(screen.visibleFrame.width, screen.visibleFrame.height)
    }

    private var maxRectSize: NSSize {
        guard let screen = window?.screen ?? NSScreen.main else { return NSSize(width: 3840, height: 2160) }
        return screen.visibleFrame.size
    }

    // MARK: - Init

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay

        maskLayer.fillColor = NSColor.black.cgColor
        maskLayer.strokeColor = nil
        maskLayer.actions = ["path": NSNull()]
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Layout

    override func layout() {
        super.layout()

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.frame = bounds
        updateShape()
        positionGrabLayer()
        CATransaction.commit()
    }

    /// (Re)builds the mask + shadow for the current shape.
    private func updateShape() {
        guard let layer = self.layer else { return }
        layer.backgroundColor = NSColor.black.cgColor

        let rect = bounds
        let path: CGPath
        switch shape {
        case .circle:
            let d = min(rect.width, rect.height)
            let circle = CGRect(
                x: (rect.width - d) / 2,
                y: (rect.height - d) / 2,
                width: d,
                height: d
            )
            path = CGPath(ellipseIn: circle, transform: nil)
        case .rect:
            path = CGPath(
                roundedRect: rect.insetBy(dx: 1, dy: 1),
                cornerWidth: 18,
                cornerHeight: 18,
                transform: nil
            )
        }

        maskLayer.path = path
        layer.mask = maskLayer

        layer.shadowPath = path
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.5
        layer.shadowRadius = 10
        layer.shadowOffset = CGSize(width: 0, height: -5)
    }

    private func positionGrabLayer() {
        if shape == .circle {
            grabLayer?.isHidden = true
            return
        }
        if grabLayer == nil {
            let g = CALayer()
            g.backgroundColor = NSColor.white.withAlphaComponent(0.4).cgColor
            g.cornerRadius = 2.5
            g.actions = ["hidden": NSNull()]
            layer?.addSublayer(g)
            grabLayer = g
        }
        grabLayer?.isHidden = false
        grabLayer?.frame = CGRect(x: bounds.width - 26, y: 8, width: 18, height: 5)
    }

    // MARK: - Preview layer

    func setPreviewLayer(_ layer: AVCaptureVideoPreviewLayer?) {
        guard let layer else { return }
        previewLayer?.removeFromSuperlayer()

        layer.actions = [
            "bounds": NSNull(),
            "position": NSNull(),
            "frame": NSNull(),
            "transform": NSNull(),
        ]
        layer.frame = bounds
        layer.videoGravity = .resizeAspectFill

        self.layer?.insertSublayer(layer, at: 0)
        previewLayer = layer
    }

    func setMirrored(_ mirrored: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        previewLayer?.transform = mirrored
            ? CATransform3DMakeScale(-1, 1, 1)
            : CATransform3DIdentity
        CATransaction.commit()
    }

    // MARK: - Gesture geometry

    private func isNearCircleEdge(_ p: CGPoint) -> Bool {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        let dx = p.x - center.x
        let dy = p.y - center.y
        let distance = sqrt(dx * dx + dy * dy)
        return distance >= (radius - circleEdgeThreshold) && distance <= radius
    }

    private func isInsideCircle(_ p: CGPoint) -> Bool {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let radius = min(bounds.width, bounds.height) / 2
        let dx = p.x - center.x
        let dy = p.y - center.y
        return (dx * dx + dy * dy) < (radius - circleEdgeThreshold) * (radius - circleEdgeThreshold)
    }

    private func quadrant(for p: CGPoint) -> Quadrant {
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        if p.x >= center.x && p.y >= center.y { return .topRight }
        if p.x < center.x && p.y >= center.y { return .topLeft }
        if p.x >= center.x && p.y < center.y { return .bottomRight }
        return .bottomLeft
    }

    private func rectZone(at p: CGPoint) -> EdgeZone {
        let b = bounds
        var zone = EdgeZone()
        if p.x <= rectEdgeThreshold { zone.insert(.left) }
        else if p.x >= b.width - rectEdgeThreshold { zone.insert(.right) }
        if p.y <= rectEdgeThreshold { zone.insert(.bottom) }
        else if p.y >= b.height - rectEdgeThreshold { zone.insert(.top) }
        return zone
    }

    // MARK: - Mouse events

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            interaction = .none
            onToggleShape?()
            return
        }

        let p = convert(event.locationInWindow, from: nil)
        guard let window else { return }

        switch shape {
        case .circle:
            if isNearCircleEdge(p) {
                interaction = .resizing
                resizeQuadrant = quadrant(for: p)
                let f = window.frame
                switch resizeQuadrant {
                case .topRight:     resizeAnchor = CGPoint(x: f.minX, y: f.minY)
                case .topLeft:      resizeAnchor = CGPoint(x: f.maxX, y: f.minY)
                case .bottomRight:  resizeAnchor = CGPoint(x: f.minX, y: f.maxY)
                case .bottomLeft:   resizeAnchor = CGPoint(x: f.maxX, y: f.maxY)
                }
            } else if isInsideCircle(p) {
                interaction = .moving
            }
        case .rect:
            let zone = rectZone(at: p)
            if !zone.isEmpty {
                interaction = .resizing
                rectZone = zone
            } else {
                interaction = .moving
            }
        }

        if interaction != .none {
            dragStartMouse = NSEvent.mouseLocation
            dragStartFrame = window.frame
            updateCursorAndHighlight()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let window, interaction != .none else { return }
        let mouse = NSEvent.mouseLocation

        switch interaction {
        case .moving:
            let dx = mouse.x - dragStartMouse.x
            let dy = mouse.y - dragStartMouse.y
            window.setFrameOrigin(NSPoint(
                x: dragStartFrame.origin.x + dx,
                y: dragStartFrame.origin.y + dy
            ))

        case .resizing:
            switch shape {
            case .circle:
                resizeCircle(mouse: mouse)
            case .rect:
                resizeRect(mouse: mouse)
            }
        case .none:
            break
        }
    }

    override func mouseUp(with event: NSEvent) {
        if interaction != .none, let window = window {
            if shape == .circle {
                Preferences.shared.circleSize = window.frame.width
                Preferences.shared.circleOrigin = window.frame.origin
            } else {
                Preferences.shared.presentationRect = window.frame
            }
        }
        interaction = .none
        updateCursorAndHighlight()
    }

    override func mouseMoved(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)

        switch shape {
        case .circle:
            let near = isNearCircleEdge(p)
            let inside = isInsideCircle(p)
            if near != hoveringCircleEdge || inside != hoveringCircleInside {
                hoveringCircleEdge = near
                hoveringCircleInside = inside
                updateCursorAndHighlight()
            }
        case .rect:
            let zone = rectZone(at: p)
            if zone != hoveringRectZone || bounds.contains(p) != hoveringRectVisible {
                hoveringRectZone = zone
                hoveringRectVisible = bounds.contains(p) && zone.isEmpty
                updateCursorAndHighlight()
            }
        }
    }

    override func mouseExited(with event: NSEvent) {
        hoveringCircleEdge = false
        hoveringCircleInside = false
        hoveringRectZone = []
        hoveringRectVisible = false
        updateCursorAndHighlight()
    }

    override func rightMouseDown(with event: NSEvent) {
        if let menu = onContextMenu?(event) {
            NSMenu.popUpContextMenu(menu, with: event, for: self)
        }
    }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        true // let drag/double-click work even when the app isn't active
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        let area = NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
    }

    // MARK: - Resize math

    private func resizeCircle(mouse: CGPoint) {
        guard let window else { return }

        let dx = abs(mouse.x - resizeAnchor.x)
        let dy = abs(mouse.y - resizeAnchor.y)
        var size = max(dx, dy)
        size = min(max(size, minCircleSize), maxCircleSize)

        let origin: CGPoint
        switch resizeQuadrant {
        case .topRight:     origin = resizeAnchor
        case .topLeft:      origin = CGPoint(x: resizeAnchor.x - size, y: resizeAnchor.y)
        case .bottomRight:  origin = CGPoint(x: resizeAnchor.x, y: resizeAnchor.y - size)
        case .bottomLeft:   origin = CGPoint(x: resizeAnchor.x - size, y: resizeAnchor.y - size)
        }

        window.setFrame(
            NSRect(origin: origin, size: NSSize(width: size, height: size)),
            display: true
        )
    }

    private func resizeRect(mouse: CGPoint) {
        guard let window else { return }

        let start = dragStartFrame
        let minW = minRectSize.width
        let minH = minRectSize.height
        let maxW = maxRectSize.width
        let maxH = maxRectSize.height

        var origin = start.origin
        var size = start.size

        if rectZone.contains(.left) {
            let w = min(max(start.maxX - mouse.x, minW), maxW)
            size.width = w
            origin.x = start.maxX - w
        } else if rectZone.contains(.right) {
            size.width = min(max(mouse.x - start.minX, minW), maxW)
        }

        if rectZone.contains(.bottom) {
            let h = min(max(start.maxY - mouse.y, minH), maxH)
            size.height = h
            origin.y = start.maxY - h
        } else if rectZone.contains(.top) {
            size.height = min(max(mouse.y - start.minY, minH), maxH)
        }

        window.setFrame(
            NSRect(origin: origin, size: size),
            display: true
        )
    }

    // MARK: - Cursor & highlight

    private func updateCursorAndHighlight() {
        if cursorPushed {
            NSCursor.pop()
            cursorPushed = false
        }
        cursorPushed = true

        switch shape {
        case .circle:
            let resizing = interaction == .resizing
            let hoveringEdge = hoveringCircleEdge && interaction == .none
            if resizing || hoveringEdge {
                NSCursor.resizeLeftRight.push()
            } else if interaction == .moving {
                NSCursor.closedHand.push()
            } else if hoveringCircleInside {
                NSCursor.openHand.push()
            } else {
                cursorPushed = false // default cursor
            }

        case .rect:
            let zone = interaction == .resizing ? rectZone : hoveringRectZone
            if interaction == .moving {
                NSCursor.closedHand.push()
            } else if !zone.isEmpty {
                let horizontal = zone.contains(.left) || zone.contains(.right)
                let vertical = zone.contains(.top) || zone.contains(.bottom)
                if horizontal && vertical {
                    NSCursor.crosshair.push()
                } else if horizontal {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.resizeUpDown.push()
                }
            } else if interaction == .none && hoveringRectVisible {
                NSCursor.openHand.push()
            } else {
                cursorPushed = false // default cursor
            }
        }
    }

    deinit {
        if cursorPushed { NSCursor.pop() }
    }
}
