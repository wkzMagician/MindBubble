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
    ReminderDeliveryLedger.record(response.notification)
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
    ReminderDeliveryLedger.record(notification)
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}

enum ReminderDeliveryLedger {
  static let key = "mindbubble.delivered"
  static let acknowledgedKey = "mindbubble.delivered.acknowledged"
  static func record(_ notification: UNNotification) {
    let info = notification.request.content.userInfo
    guard let eventId = info["eventId"] as? String,
          let bubbleId = info["bubbleId"] as? String else { return }
    let acknowledged = UserDefaults.standard.stringArray(forKey: acknowledgedKey) ?? []
    if acknowledged.contains(eventId) { return }
    var events = UserDefaults.standard.array(forKey: key) as? [[String: Any]] ?? []
    if !events.contains(where: { ($0["eventId"] as? String) == eventId }) {
      events.append(["eventId": eventId, "bubbleId": bubbleId,
                     "at": notification.date.timeIntervalSince1970 * 1000])
      UserDefaults.standard.set(events, forKey: key)
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
      case "deliveredReminders":
        UNUserNotificationCenter.current().getDeliveredNotifications { notifications in
          DispatchQueue.main.async {
            notifications.forEach { ReminderDeliveryLedger.record($0) }
            result(UserDefaults.standard.array(forKey: ReminderDeliveryLedger.key) ?? [])
          }
        }
      case "acknowledgeReminders":
        let args = call.arguments as? [String: Any]
        let ids = args?["ids"] as? [String] ?? []
        let events = UserDefaults.standard.array(forKey: ReminderDeliveryLedger.key) as? [[String: Any]] ?? []
        UserDefaults.standard.set(events.filter { !ids.contains($0["eventId"] as? String ?? "") },
                                  forKey: ReminderDeliveryLedger.key)
        let previous = UserDefaults.standard.stringArray(forKey: ReminderDeliveryLedger.acknowledgedKey) ?? []
        UserDefaults.standard.set(Array(Set(previous + ids)), forKey: ReminderDeliveryLedger.acknowledgedKey)
        result(nil)
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
    content.body = item["summary"] as? String ?? ""
    content.sound = .default
    content.userInfo = ["bubbleId": bubbleId, "eventId": item["eventId"] as? String ?? ""]
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
