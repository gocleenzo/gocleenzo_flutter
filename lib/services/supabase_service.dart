import 'package:flutter/foundation.dart';
import 'package:firebase_auth/firebase_auth.dart' as fb;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'notification_service.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;
  static SupabaseClient get client => _client;

<<<<<<< HEAD
  // Cached app user id (set after Firebase login via edge function)
  static String? _cachedUserId;

  /// Call this right after a successful Firebase login + edge function
  /// response, passing the `user_id` returned from the `firebase-auth`
  /// edge function. Persists it so it survives app restarts.
  static Future<void> setCachedUserId(String userId) async {
    _cachedUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('app_user_id', userId);
  }

  static Future<String?> loadCachedUserId() async {
    if (_cachedUserId != null) return _cachedUserId;
    final prefs = await SharedPreferences.getInstance();
    _cachedUserId = prefs.getString('app_user_id');
    return _cachedUserId;
  }

  /// Unified current user id — works whether the session came from
  /// Supabase auth (legacy) or Firebase auth (current flow).
  static String? get currentUserId {
    final supaUser = _client.auth.currentUser;
    if (supaUser != null) return supaUser.id;
    return _cachedUserId;
=======
  /// Normalizes ANY user input to +91XXXXXXXXXX (E.164).
  /// Strips spaces, dashes, a leading 0, or a pasted +91 so the number
  /// sent to Twilio is always clean. This is the #1 cause of "OTP not
  /// sending", and it must be identical in sendOtp and verifyOtp.
  static String _e164(String raw) {
    var d = raw.replaceAll(RegExp(r'\D'), ''); // digits only
    if (d.startsWith('0')) d = d.substring(1); // drop a leading 0
    if (d.length > 10) d = d.substring(d.length - 10); // keep last 10
    return '+91$d';
>>>>>>> 7b7a43646a02ef1a0f3ff5b2e13b499a96512c0f
  }

  // ── Auth ────────────────────────────────────────────────────
  static Future<void> sendOtp(String phone) async {
    final fullPhone = _e164(phone);
    debugPrint('===> Sending OTP to: $fullPhone');
    await _client.auth.signInWithOtp(
      phone: fullPhone,
      shouldCreateUser: true,
    );
  }

  static Future<AuthResponse> verifyOtp(String phone, String token) async {
    return await _client.auth.verifyOTP(
      phone: _e164(phone),
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