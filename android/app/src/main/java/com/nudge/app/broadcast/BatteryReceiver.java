// Battery change broadcast receiver
package com.nudge.app.broadcast;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

import androidx.work.ExistingWorkPolicy;
import androidx.work.OneTimeWorkRequest;
import androidx.work.WorkManager;

import com.nudge.app.workmanager.RuleWorker;

/**
 * Listens for battery-related system broadcasts and triggers an
 * immediate rule-evaluation run via [WorkManager]. The actual
 * notification (with the user's custom rule text + alert type) is
 * posted by [RuleWorker] after it consults the rule list from
 * SharedPreferences, so a battery event that does not match any
 * user-configured rule stays silent.
 *
 * Why we delegate to the worker rather than posting a notification
 * directly: the legacy implementation fired a hardcoded
 * "Battery is low!" message on every battery change, regardless of
 * the user's rules. That was useful as a 1.0 MVP but it does not
 * match the user-controlled model the rest of the app uses.
 */
public class BatteryReceiver extends BroadcastReceiver {
    private static final String TAG = "BatteryReceiver";
    // Same unique name the Dart "Test all rules now" button uses; the
    // REPLACE policy means a second battery event cancels the first
    // in-flight evaluation instead of stacking workers.
    private static final String UNIQUE_WORK_NAME = "rule_evaluation_work_now";

    @Override
    public void onReceive(Context context, Intent intent) {
        Log.d(TAG, "Battery event: " + intent.getAction()
                + " — enqueuing rule evaluation.");
        try {
            OneTimeWorkRequest oneTime = new OneTimeWorkRequest.Builder(
                    RuleWorker.class)
                .addTag("rule_evaluation")
                .build();
            WorkManager.getInstance(context).enqueueUniqueWork(
                    UNIQUE_WORK_NAME,
                    ExistingWorkPolicy.REPLACE,
                    oneTime);
        } catch (Exception e) {
            // Swallow the exception so a misconfigured WorkManager
            // never crashes the BroadcastReceiver (which would be
            // logged by the system and would block subsequent events).
            Log.e(TAG, "BatteryReceiver: failed to enqueue work: "
                    + e.getMessage());
        }
    }
}