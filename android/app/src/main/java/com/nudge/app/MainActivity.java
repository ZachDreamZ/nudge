// MainActivity.java — Android Entry Point with MethodChannel for rule sync
package com.nudge.app;

import android.app.Activity;
import android.content.Context;
import android.content.Intent;
import android.content.IntentFilter;
import android.content.SharedPreferences;
import android.net.Uri;
import android.os.Build;
import android.os.Bundle;
import android.util.Log;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.core.content.ContextCompat;
import androidx.work.Constraints;
import androidx.work.ExistingPeriodicWorkPolicy;
import androidx.work.ExistingWorkPolicy;
import androidx.work.OneTimeWorkRequest;
import androidx.work.PeriodicWorkRequest;
import androidx.work.WorkManager;

import com.nudge.app.broadcast.BatteryReceiver;
import com.nudge.app.broadcast.WifiChangeBroadcastReceiver;
import com.nudge.app.notifications.NotificationHelper;
import com.nudge.app.workmanager.RuleWorker;

import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.concurrent.TimeUnit;

import io.flutter.embedding.android.FlutterActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterActivity {
    private static final String TAG = "MainActivity";
    private static final String CHANNEL_NAME = "com.nudge.app/rules";
    private static final String IMPORT_CHANNEL_NAME = "com.nudge.app/import";
    private static final int PICK_FILE_REQUEST_CODE = 0xC0DE;

    private static final String PREFS_NAME = "nudge_prefs";
    private static final String RULES_KEY = "stored_rules_json";
    // Bounded FIFO log of rule firings. Stored as a JSON array string
    // in SharedPreferences so both the worker (write) and the Dart UI
    // (read) can access it without any new file I/O. Capped at
    // FIRE_LOG_MAX entries; older entries are evicted on append.
    private static final String FIRE_LOG_KEY = "fire_log_json";
    private static final int FIRE_LOG_MAX = 50;
    // org.json.* and java.util.* are imported via the existing
    // java.* / org.json.* imports at the top of the file.

    private BatteryReceiver batteryReceiver;
    private WifiChangeBroadcastReceiver wifiReceiver;

    /** Held while the system file picker is open so onActivityResult can reply. */
    @Nullable
    private MethodChannel.Result pendingPickResult;

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        Log.d(TAG, "onCreate: Dynamically registering BatteryReceiver and WifiChangeBroadcastReceiver.");

        // Dynamically register BatteryReceiver for ACTION_BATTERY_CHANGED and ACTION_BATTERY_LOW.
        // Using RECEIVER_EXPORTED because these are system broadcasts delivered by the OS.
        batteryReceiver = new BatteryReceiver();
        IntentFilter batteryFilter = new IntentFilter();
        batteryFilter.addAction(Intent.ACTION_BATTERY_CHANGED);
        batteryFilter.addAction(Intent.ACTION_BATTERY_LOW);
        batteryFilter.addAction(Intent.ACTION_BATTERY_OKAY);
        ContextCompat.registerReceiver(this, batteryReceiver, batteryFilter, ContextCompat.RECEIVER_EXPORTED);

        // Dynamically register WifiChangeBroadcastReceiver for WIFI_STATE and CONNECTIVITY_CHANGE.
        // (ACTION_BATTERY_CHANGED used to be here but is not a Wi-Fi event —
        // removing it stops the receiver from firing on every battery tick,
        // which would otherwise spam the user with constant "Connected to a
        // Wi-Fi network" notifications.)
        wifiReceiver = new WifiChangeBroadcastReceiver();
        IntentFilter wifiFilter = new IntentFilter();
        wifiFilter.addAction(android.net.wifi.WifiManager.WIFI_STATE_CHANGED_ACTION);
        wifiFilter.addAction(android.net.ConnectivityManager.CONNECTIVITY_ACTION);
        ContextCompat.registerReceiver(this, wifiReceiver, wifiFilter, ContextCompat.RECEIVER_EXPORTED);

        Log.d(TAG, "onCreate: Receivers registered successfully (exported).");
    }

    @Override
    protected void onDestroy() {
        super.onDestroy();
        try {
            if (batteryReceiver != null) {
                unregisterReceiver(batteryReceiver);
            }
            if (wifiReceiver != null) {
                unregisterReceiver(wifiReceiver);
            }
            Log.d(TAG, "onDestroy: Receivers unregistered.");
        } catch (IllegalArgumentException e) {
            Log.w(TAG, "onDestroy: Receiver was not registered: " + e.getMessage());
        }
        if (pendingPickResult != null) {
            pendingPickResult.success(null);
            pendingPickResult = null;
        }
    }

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);
        Log.d(TAG, "configureFlutterEngine: Setting up MethodChannel and WorkManager.");

        // Create notification channels on app start
        NotificationHelper.createNotificationChannels(this);

        // Set up MethodChannel to receive rules from Dart
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL_NAME)
            .setMethodCallHandler((MethodCall call, MethodChannel.Result result) -> {
                switch (call.method) {
                    case "syncRules":
                        handleSyncRules(call, result);
                        break;
                    case "testRule":
                        handleTestRule(call, result);
                        break;
                    case "runRuleWorkerNow":
                        handleRunRuleWorkerNow(result);
                        break;
                    default:
                        result.notImplemented();
                        break;
                }
            });

        // Set up MethodChannel for the file-picker used by the import flow.
        // We use the system Storage Access Framework (Intent.ACTION_OPEN_DOCUMENT)
        // so the user gets the native Files / Drive / Downloads picker.
        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), IMPORT_CHANNEL_NAME)
            .setMethodCallHandler((MethodCall call, MethodChannel.Result result) -> {
                switch (call.method) {
                    case "pickFile":
                        handlePickFile(result);
                        break;
                    default:
                        result.notImplemented();
                        break;
                }
            });

        // Schedule periodic WorkManager task (15-minute intervals for MVP)
        scheduleRuleWorker();

        Log.d(TAG, "configureFlutterEngine: Channels + WorkManager ready.");
    }

    /**
     * Receives rules JSON from Dart via MethodChannel and stores in SharedPreferences.
     * RuleWorker reads from SharedPreferences to evaluate rules in the background.
     *
     * PRIVACY: the raw rules JSON is NEVER logged. The reminder text can
     * contain anything the user typed and the SSID is location data. We
     * log only the size + a redaction note so a future bug report can
     * confirm the sync landed without leaking user content to logcat
     * in release builds.
     */
    private void handleSyncRules(MethodCall call, MethodChannel.Result result) {
        Log.d(TAG, "handleSyncRules: Received rule sync from Flutter.");

        try {
            Object rulesRaw = call.argument("rules");
            if (rulesRaw == null) {
                Log.w(TAG, "handleSyncRules: No rules data received.");
                result.success(false);
                return;
            }

            String rulesJson = rulesRaw.toString();
            Log.d(TAG, "handleSyncRules: Stored " + rulesJson.length()
                    + " chars of rules JSON (contents redacted).");

            // Store in SharedPreferences for RuleWorker to read
            SharedPreferences prefs = getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
            prefs.edit().putString(RULES_KEY, rulesJson).apply();

            Log.d(TAG, "handleSyncRules: Rules stored successfully in SharedPreferences.");
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "handleSyncRules: Error storing rules: " + e.getMessage());
            result.success(false);
        }
    }

    /**
     * Bypasses the normal battery/Wi-Fi condition check and immediately
     * posts a notification using the rule's reminder text. Invoked from
     * the home screen's "Test rule" play button so the user can preview
     * the exact notification design that the real trigger will produce.
     *
     * Expected arguments:
     *   - ruleId (Integer, optional): Hive key of the rule, for logging.
     *   - reminderText (String): text to show in the notification body.
     *   - triggerType (String, optional): "BATTERY" / "WIFI" for logging.
     *
     * PRIVACY: reminderText is NOT logged in production-shaped calls
     * because it can contain anything the user typed. The debug log
     * includes only the rule id, trigger type, and alert type.
     */
    private void handleTestRule(MethodCall call, MethodChannel.Result result) {
        Object ruleIdRaw = call.argument("ruleId");
        Object reminderRaw = call.argument("reminderText");
        Object triggerRaw = call.argument("triggerType");
        // Optional: the rule's alert type ("default" / "alarm").
        Object alertTypeRaw = call.argument("alertType");
        if (reminderRaw == null) {
            Log.w(TAG, "handleTestRule: missing reminderText argument.");
            result.error("MISSING_ARG", "reminderText is required.", null);
            return;
        }
        String reminderText = reminderRaw.toString();
        String alertType = alertTypeRaw == null ? null : alertTypeRaw.toString();
        Log.d(TAG, "handleTestRule: ruleId=" + ruleIdRaw
                + " triggerType=" + triggerRaw
                + " alertType=" + alertType
                + " reminderLength=" + reminderText.length());
        try {
            NotificationHelper.showRuleEvaluationNotification(this, reminderText, alertType);
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "handleTestRule: failed to post notification: " + e.getMessage());
            result.error("TEST_FAILED", e.getMessage(), null);
        }
    }

    /**
     * Launches the system file picker (Storage Access Framework) so the user
     * can pick a backup `.json` file. The selected file's contents are read
     * and returned to Flutter as a single string. If the user cancels,
     * `null` is returned.
     */
    private void handlePickFile(MethodChannel.Result result) {
        if (pendingPickResult != null) {
            // Another pick is already in flight; reject the new one.
            result.error("ALREADY_PICKING", "A file pick is already in progress.", null);
            return;
        }
        pendingPickResult = result;
        try {
            Intent intent = new Intent(Intent.ACTION_OPEN_DOCUMENT);
            intent.addCategory(Intent.CATEGORY_OPENABLE);
            intent.setType("application/json");
            intent.putExtra(Intent.EXTRA_MIME_TYPES,
                    new String[]{"application/json", "text/plain", "*/*"});
            startActivityForResult(intent, PICK_FILE_REQUEST_CODE);
        } catch (Exception e) {
            Log.e(TAG, "handlePickFile: failed to launch SAF picker: " + e.getMessage());
            pendingPickResult = null;
            result.error("PICK_FAILED", e.getMessage(), null);
        }
    }

    @Override
    protected void onActivityResult(int requestCode, int resultCode, @Nullable Intent data) {
        super.onActivityResult(requestCode, resultCode, data);
        if (requestCode != PICK_FILE_REQUEST_CODE) return;
        MethodChannel.Result result = pendingPickResult;
        pendingPickResult = null;
        if (result == null) return;

        if (resultCode != Activity.RESULT_OK || data == null) {
            Log.d(TAG, "onActivityResult: user cancelled file pick.");
            result.success(null);
            return;
        }

        Uri uri = data.getData();
        if (uri == null) {
            result.success(null);
            return;
        }

        try {
            getContentResolver().takePersistableUriPermission(
                    uri, Intent.FLAG_GRANT_READ_URI_PERMISSION);
        } catch (Exception e) {
            Log.w(TAG, "onActivityResult: takePersistableUriPermission failed: " + e.getMessage());
        }

        try (InputStream in = getContentResolver().openInputStream(uri);
             BufferedReader reader = new BufferedReader(
                     new InputStreamReader(in, StandardCharsets.UTF_8))) {
            StringBuilder sb = new StringBuilder();
            String line;
            while ((line = reader.readLine()) != null) {
                sb.append(line).append('\n');
            }
            String contents = sb.toString();
            // Log the size only — the contents is a user-chosen
            // backup file that may contain SSIDs.
            Log.d(TAG, "onActivityResult: read " + contents.length()
                    + " chars from " + uri);
            result.success(contents);
        } catch (Exception e) {
            Log.e(TAG, "onActivityResult: read failed: " + e.getMessage());
            result.error("READ_FAILED", e.getMessage(), null);
        }
    }

    /**
     * Forces the rule-evaluation worker to run RIGHT NOW, bypassing
     * the 15-minute periodic schedule.
     */
    private void handleRunRuleWorkerNow(MethodChannel.Result result) {
        Log.d(TAG, "handleRunRuleWorkerNow: enqueuing one-time RuleWorker.");
        try {
            OneTimeWorkRequest oneTime = new OneTimeWorkRequest.Builder(RuleWorker.class)
                .addTag("rule_evaluation")
                .build();
            WorkManager.getInstance(this).enqueueUniqueWork(
                "rule_evaluation_work_now",
                ExistingWorkPolicy.REPLACE,
                oneTime
            );
            result.success(true);
        } catch (Exception e) {
            Log.e(TAG, "handleRunRuleWorkerNow: enqueue failed: " + e.getMessage());
            result.error("ENQUEUE_FAILED", e.getMessage(), null);
        }
    }

    /**
     * Enqueues a periodic WorkManager job for RuleWorker.
     */
    private void scheduleRuleWorker() {
        Log.d(TAG, "scheduleRuleWorker: Enqueuing periodic rule evaluation.");

        Constraints constraints = new Constraints.Builder()
            .setRequiresBatteryNotLow(true)
            .build();

        PeriodicWorkRequest workRequest = new PeriodicWorkRequest.Builder(
                RuleWorker.class,
                15, TimeUnit.MINUTES
            )
            .setConstraints(constraints)
            .addTag("rule_evaluation")
            .build();

        WorkManager.getInstance(this).enqueueUniquePeriodicWork(
            "rule_evaluation_work",
            ExistingPeriodicWorkPolicy.KEEP,
            workRequest
        );

        Log.d(TAG, "scheduleRuleWorker: PeriodicWorkRequest enqueued (15-min interval).");
    }

    /**
     * Returns the stored rules JSON from SharedPreferences (used by RuleWorker).
     * PRIVACY: the JSON contents is NEVER logged — only the size.
     */
    public static String getStoredRulesJson(Context context) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        String json = prefs.getString(RULES_KEY, null);
        if (json == null) {
            Log.d(TAG, "getStoredRulesJson: no rules stored.");
        } else {
            Log.d(TAG, "getStoredRulesJson: retrieved " + json.length()
                    + " chars of rules JSON (contents redacted).");
        }
        return json;
    }

    /**
     * Writes updated rules JSON to SharedPreferences (used by RuleWorker
     * to persist lastFired timestamps after firing notifications).
     */
    public static void writeStoredRulesJson(Context context, String rulesJson) {
        SharedPreferences prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE);
        prefs.edit().putString(RULES_KEY, rulesJson).apply();
        Log.d(TAG, "writeStoredRulesJson: Persisted updated rules (" + rulesJson.length() + " chars).");
    }
}