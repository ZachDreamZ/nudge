// Periodic WorkManager worker to evaluate battery AND Wi-Fi rules from SharedPreferences
package com.nudge.app.workmanager;

import android.content.Context;
import android.net.wifi.WifiInfo;
import android.net.wifi.WifiManager;
import android.util.Log;

import java.util.Calendar;

import androidx.annotation.NonNull;
import androidx.work.Worker;
import androidx.work.WorkerParameters;

import com.nudge.app.MainActivity;
import com.nudge.app.notifications.NotificationHelper;

import org.json.JSONArray;
import org.json.JSONObject;

import java.text.SimpleDateFormat;
import java.util.Date;
import java.util.Locale;
import java.util.TimeZone;

public class RuleWorker extends Worker {
    private static final String TAG = "RuleWorker";
    private static final long COOLDOWN_MS = 5 * 60 * 1000L; // 5 min anti-spam
    private static final SimpleDateFormat ISO_FORMAT = new SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss", Locale.US);
    static {
        ISO_FORMAT.setTimeZone(TimeZone.getTimeZone("UTC"));
    }

    public RuleWorker(@NonNull Context context, @NonNull WorkerParameters params) {
        super(context, params);
    }

    @NonNull
    @Override
    public Result doWork() {
        Context context = getApplicationContext();
        Log.d(TAG, "doWork: RuleWorker started.");

        // 1. Get current battery level + connected SSID
        int batteryPct = getBatteryLevel(context);
        String currentSsid = getConnectedSSID(context);
        Log.d(TAG, String.format("doWork: Battery=%d%%, Wi-Fi=%s", batteryPct, currentSsid));

        if (batteryPct < 0) {
            Log.w(TAG, "doWork: Could not read battery level. Proceeding with Wi-Fi only.");
        }

        // 2. Fetch rules from SharedPreferences
        String rulesJson = MainActivity.getStoredRulesJson(context);
        if (rulesJson == null || rulesJson.isEmpty() || "[]".equals(rulesJson)) {
            Log.d(TAG, "doWork: No rules stored. Nothing to evaluate.");
            return Result.success();
        }

        try {
            JSONArray rulesArray = new JSONArray(rulesJson);
            Log.d(TAG, String.format("doWork: Found %d rule(s).", rulesArray.length()));

            boolean anyRuleFired = false;

            for (int i = 0; i < rulesArray.length(); i++) {
                JSONObject rule = rulesArray.getJSONObject(i);

                // Filter: only enabled rules
                boolean isEnabled = rule.optBoolean("isEnabled", true);
                if (!isEnabled) {
                    Log.d(TAG, String.format("doWork: Skipping rule %d — disabled", i));
                    continue;
                }

                String triggerType = rule.optString("triggerType", "");
                boolean fired;

                if ("BATTERY".equals(triggerType) && batteryPct >= 0) {
                    fired = evaluateBatteryRule(rule, batteryPct);
                } else if ("WIFI".equals(triggerType) && currentSsid != null) {
                    fired = evaluateWifiRule(rule, currentSsid);
                } else {
                    Log.d(TAG, String.format("doWork: Skipping rule %d — type=%s (unavailable or unknown)", i, triggerType));
                    continue;
                }

                if (fired) {
                    anyRuleFired = true;
                    // Update lastFired in the JSON array for SharedPreferences persistence
                    String now = ISO_FORMAT.format(new Date());
                    rule.put("lastFired", now);
                    Log.d(TAG, String.format("doWork: Updated lastFired=%s for rule %d", now, i));
                }
            }

            // 3. Persist updated rules (with new lastFired timestamps) back to SharedPreferences
            if (anyRuleFired) {
                String updatedJson = rulesArray.toString();
                MainActivity.writeStoredRulesJson(context, updatedJson);
                Log.d(TAG, "doWork: Persisted updated rules JSON with fresh lastFired timestamps.");
            }

            Log.d(TAG, "doWork: RuleWorker completed.");
        } catch (Exception e) {
            Log.e(TAG, "doWork: Error: " + e.getMessage());
        }

        return Result.success();
    }

    // ---- Battery Rule Evaluation ----

    private boolean evaluateBatteryRule(JSONObject rule, int batteryPct) {
        try {
            String reminderText = rule.optString("reminderText", "Smart Reminder");
            int triggerValue = Integer.parseInt(rule.optString("triggerValue", "20"));
            String comparisonOp = rule.optString("comparisonOperator", "<=");
            String lastFiredStr = rule.optString("lastFired", null);
            // alertType is optional in the JSON; NotificationHelper
            // falls back to the standard channel when missing.
            String alertType = rule.optString("alertType", null);

            Log.d(TAG, String.format("evaluateBattery: '%s' | %d%% %s %d%% | alert=%s",
                    reminderText, batteryPct, comparisonOp, triggerValue, alertType));

            // Condition check
            boolean conditionMet;
            switch (comparisonOp) {
                case "<":  conditionMet = batteryPct <  triggerValue; break;
                case ">":  conditionMet = batteryPct >  triggerValue; break;
                case "==": conditionMet = batteryPct == triggerValue; break;
                case "<=": conditionMet = batteryPct <= triggerValue; break;
                case ">=": conditionMet = batteryPct >= triggerValue; break;
                default:
                    Log.w(TAG, "evaluateBattery: Unknown op '" + comparisonOp + "'");
                    return false;
            }

            if (!conditionMet) {
                Log.d(TAG, "evaluateBattery: Condition NOT met.");
                return false;
            }

            // Quiet hours gate. Even if the condition is met, the user
            // has asked us not to fire inside a configured window. This
            // is the only thing protecting a 3am sleep from an Urgent
            // alarm.
            if (isInQuietHours(rule)) {
                Log.d(TAG, "evaluateBattery: Quiet hours — suppressed.");
                return false;
            }

            // Cooldown check
            if (isWithinCooldown(lastFiredStr)) {
                Log.d(TAG, "evaluateBattery: Cooldown active — suppressed.");
                return false;
            }

            // Fire
            String msg = String.format("Battery %d%% %s %d%% — %s", batteryPct, comparisonOp, triggerValue, reminderText);
            Log.d(TAG, "evaluateBattery: FIRING (alert=" + alertType + "): " + msg);
            NotificationHelper.showRuleEvaluationNotification(
                    getApplicationContext(), msg, alertType);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "evaluateBattery: Error: " + e.getMessage());
            return false;
        }
    }

    // ---- Wi-Fi Rule Evaluation ----

    private boolean evaluateWifiRule(JSONObject rule, String currentSsid) {
        try {
            String reminderText = rule.optString("reminderText", "Smart Reminder");
            String targetSsid = rule.optString("triggerValue", "");
            String lastFiredStr = rule.optString("lastFired", null);

            Log.d(TAG, String.format("evaluateWifi: '%s' | current=\"%s\" target=\"%s\"", reminderText, currentSsid, targetSsid));

            // Wi-Fi rules only support "==" (equals) comparison
            boolean conditionMet = currentSsid.equalsIgnoreCase(targetSsid);

            if (!conditionMet) {
                Log.d(TAG, "evaluateWifi: SSID does not match.");
                return false;
            }

            // Quiet hours gate (mirrors evaluateBatteryRule above).
            if (isInQuietHours(rule)) {
                Log.d(TAG, "evaluateWifi: Quiet hours — suppressed.");
                return false;
            }

            // Cooldown check
            if (isWithinCooldown(lastFiredStr)) {
                Log.d(TAG, "evaluateWifi: Cooldown active — suppressed.");
                return false;
            }

            // Fire
            String msg = String.format("Connected to \"%s\" — %s", currentSsid, reminderText);
            Log.d(TAG, "evaluateWifi: FIRING: " + msg);
            NotificationHelper.showWifiChangeNotification(getApplicationContext(), currentSsid);
            return true;
        } catch (Exception e) {
            Log.e(TAG, "evaluateWifi: Error: " + e.getMessage());
            return false;
        }
    }

    // ---- Helpers ----

    /**
     * Returns true when the rule has a quiet-hours window configured AND
     * the current local time falls inside it. Either bound missing means
     * "no quiet hours" (so older rule JSON without the fields works
     * unchanged). The window is `[start, end)` so a 23:00 → 07:00 rule
     * (start > end) wraps midnight. Mirrors [Rule.isInQuietHours] in
     * `lib/src/rules/hive_rules.dart` — keep the two in lock-step.
     */
    private boolean isInQuietHours(JSONObject rule) {
        int start = rule.optInt("quietStartMinutes", -1);
        int end = rule.optInt("quietEndMinutes", -1);
        if (start < 0 || end < 0) return false;
        Calendar now = Calendar.getInstance();
        int minutes = now.get(Calendar.HOUR_OF_DAY) * 60 + now.get(Calendar.MINUTE);
        if (start <= end) {
            return minutes >= start && minutes < end;
        }
        return minutes >= start || minutes < end;
    }

    private boolean isWithinCooldown(String lastFiredStr) {
        if (lastFiredStr == null || lastFiredStr.isEmpty()) return false;
        try {
            Date lastFired = ISO_FORMAT.parse(lastFiredStr);
            return (System.currentTimeMillis() - lastFired.getTime()) < COOLDOWN_MS;
        } catch (Exception e) {
            return false;
        }
    }

    private String getConnectedSSID(Context context) {
        try {
            WifiManager wifiManager = (WifiManager) context.getApplicationContext().getSystemService(Context.WIFI_SERVICE);
            if (wifiManager == null) return null;
            WifiInfo wifiInfo = wifiManager.getConnectionInfo();
            if (wifiInfo == null) return null;
            String ssid = wifiInfo.getSSID();
            if (ssid != null && ssid.startsWith("\"") && ssid.endsWith("\"")) {
                ssid = ssid.substring(1, ssid.length() - 1);
            }
            return ssid;
        } catch (Exception e) {
            Log.e(TAG, "getConnectedSSID: Error: " + e.getMessage());
            return null;
        }
    }

    private int getBatteryLevel(Context context) {
        try {
            android.os.BatteryManager bm = (android.os.BatteryManager) context.getSystemService(Context.BATTERY_SERVICE);
            if (bm != null) return bm.getIntProperty(android.os.BatteryManager.BATTERY_PROPERTY_CAPACITY);
        } catch (Exception e) {
            Log.e(TAG, "getBatteryLevel: Error: " + e.getMessage());
        }
        return -1;
    }
}