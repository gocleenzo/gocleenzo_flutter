import 'package:flutter/foundation.dart';
import 'package:in_app_update/in_app_update.dart';

/// Checks Google Play for a newer version of the app, and if one exists,
/// triggers Play's own native IMMEDIATE update flow — a full-screen,
/// blocking prompt that the customer cannot dismiss or work around; they
/// must update before they can use the app at all.
///
/// Android only (the underlying Play Core library has no iOS
/// equivalent) — safe to call on any platform, it simply no-ops
/// everywhere else.
///
/// WHERE TO CALL THIS: as early as possible in app startup — ideally
/// right after Supabase/Firebase initialization in main(), or as the
/// very first thing splash_screen.dart's initState() does, BEFORE any
/// routing/auth-check logic runs. If an update is available and
/// immediate-eligible, this call will not return until either the
/// update completes (app restarts automatically) or genuinely fails —
/// so nothing past this call in your startup sequence should assume it
/// always returns quickly.
class AppUpdateService {
  AppUpdateService._();

  /// Returns true if an immediate update was actually triggered (the
  /// screen the app briefly transitions to Play Store's own UI).
  /// Returns false if no update was available, the platform doesn't
  /// support it, or checking failed — in all of these "false" cases,
  /// the caller should just continue with normal app startup.
  static Future<bool> checkAndForceImmediateUpdate() async {
    if (!(defaultTargetPlatform == TargetPlatform.android)) {
      return false; // Play Core in-app updates are Android-only.
    }

    try {
      final info = await InAppUpdate.checkForUpdate();

      if (info.updateAvailability != UpdateAvailability.updateAvailable) {
        return false; // Already on the latest version.
      }

      if (info.immediateUpdateAllowed) {
        // This launches Play Store's own full-screen blocking UI. It
        // suspends here until the update completes (the OS restarts the
        // app automatically afterward) or the call throws/fails.
        await InAppUpdate.performImmediateUpdate();
        return true;
      }

      // Play sometimes only permits a FLEXIBLE update (e.g. during a
      // staged rollout, or depending on how the release was configured
      // in Play Console) even when a newer version exists. Flexible
      // updates download in the background and are inherently
      // dismissible/non-blocking by design — there's no way to force a
      // truly blocking flow in that case. Rather than silently doing
      // nothing, still start the flexible download so it's ready
      // sooner, but this does NOT satisfy a "hard block" requirement on
      // its own — see the note in the calling code about this edge case.
      if (info.flexibleUpdateAllowed) {
        await InAppUpdate.startFlexibleUpdate();
      }
      return false;
    } catch (e) {
      debugPrint('AppUpdateService: update check failed (non-fatal): $e');
      return false; // Never block app startup over a failed update check.
    }
  }
}