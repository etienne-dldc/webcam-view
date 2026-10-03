import Foundation
import CoreGraphics

/// Simple UserDefaults-backed persistence.
///
/// All geometry is stored in global (screen) coordinates with the origin at
/// the bottom-left of the main display, matching `NSWindow.frame`.
final class Preferences {

    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Key {
        static let circleSize = "wv.circleSize"
        static let circleX    = "wv.circleX"
        static let circleY    = "wv.circleY"

        static let rectX = "wv.rectX"
        static let rectY = "wv.rectY"
        static let rectW = "wv.rectW"
        static let rectH = "wv.rectH"

        static let mirror   = "wv.mirror"
        static let visible  = "wv.visible"
        static let cameraID = "wv.cameraID"
    }

    private init() {
        defaults.register(defaults: [
            Key.circleSize: 200.0,
            Key.mirror: true,
            Key.visible: true,
        ])
    }

    // MARK: - Circle mode

    /// Diameter of the circular preview.
    var circleSize: CGFloat {
        get { CGFloat(defaults.double(forKey: Key.circleSize)) }
        set { defaults.set(Double(newValue), forKey: Key.circleSize) }
    }

    /// Where the circle lives. Returns `.zero` when never set; callers then
    /// fall back to centering on screen.
    var circleOrigin: CGPoint {
        get {
            CGPoint(
                x: defaults.double(forKey: Key.circleX),
                y: defaults.double(forKey: Key.circleY)
            )
        }
        set {
            defaults.set(Double(newValue.x), forKey: Key.circleX)
            defaults.set(Double(newValue.y), forKey: Key.circleY)
        }
    }

    // MARK: - Presentation (big rectangle) mode

    /// Last known frame of the big rectangular preview. `nil` on first use.
    var presentationRect: CGRect? {
        get {
            let w = defaults.double(forKey: Key.rectW)
            let h = defaults.double(forKey: Key.rectH)
            guard w > 0, h > 0 else { return nil }
            return CGRect(
                x: defaults.double(forKey: Key.rectX),
                y: defaults.double(forKey: Key.rectY),
                width: w,
                height: h
            )
        }
        set {
            guard let rect = newValue else { return }
            defaults.set(Double(rect.origin.x), forKey: Key.rectX)
            defaults.set(Double(rect.origin.y), forKey: Key.rectY)
            defaults.set(Double(rect.width), forKey: Key.rectW)
            defaults.set(Double(rect.height), forKey: Key.rectH)
        }
    }

    // MARK: - Other preferences

    /// Mirror the camera image horizontally (default on, like video calls).
    var mirror: Bool {
        get { defaults.bool(forKey: Key.mirror) }
        set { defaults.set(newValue, forKey: Key.mirror) }
    }

    /// Whether the preview was visible when the app quit last time.
    var wasVisible: Bool {
        get { defaults.bool(forKey: Key.visible) }
        set { defaults.set(newValue, forKey: Key.visible) }
    }

    /// Preferred camera unique ID (set when the user picks a camera).
    var cameraID: String? {
        get { defaults.string(forKey: Key.cameraID) }
        set { defaults.set(newValue, forKey: Key.cameraID) }
    }
}
