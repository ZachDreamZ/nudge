// Notification helper for creating and showing notifications
package com.nudge.app.notifications;

import android.app.NotificationChannel;
import android.app.NotificationManager;
import android.content.Context;
import android.media.AudioAttributes;
import android.media.RingtoneManager;
import android.net.Uri;
import android.os.Build;
import androidx.core.app.NotificationCompat;
import com.nudge.app.R;

public class NotificationHelper {
    // Legacy channel IDs. Kept around so any cached notification builder
    // we hand out (e.g. from a previous app version) still resolves to a
    // valid channel. New code should always route through
    // `routeForAlertType(...)` instead of hard-coding these.
    private static final String CHANNEL_ID_BATTERY = "battery_low_channel";
    private static final String CHANNEL_ID_WIFI = "wifi_change_channel";
    private static final String CHANNEL_ID_RULE = "rule_evaluation_channel";

    // New rule-evaluation channels. The user picks one of two alert
    // types on each rule ("default" / "alarm") and the Dart side
    // forwards the choice to us as the `alertType` argument on
    // `testRule` (and as a `alertType` JSON field for the worker's
    // background-fired rules). The ID constants are mirrored on the
    // Dart side via the `com.nudge.app/rules` MethodChannel.
    public static final String CHANNEL_ID_DEFAULT = "nudge_default_channel";
    public static final String CHANNEL_ID_ALARM = "nudge_alarm_channel";

    // Mirror of the Dart-side `AlertType` constants in
    // `lib/src/rules/hive_rules.dart`. Keep in lock-step; the routing
    // table below is the single point of truth.
    public static final String ALERT_TYPE_DEFAULT = "default";
    public static final String ALERT_TYPE_ALARM = "alarm";

    public static void createNotificationChannels(Context context) {
        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager == null) return;

        // Create channel for battery low notifications
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel batteryChannel = new NotificationChannel(
                CHANNEL_ID_BATTERY,
                "Low Battery Reminders",
                NotificationManager.IMPORTANCE_LOW
            );
            batteryChannel.setDescription("Shows a notification when battery drops below 20%");
            batteryChannel.setShowBadge(false);
            notificationManager.createNotificationChannel(batteryChannel);
        }

        // Create channel for Wi-Fi change notifications
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel wifiChannel = new NotificationChannel(
                CHANNEL_ID_WIFI,
                "Wi-Fi Change Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            );
            wifiChannel.setDescription("Shows a notification when Wi-Fi SSID changes");
            wifiChannel.setShowBadge(false);
            notificationManager.createNotificationChannel(wifiChannel);
        }

        // Legacy rule-evaluation channel. Still created so the system
        // keeps existing user-facing preferences around after upgrade.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel ruleChannel = new NotificationChannel(
                CHANNEL_ID_RULE,
                "Smart Reminder Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            );
            ruleChannel.setDescription("Shows a notification when a smart reminder rule is triggered");
            ruleChannel.setShowBadge(false);
            notificationManager.createNotificationChannel(ruleChannel);
        }

        // Standard (default) alert channel. Uses the OS notification
        // ringtone so the user gets a familiar "ding" without overriding
        // their silent mode.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel defaultChannel = new NotificationChannel(
                CHANNEL_ID_DEFAULT,
                "Smart Reminder Alerts",
                NotificationManager.IMPORTANCE_DEFAULT
            );
            defaultChannel.setDescription("Standard notification sound when a rule fires.");
            defaultChannel.setShowBadge(false);
            defaultChannel.setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION),
                new android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_NOTIFICATION)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            );
            notificationManager.createNotificationChannel(defaultChannel);
        }

        // Urgent / alarm channel. Importance HIGH so it surfaces as a
        // heads-up notification, and uses the alarm ringtone by default
        // so the user can actually hear it through Doze / silent mode.
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            NotificationChannel alarmChannel = new NotificationChannel(
                CHANNEL_ID_ALARM,
                "Urgent Alarm Alerts",
                NotificationManager.IMPORTANCE_HIGH
            );
            alarmChannel.setDescription("Loud alarm sound when an urgent rule fires.");
            alarmChannel.setShowBadge(false);
            alarmChannel.enableVibration(true);
            alarmChannel.setBypassDnd(false);
            alarmChannel.setLockscreenVisibility(NotificationCompat.VISIBILITY_PUBLIC);
            alarmChannel.setSound(
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_ALARM),
                new android.media.AudioAttributes.Builder()
                    .setUsage(android.media.AudioAttributes.USAGE_ALARM)
                    .setContentType(android.media.AudioAttributes.CONTENT_TYPE_SONIFICATION)
                    .build()
            );
            notificationManager.createNotificationChannel(alarmChannel);
        }
    }

    // Show battery low notification
    public static void showBatteryLowNotification(Context context, String reminderText) {
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID_BATTERY)
                .setSmallIcon(R.drawable.ic_battery_alert)
                .setContentTitle("Low Battery Alert")
                .setContentText(reminderText)
                .setPriority(NotificationCompat.PRIORITY_LOW)
                .setAutoCancel(true);

        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager != null) {
            notificationManager.notify(1001, builder.build());
        }
    }

    // Show Wi-Fi change notification
    public static void showWifiChangeNotification(Context context, String ssid) {
        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, CHANNEL_ID_WIFI)
                .setSmallIcon(R.drawable.ic_wifi)
                .setContentTitle("Wi-Fi Changed")
                .setContentText("Connected to: " + ssid)
                .setPriority(NotificationCompat.PRIORITY_DEFAULT)
                .setAutoCancel(true);

        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager != null) {
            notificationManager.notify(1002, builder.build());
        }
    }

    /**
     * Routes a reminder notification to the channel that matches the
     * rule's persisted `alertType`. Falls back to the standard channel
     * for unknown / null values so a stale Dart payload never throws.
     *
     * Possible values (mirrored from `AlertType` in `lib/src/rules/hive_rules.dart`):
     *   - "default"  -> nudge_default_channel  (standard notification sound)
     *   - "alarm"    -> nudge_alarm_channel    (IMPORTANCE_HIGH + alarm ringtone)
     *
     * @param context      any context with notification manager access
     * @param reminderText the body text shown in the notification
     * @param alertType    the rule's alert type (see AlertType.normalize on Dart side)
     */
    public static void showRuleEvaluationNotification(Context context, String reminderText, String alertType) {
        String channelId = routeForAlertType(alertType);
        boolean isUrgent = ALERT_TYPE_ALARM.equalsIgnoreCase(alertType);

        NotificationCompat.Builder builder = new NotificationCompat.Builder(context, channelId)
                .setSmallIcon(R.drawable.ic_notification)
                .setContentTitle(isUrgent ? "Urgent Reminder" : "Smart Reminder Triggered")
                .setContentText(reminderText)
                .setPriority(isUrgent
                        ? NotificationCompat.PRIORITY_HIGH
                        : NotificationCompat.PRIORITY_DEFAULT)
                .setCategory(isUrgent
                        ? NotificationCompat.CATEGORY_ALARM
                        : NotificationCompat.CATEGORY_REMINDER)
                .setAutoCancel(true);

        NotificationManager notificationManager = (NotificationManager) context.getSystemService(Context.NOTIFICATION_SERVICE);
        if (notificationManager != null) {
            notificationManager.notify(1003, builder.build());
        }
    }

    /**
     * Legacy overload that keeps a null alert type flowing to the legacy
     * `rule_evaluation_channel`. New code paths should pass an explicit
     * alertType string and use {@link #showRuleEvaluationNotification(Context, String, String)}.
     */
    public static void showRuleEvaluationNotification(Context context, String reminderText) {
        showRuleEvaluationNotification(context, reminderText, ALERT_TYPE_DEFAULT);
    }

    /**
     * Returns the channel ID for the given alert type. Always non-null;
     * unknown values fall back to {@link #CHANNEL_ID_DEFAULT}.
     */
    public static String routeForAlertType(String alertType) {
        if (alertType == null) return CHANNEL_ID_DEFAULT;
        if (ALERT_TYPE_ALARM.equalsIgnoreCase(alertType.trim())) {
            return CHANNEL_ID_ALARM;
        }
        return CHANNEL_ID_DEFAULT;
    }
}