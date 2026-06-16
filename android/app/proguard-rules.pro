# Flutter / AndroidX ProGuard & R8 keep rules
#
# These rules prevent the R8 shrinker from removing or renaming classes
# that are looked up via reflection at runtime. Without them, the
# androidx.startup InitializationProvider (which uses reflection to find
# androidx.work.impl.WorkDatabase) crashes on app start with:
#   "Failed to create an instance of class
#    androidx.work.impl.WorkDatabase.canonicalName"
# See: https://developer.android.com/jetpack/androidx/releases/startup

# --- androidx.startup: keep all initializer entries intact ---
-keep class androidx.startup.** { *; }
-keep interface androidx.startup.** { *; }
-keep class * implements androidx.startup.Initializer { *; }

# --- androidx.work: keep WorkManager + Room / SQLite intact ---
-keep class androidx.work.** { *; }
-keep interface androidx.work.** { *; }
-keep class * extends androidx.work.Worker
-keep class * extends androidx.work.CoroutineWorker
-keep class * extends androidx.work.ListenableWorker
-keep class * extends androidx.work.ListenableWorker { <init>(...); }
-keep class * extends androidx.work.Worker { <init>(...); }
-keep class * extends androidx.work.CoroutineWorker { <init>(...); }
-keep class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# --- Room (used internally by WorkManager) ---
-keep class androidx.room.** { *; }
-keep interface androidx.room.** { *; }
-keep @androidx.room.Database class * { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }
-keepclassmembers class * extends androidx.room.RoomDatabase {
    public <init>();
}

# --- AndroidX core: keep our app's NotificationHelper + receivers
# (the AGP plugin should auto-include these, but be explicit for safety) ---
-keep class com.nudge.app.** { *; }
-keep class com.nudge.app.notifications.NotificationHelper { *; }
-keep class com.nudge.app.broadcast.** { *; }
-keep class com.nudge.app.broadcast.WifiChangeBroadcastReceiver { *; }
-keep class com.nudge.app.broadcast.BatteryReceiver { *; }
-keep class com.nudge.app.workmanager.RuleWorker { *; }
-keep class com.nudge.app.MainActivity { *; }

# --- google_fonts: keep reflection-based file lookup ---
-keep class com.google.** { *; }
-keep class io.flutter.plugins.** { *; }
-dontwarn com.google.**

# --- Standard Flutter safety net ---
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.embedding.**
-dontwarn com.google.android.play.core.**

# --- Suppress noisy warnings from optional dependencies ---
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.IgnoreJRERequirement