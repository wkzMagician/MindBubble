import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  private var reminderChannel: FlutterMethodChannel?
  private var trayItem: NSStatusItem?
  private var floatingPanel: NSPanel?
  private var floatingTimer: Timer?
  private var currentBubble: String?
  private var keepInTray = false

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return !keepInTray
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func installReminderChannel(_ messenger: FlutterBinaryMessenger) {
    reminderChannel = FlutterMethodChannel(name: "mindbubble/reminder", binaryMessenger: messenger)
    reminderChannel?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "setKeepInTray":
        let args = call.arguments as? [String: Any] ?? [:]
        self.setKeepInTray(args["enabled"] as? Bool ?? false)
        result(nil)
      case "showOverlay":
        let args = call.arguments as? [String: Any] ?? [:]
        self.showReminder(args)
        result(nil)
      case "consumeLaunchBubble":
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  func shouldHideOnClose() -> Bool { keepInTray }

  private func setKeepInTray(_ enabled: Bool) {
    keepInTray = enabled
    if enabled && trayItem == nil {
      let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
      item.button?.title = "◉"
      item.button?.toolTip = "MindBubble 浮念"
      let menu = NSMenu()
      menu.addItem(NSMenuItem(title: "打开浮念", action: #selector(openMain), keyEquivalent: ""))
      menu.addItem(NSMenuItem(title: "退出浮念", action: #selector(quitApp), keyEquivalent: ""))
      for item in menu.items { item.target = self }
      item.menu = menu
      trayItem = item
    } else if !enabled, let item = trayItem {
      NSStatusBar.system.removeStatusItem(item)
      trayItem = nil
    }
  }

  @objc private func openMain() {
    NSApp.activate(ignoringOtherApps: true)
    NSApp.windows.first(where: { $0 is MainFlutterWindow })?.makeKeyAndOrderFront(nil)
  }

  @objc private func quitApp() {
    keepInTray = false
    NSApp.terminate(nil)
  }

  @objc private func openReminder() {
    openMain()
    if let id = currentBubble {
      reminderChannel?.invokeMethod("opened", arguments: id)
    }
    floatingPanel?.orderOut(nil)
  }

  private func showReminder(_ args: [String: Any]) {
    floatingTimer?.invalidate()
    floatingPanel?.close()
    guard let bytes = (args["artwork"] as? FlutterStandardTypedData)?.data,
          let picture = NSImage(data: bytes) else { return }
    currentBubble = args["bubbleId"] as? String
    let seconds = args["seconds"] as? Int ?? 10
    let corner = args["corner"] as? String ?? "bottomRight"
    let width = picture.size.width
    let height = picture.size.height
    let screen = NSScreen.main?.visibleFrame ??
      NSRect(x: 0, y: 0, width: 1024, height: 768)
    let x = corner.contains("Right") ? screen.maxX - width - 14 : screen.minX + 14
    let y = corner.contains("bottom") ? screen.minY + 14 : screen.maxY - height - 14
    let panel = NSPanel(
      contentRect: NSRect(x: x, y: y, width: width, height: height),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered, defer: false
    )
    panel.level = .floating
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    let button = NSButton(frame: NSRect(x: 0, y: 0, width: width, height: height))
    button.title = ""
    button.image = picture
    button.imagePosition = .imageOnly
    button.imageScaling = .scaleProportionallyUpOrDown
    button.isBordered = false
    button.target = self
    button.action = #selector(openReminder)
    panel.contentView = button
    panel.alphaValue = 0
    panel.orderFrontRegardless()
    floatingPanel = panel
    NSAnimationContext.runAnimationGroup { animation in
      animation.duration = 0.3
      panel.animator().alphaValue = 1
    }
    floatingTimer = Timer.scheduledTimer(
      withTimeInterval: Double(max(seconds, 1)), repeats: false
    ) { [weak self, weak panel] _ in
      guard let self = self, let panel = panel,
            self.floatingPanel === panel else { return }
      NSAnimationContext.runAnimationGroup({ animation in
        animation.duration = 0.32
        panel.animator().alphaValue = 0
      }, completionHandler: { panel.orderOut(nil) })
    }
  }}
