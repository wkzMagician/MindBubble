import Flutter
import UIKit
import UserNotifications
import workmanager_apple

final class BubbleNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
  var opened: ((String) -> Void)?
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let id = response.notification.request.content.userInfo["bubbleId"] as? String {
      opened?(id)
    }
    completionHandler()
  }
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let notificationDelegate = BubbleNotificationDelegate()
  private var reminders: FlutterMethodChannel?
  private var bubbleToOpen: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    let result = super.application(application, didFinishLaunchingWithOptions: options)
    UNUserNotificationCenter.current().delegate = notificationDelegate
    notificationDelegate.opened = { [weak self] id in
      self?.bubbleToOpen = id
      self?.reminders?.invokeMethod("opened", arguments: id)
    }
    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(withIdentifier: "dartloom.sync.mindbubble.periodic")
    return result
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "MindBubbleReminder")
    reminders = FlutterMethodChannel(name: "mindbubble/reminder", binaryMessenger: registrar.messenger())
    reminders?.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { result(FlutterMethodNotImplemented); return }
      switch call.method {
      case "requestPermission":
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { allowed, _ in
          DispatchQueue.main.async { result(allowed) }
        }
      case "cancelReminders":
        self.removeReminders {
          result(nil)
        }
      case "scheduleReminders":
        let args = call.arguments as? [String: Any]
        let items = args?["items"] as? [[String: Any]] ?? []
        self.removeReminders {
          self.addReminders(items, index: 0, completion: { result(nil) })
        }
      case "consumeLaunchBubble":
        result(self.bubbleToOpen)
        self.bubbleToOpen = nil
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  private func removeReminders(_ finished: @escaping () -> Void) {
    let center = UNUserNotificationCenter.current()
    center.getPendingNotificationRequests { pending in
      let ids = pending.map { $0.identifier }.filter { $0.hasPrefix("mindbubble.reminder.") }
      center.removePendingNotificationRequests(withIdentifiers: ids)
      DispatchQueue.main.async { finished() }
    }
  }

  // Complete the operation only after all pending requests have been submitted.
  private func addReminders(
    _ items: [[String: Any]], index: Int, completion: @escaping () -> Void
  ) {
    if index >= min(48, items.count) {
      completion()
      return
    }
    let item = items[index]
    let milliseconds = (item["at"] as? NSNumber)?.doubleValue ?? 0
    let bubbleId = item["bubbleId"] as? String ?? ""
    let title = item["title"] as? String ?? ""
    let id = (item["id"] as? NSNumber)?.intValue ?? index
    let when = Date(timeIntervalSince1970: milliseconds / 1000)
    if when <= Date() || bubbleId.isEmpty {
      addReminders(items, index: index + 1, completion: completion)
      return
    }
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = "浮念 · 重新遇见一个想法"
    content.sound = .default
    content.userInfo = ["bubbleId": bubbleId]
    let components = Calendar.current.dateComponents(
      [.year, .month, .day, .hour, .minute, .second], from: when
    )
    let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
    let request = UNNotificationRequest(
      identifier: "mindbubble.reminder." + String(id),
      content: content, trigger: trigger
    )
    UNUserNotificationCenter.current().add(request) { [weak self] _ in
      DispatchQueue.main.async {
        self?.addReminders(items, index: index + 1, completion: completion)
      }
    }
  }
}
