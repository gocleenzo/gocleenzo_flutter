import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;
  static SupabaseClient get client => _client;

  // Cached app user id (set after Firebase login via edge function)
  static String? _cachedUserId;

  // FIXED: this is the actual root cause of "some customers get logged
  // out every time they close and reopen the app." _cachedUserId is a
  // static in-memory variable — Flutter wipes it back to null on EVERY
  // cold start, since the whole Dart process (and every static
  // variable in it) is destroyed when the app is closed. The real,
  // persisted login lives in SharedPreferences on disk. The safe
  // getter, loadCachedUserId(), correctly falls back to reading that
  // disk value — but the synchronous currentUserId getter below does
  // NOT; it only ever reads the in-memory variable. On a fresh cold
  // start, before anything has explicitly awaited loadCachedUserId(),
  // _cachedUserId is still null, so ANY screen that checks
  // currentUserId that early (a splash screen, an early route guard, a
  // widget's initState running before its first async call resolves)
  // sees "not logged in" and sends a genuinely logged-in customer back
  // to the login screen — even though their real session is sitting
  // right there on disk. This only shows up on SOME customers'
  // devices because it's a timing race: it depends on exactly which
  // screen runs first, how fast that device is, and whether that
  // screen's code path happens to await the safe async getter before
  // rendering or not.
  //
  // THE FIX: hydrate _cachedUserId from disk ONCE, as early as
  // possible in the app's lifecycle — before runApp() is even called.
  // Call this from main(), like:
  //
  //   Future<void> main() async {
  //     WidgetsFlutterBinding.ensureInitialized();
  //     await Supabase.initialize(...);
  //     await SupabaseService.hydrateCachedUserId();   // <-- add this
  //     runApp(const MyApp());
  //   }
  //
  // Once this has run, the in-memory value is populated for the rest
  // of the app's life (until sign-out), so EVERY screen's synchronous
  // currentUserId check — no matter which one runs first, no matter
  // how fast the device is — sees the correct, already-loaded value
  // instead of racing against an async disk read that hasn't finished
  // yet. This fixes the bug for every screen at once, without needing
  // to hunt down and fix every individual call site that might be
  // using the synchronous getter too early.
  static bool _hydrated = false;

  static Future<void> hydrateCachedUserId() async {
    if (_hydrated) return;
    _hydrated = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      _cachedUserId = prefs.getString('app_user_id');
    } catch (e) {
      debugPrint('hydrateCachedUserId: failed to read SharedPreferences: $e');
    }
  }

  /// Call this right after a successful Firebase login + edge function
  /// response, passing the `user_id` returned from the `firebase-auth`
  /// edge function. Persists it so it survives app restarts.
  static Future<void> setCachedUserId(String userId) async {
    _cachedUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_user_id', userId);
  }

  /// Clears the cached user id, both in memory and on disk. Used when a
  /// cached id turns out to be stale (points at a `users` row that no
  /// longer exists — see [loadCachedUserId]).
  static Future<void> _clearCachedUserId() async {
    _cachedUserId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('app_user_id');
  }

  /// Loads the cached user id AND validates it still points at a real
  /// row in `users`. If the row is missing (e.g. stale local cache from
  /// before a database reset, an account that got deleted, or a login
  /// that never fully completed server-side), the stale id is cleared
  /// and this returns null instead of an id that will fail every
  /// foreign-key-constrained write with a confusing error.
  ///
  /// Screens that call this already handle a null result by sending the
  /// person back to /login, so this fix is transparent to callers — no
  /// call sites need to change.
  static Future<String?> loadCachedUserId() async {
    String? id = _cachedUserId;
    if (id == null) {
      final prefs = await SharedPreferences.getInstance();
      id = prefs.getString('app_user_id');
      _cachedUserId = id;
    }
    if (id == null) return null;

    try {
      final exists = await _client
          .from('users')
          .select('id')
          .eq('id', id)
          .maybeSingle();
      if (exists == null) {
        debugPrint(
            'loadCachedUserId: cached id $id has no matching users row — clearing stale cache');
        await _clearCachedUserId();
        return null;
      }
    } catch (e) {
      // Network hiccup or similar — don't punish the user for a
      // connectivity blip by logging them out. Trust the cached id for
      // now; the real write will surface its own error if it's actually
      // invalid.
      debugPrint('loadCachedUserId: validation check failed, proceeding with cached id: $e');
    }

    return id;
  }

  /// Unified current user id — works whether the session came from
  /// Supabase auth (legacy) or Firebase auth (current flow).
  ///
  /// SAFE to use synchronously from anywhere in the app ONLY because
  /// hydrateCachedUserId() is now called once at app startup (see
  /// main()), guaranteeing _cachedUserId is already populated from
  /// disk by the time any screen's build/initState runs. If you ever
  /// remove that startup call, this getter goes back to being unsafe
  /// on a cold start — see the long comment above _hydrated for why.
  static String? get currentUserId {
    final supaUser = _client.auth.currentUser;
    if (supaUser != null) return supaUser.id;
    return _cachedUserId;
  }

  // ── Auth ────────────────────────────────────────────────────
  static Future<void> sendOtp(String phone) async {
    final fullPhone = '+91$phone';
    debugPrint('===> Sending OTP to: $fullPhone');
    await _client.auth.signInWithOtp(
      phone: fullPhone,
      shouldCreateUser: true,
    );
  }

  static Future<AuthResponse> verifyOtp(String phone, String token) async {
    return await _client.auth.verifyOTP(
      phone: '+91$phone',
      token: token,
      type: OtpType.sms,
    );
  }

  static Future<void> signOut() async {
    await NotificationService.clearTokenOnLogout();
    await _client.auth.signOut();
    await fb.FirebaseAuth.instance.signOut();
    _cachedUserId = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static User? get currentUser => _client.auth.currentUser;

  // ── Users ───────────────────────────────────────────────────
  static Future<Map<String, dynamic>?> getUserProfile(
      String userId) async {
    final res = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return res;
  }

  static Future<void> updateUserProfile(
      String userId, Map<String, dynamic> data) async {
    await _client.from('users').update(data).eq('id', userId);
  }

  static Future<void> createUser(Map<String, dynamic> data) async {
    await _client.from('users').upsert(data);
  }

  // ── Services ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getServices() async {
    final res = await _client
        .from('services')
        .select()
        .eq('is_active', true)
        .order('category');
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>?> getServiceById(
      String id) async {
    final res = await _client
        .from('services')
        .select()
        .eq('id', id)
        .maybeSingle();
    return res;
  }

  // ── Addresses ───────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAddresses(
      String userId) async {
    final res = await _client
        .from('addresses')
        .select()
        .eq('user_id', userId)
        .eq('is_deleted', false)
        .order('is_default', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> addAddress(Map<String, dynamic> data) async {
    await _client.from('addresses').insert(data);
  }

  // ── Bookings ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getCustomerBookings(
      String customerId) async {
    final res = await _client
        .from('bookings')
        .select('''
          id, status, scheduled_at, final_amount, otp,
          service_names, total_services,
          services ( name ),
          addresses ( area, city )
        ''')
        .eq('customer_id', customerId)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<Map<String, dynamic>?> getBookingById(
      String id) async {
    final res = await _client
        .from('bookings')
        .select('''
          id, status, scheduled_at, final_amount, otp,
          service_names, total_services, total_duration,
          services ( name, duration_minutes ),
          addresses ( label, flat_no, building, area, city ),
          worker:users!worker_id ( full_name, phone )
        ''')
        .eq('id', id)
        .maybeSingle();
    return res;
  }

  static Future<Map<String, dynamic>> createBooking(
      Map<String, dynamic> data) async {
    final res = await _client
        .from('bookings')
        .insert(data)
        .select()
        .single();
    return res;
  }

  static Future<void> updateBookingStatus(
      String id, String status) async {
    await _client
        .from('bookings')
        .update({'status': status})
        .eq('id', id);
  }

  // ── Worker ──────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getPendingJobs() async {
    final res = await _client
        .from('bookings')
        .select('''
          id, status, final_amount, scheduled_at, worker_id,
          service_names, total_services,
          services ( name, duration_minutes ),
          addresses ( area, city ),
          customer:users!customer_id ( full_name, phone )
        ''')
        .eq('status', 'pending')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> acceptJob(
      String jobId, String workerId) async {
    await _client
        .from('bookings')
        .update({'worker_id': workerId, 'status': 'accepted'})
        .eq('id', jobId)
        .eq('status', 'pending');
  }

  static Future<void> updateWorkerAvailability(
      String userId, bool available) async {
    await _client
        .from('workers')
        .update({'is_available': available})
        .eq('user_id', userId);
  }

  // ── Admin ───────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAllBookings() async {
    final res = await _client
        .from('bookings')
        .select('''
          id, status, final_amount, scheduled_at, worker_id,
          services ( name ),
          addresses ( area, city ),
          customer:users!customer_id ( full_name ),
          worker:users!worker_id ( full_name )
        ''')
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  // ── Realtime ─────────────────────────────────────────────────
  static RealtimeChannel subscribeToBookings(
      void Function() onEvent) {
    return client
        .channel('bookings-changes')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          callback: (_) => onEvent(),
        )
        .subscribe();
  }
}