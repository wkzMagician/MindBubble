package com.example.mind_bubble

import android.Manifest
import android.app.*
import android.content.*
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONArray
import org.json.JSONObject

private const val REMINDER_CHANNEL = "mindbubble/reminder"
private const val NOTIFY_CHANNEL = "mindbubble.reminders"

class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var permissionResult: MethodChannel.Result? = null
    private var bubbleToOpen: String? = null

    override fun configureFlutterEngine(engine: FlutterEngine) {
        super.configureFlutterEngine(engine)
        bubbleToOpen = intent?.getStringExtra("bubbleId")
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, REMINDER_CHANNEL)
        channel!!.setMethodCallHandler { call, result ->
            when (call.method) {
                "requestPermission" -> {
                    if (Build.VERSION.SDK_INT >= 33 &&
                        checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                        permissionResult = result
                        requestPermissions(arrayOf(Manifest.permission.POST_NOTIFICATIONS), 501)
                    } else result.success(true)
                }
                "scheduleReminders" -> {
                    val values = call.argument<List<Map<String, Any>>>("items") ?: emptyList()
                    val json = JSONArray()
                    values.forEach { json.put(JSONObject(it)) }
                    ReminderAlarms.schedule(this, json)
                    result.success(null)
                }
                "cancelReminders" -> { ReminderAlarms.cancel(this); result.success(null) }
                "consumeLaunchBubble" -> {
                    result.success(bubbleToOpen)
                    bubbleToOpen = null
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        bubbleToOpen = intent.getStringExtra("bubbleId")
        bubbleToOpen?.let { channel?.invokeMethod("opened", it) }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int, permissions: Array<out String>, grantResults: IntArray
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == 501) {
            permissionResult?.success(grantResults.firstOrNull() == PackageManager.PERMISSION_GRANTED)
            permissionResult = null
        }
    }
}

object ReminderAlarms {
    private const val PREFS = "mindbubble_reminders"
    private const val IDS = "ids"
    private const val ITEMS = "items"

    private fun pending(context: Context, id: Int, title: String, bubbleId: String): PendingIntent {
        val trigger = Intent(context, ReminderReceiver::class.java).apply {
            action = "mindbubble.remind." + id
            putExtra("id", id)
            putExtra("title", title)
            putExtra("bubbleId", bubbleId)
        }
        return PendingIntent.getBroadcast(
            context, id, trigger, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )
    }

    fun cancel(context: Context) {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val ids = p.getString(IDS, "")!!.split(",").mapNotNull { it.toIntOrNull() }
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        ids.forEach { alarm.cancel(pending(context, it, "", "")) }
        p.edit().remove(IDS).remove(ITEMS).apply()
    }

    fun schedule(context: Context, items: JSONArray) {
        cancel(context)
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                NOTIFY_CHANNEL, "浮念自动浮现", NotificationManager.IMPORTANCE_DEFAULT
            ))
        }
        val ids = mutableListOf<Int>()
        val alarm = context.getSystemService(Context.ALARM_SERVICE) as AlarmManager
        val now = System.currentTimeMillis()
        for (i in 0 until items.length()) {
            val item = items.optJSONObject(i) ?: continue
            val at = item.optLong("at")
            if (at <= now) continue
            val id = item.optInt("id")
            ids.add(id)
            alarm.setAndAllowWhileIdle(
                AlarmManager.RTC_WAKEUP, at,
                pending(context, id, item.optString("title"), item.optString("bubbleId"))
            )
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putString(IDS, ids.joinToString(","))
            .putString(ITEMS, items.toString()).apply()
    }

    fun restore(context: Context) {
        val json = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString(ITEMS, null)
        if (json != null) schedule(context, JSONArray(json))
    }
}

class ReminderReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val id = intent.getIntExtra("id", 0)
        val title = intent.getStringExtra("title") ?: return
        val bubbleId = intent.getStringExtra("bubbleId") ?: return
        if (Build.VERSION.SDK_INT >= 33 &&
            context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) return
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= 26) {
            manager.createNotificationChannel(NotificationChannel(
                NOTIFY_CHANNEL, "浮念自动浮现", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra("bubbleId", bubbleId)
        }
        val click = PendingIntent.getActivity(context, id, open,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        val builder = if (Build.VERSION.SDK_INT >= 26)
            Notification.Builder(context, NOTIFY_CHANNEL) else Notification.Builder(context)
        manager.notify(id, builder
            .setSmallIcon(context.applicationInfo.icon)
            .setContentTitle(title)
            .setContentText("浮念 · 重新遇见一个想法")
            .setContentIntent(click)
            .setAutoCancel(true)
            .build())
    }
}

class ReminderBootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_BOOT_COMPLETED ||
            intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            ReminderAlarms.restore(context)
        }
    }
}
