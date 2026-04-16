package com.rnd.boomprint

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Context
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {
    private val monitoringAlertsChannel = "app/monitoring_alerts"
    private val monitoringChannelId = "monitoring_alerts"
    private val notificationPermissionRequestCode = 4101

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        createMonitoringChannel()

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            monitoringAlertsChannel,
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestNotificationPermission" -> {
                    result.success(requestNotificationPermissionIfNeeded())
                }

                "showMonitoringNotification" -> {
                    val title = call.argument<String>("title") ?: "Printer update"
                    val body = call.argument<String>("body") ?: ""
                    val success = call.argument<Boolean>("success") ?: false
                    showMonitoringNotification(title, body, success)
                    result.success(null)
                }

                else -> result.notImplemented()
            }
        }
    }

    private fun requestNotificationPermissionIfNeeded(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            return true
        }
        if (
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            return true
        }
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            notificationPermissionRequestCode,
        )
        return false
    }

    private fun createMonitoringChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel =
            NotificationChannel(
                monitoringChannelId,
                "Print monitoring",
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = "Paused, error, and success alerts while monitoring a print."
            }
        manager.createNotificationChannel(channel)
    }

    private fun showMonitoringNotification(title: String, body: String, success: Boolean) {
        if (!requestNotificationPermissionIfNeeded()) {
            return
        }

        val builder =
            NotificationCompat.Builder(this, monitoringChannelId)
                .setSmallIcon(R.mipmap.ic_launcher)
                .setContentTitle(title)
                .setContentText(body)
                .setStyle(NotificationCompat.BigTextStyle().bigText(body))
                .setPriority(
                    if (success) {
                        NotificationCompat.PRIORITY_DEFAULT
                    } else {
                        NotificationCompat.PRIORITY_HIGH
                    },
                )
                .setCategory(
                    if (success) {
                        NotificationCompat.CATEGORY_STATUS
                    } else {
                        NotificationCompat.CATEGORY_ALARM
                    },
                )
                .setAutoCancel(true)
                .setDefaults(NotificationCompat.DEFAULT_SOUND or NotificationCompat.DEFAULT_VIBRATE)

        val manager =
            getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        manager.notify(
            if (success) {
                4103
            } else {
                4102
            },
            builder.build(),
        )
    }
}
