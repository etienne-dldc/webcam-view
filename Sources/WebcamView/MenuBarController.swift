import Cocoa
import AVFoundation

/// Minimal menu bar presence: a status item that toggles the preview on
/// left-click and shows a small menu on right-click.
final class MenuBarController: NSObject {

    private let cameraManager: CameraManager
    private var statusItem: NSStatusItem?

    weak var previewWindow: PreviewWindow?

    init(cameraManager: CameraManager) {
        self.cameraManager = cameraManager
        super.init()
    }

    func install() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = item.button else { return }

        if let image = NSImage(
            systemSymbolName: "video.circle",
            accessibilityDescription: "WebcamView"
        ) {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "🎥"
        }

        button.toolTip = "WebcamView — click to show/hide, right-click for menu"
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        statusItem = item
    }

    // MARK: - Actions

    @objc private func statusItemClicked(_ sender: Any?) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            toggleVisible()
        }
    }

    @objc func toggleVisible() {
        guard let window = previewWindow else { return }
        if window.isVisible { window.hide() } else { window.show() }
    }

    @objc func toggleShape() {
        previewWindow?.toggleShape()
    }

    @objc func toggleMirror() {
        let newValue = !Preferences.shared.mirror
        Preferences.shared.mirror = newValue
        previewWindow?.setMirrored(newValue)
    }

    @objc func selectCamera(_ sender: NSMenuItem) {
        guard let device = sender.representedObject as? AVCaptureDevice else { return }
        Task {
            do {
                try await cameraManager.switchToCamera(device)
            } catch {
                await MainActor.run { self.showError(error.localizedDescription) }
            }
        }
    }

    @objc func quit() {
        NSApp.terminate(nil)
    }

    // MARK: - Menu

    func makeMenu() -> NSMenu {
        let menu = NSMenu()

        let isVisible = previewWindow?.isVisible ?? false
        let showHide = NSMenuItem(
            title: isVisible ? "Hide Camera" : "Show Camera",
            action: #selector(toggleVisible),
            keyEquivalent: "h"
        )
        showHide.target = self
        if previewWindow == nil { showHide.isEnabled = false }
        menu.addItem(showHide)

        let shapeItem = NSMenuItem(
            title: "Toggle Large Preview",
            action: #selector(toggleShape),
            keyEquivalent: "p"
        )
        shapeItem.target = self
        if previewWindow == nil { shapeItem.isEnabled = false }
        menu.addItem(shapeItem)

        let mirrorItem = NSMenuItem(
            title: "Mirror View",
            action: #selector(toggleMirror),
            keyEquivalent: ""
        )
        mirrorItem.target = self
        mirrorItem.state = Preferences.shared.mirror ? .on : .off
        menu.addItem(mirrorItem)

        let cameraTitle = NSMenuItem(title: "Camera", action: nil, keyEquivalent: "")
        let cameraMenu = NSMenu()
        let cameras = CameraManager.availableCameras()
        if cameras.isEmpty {
            let none = NSMenuItem(title: "No Camera Available", action: nil, keyEquivalent: "")
            none.isEnabled = false
            cameraMenu.addItem(none)
        } else {
            let currentID = cameraManager.currentDevice?.uniqueID
            for camera in cameras {
                let item = NSMenuItem(
                    title: camera.localizedName,
                    action: #selector(selectCamera(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = camera
                if camera.uniqueID == currentID { item.state = .on }
                cameraMenu.addItem(item)
            }
        }
        cameraTitle.submenu = cameraMenu
        menu.addItem(cameraTitle)

        menu.addItem(NSMenuItem.separator())

        let quit = NSMenuItem(title: "Quit WebcamView", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    private func showMenu() {
        guard let button = statusItem?.button else { return }
        let menu = makeMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 5), in: button)
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "WebcamView"
        alert.informativeText = message
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
