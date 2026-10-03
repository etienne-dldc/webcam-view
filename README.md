# WebcamView

A tiny personal macOS app (AppKit + AVFoundation, no Xcode project needed) that
shows your webcam as a circular, always-on-top window — the same idea as
[Iris](https://github.com/ahmetb/Iris), with two changes:

1. **Double-click toggles a big rectangular preview.** Double-click the small
   circle and it expands into a large (~70% screen width, 16:9) rounded
   rectangle so you can talk to the camera; double-click again and it shrinks
   back down to the circle in the corner. In the big preview you can drag it
   around and resize it from the borders/corners.
2. **The preview survives Space switches.** Iris disappears when you swipe
   between Spaces; this app sets `collectionBehavior` to
   `[.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]`, so the peephole and
   the big preview stay visible on every Space — including over fullscreen apps.

## Features

* Menu-bar only app (no Dock icon).
* Circular preview: drag anywhere inside to move, drag near the edge to resize
  (stays a perfect circle, 100–screen size).
* Big rectangular "presentation" preview: double-click to toggle in/out, drag to
  move, drag edges/corners to resize.
* Always on top, across all Spaces and fullscreen apps.
* Remembers circle size/position, preview size/position, mirror setting, and
  the chosen camera.
* Camera reconnect: recovers after sleep and falls back if your camera is
  unplugged.
* Right-click menu: show/hide, toggle big preview, mirror view, camera
  selection, quit.

## Build & run

Requires only the Xcode Command Line Tools (Swift + SwiftPM). No full Xcode.

```bash
./build.sh   # builds build/WebcamView.app
./run.sh     # builds and launches it
```

or manually:

```bash
swift build -c release --product WebcamView
./build.sh
open build/WebcamView.app
```

On first launch macOS asks for camera access (System Settings > Privacy &
Security > Camera). The app is ad-hoc signed, so after a rebuild you may be
asked once more — that's normal.

## Usage

| Action | Result |
| --- | --- |
| Double-click the circle | Toggle big rectangular preview |
| Drag inside the circle | Move it |
| Drag near the circle's edge | Resize (stays circular) |
| Drag anywhere in the big preview | Move it |
| Drag the big preview's border/corner | Resize it |
| Double-click the big preview | Back to the circle |
| Menu bar icon, left click | Show / hide the preview |
| Menu bar icon, right click | Menu (show/hide, big preview, mirror, camera, quit) |

## Notes

* Built for Apple Silicon (`arm64`) and macOS 14+. No Intel support, by design.
* Personal tool: no Sparkle, no sandbox, no notarization. The bundle id is
  `dev.dldc.webcamview`.

## Project layout

```
Package.swift                    # SwiftPM manifest (no external deps)
Resources/Info.plist             # app metadata (menu-bar only, camera usage)
Sources/WebcamView/
  main.swift                     # entry point
  AppDelegate.swift              # lifecycle + wiring
  CameraManager.swift            # AVCaptureSession + recovery
  PreviewWindow.swift            # the window + interactive preview view
  MenuBarController.swift        # status item/menu
  Preferences.swift              # UserDefaults persistence
build.sh                         # build + assemble + ad-hoc sign WebcamView.app
run.sh                           # build + open
```
