import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var cameraManager: CameraManager!
    private var menuBarController: MenuBarController!
    private var previewWindow: PreviewWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        cameraManager = CameraManager()
        menuBarController = MenuBarController(cameraManager: cameraManager)
        menuBarController.install()

        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await self.cameraManager.setup()
            } catch {
                self.showError(error)
                return
            }

            let window = PreviewWindow(camera: self.cameraManager)
            window.onContextMenu = { [weak self] _ in
                self?.menuBarController.makeMenu()
            }

            self.previewWindow = window
            self.menuBarController.previewWindow = window

            if Preferences.shared.wasVisible {
                window.show()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let window = previewWindow {
            Preferences.shared.wasVisible = window.isVisible
            window.hide()
        }
        cameraManager?.stopSession()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Lives in the menu bar; never auto-quits when the window is hidden.
        return false
    }

    private func showError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "Camera Unavailable"
        alert.informativeText = error.localizedDescription
        alert.alertStyle = .warning
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
