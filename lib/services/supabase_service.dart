import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SupabaseService {
  static final _client = Supabase.instance.client;
  static SupabaseClient get client => _client;

  // ── Auth ────────────────────────────────────────────────────
  static Future<void> sendOtp(String phone) async {
    final fullPhone = '+91$phone';
    print('===> Sending OTP to: $fullPhone');
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
    await _client.auth.signOut();
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }

  static User? get currentUser => _client.auth.currentUser;

  // ── Users ───────────────────────────────────────────────────
  // Uses maybeSingle() so a brand-new user (no row yet) returns null
  // instead of throwing. The login flow relies on null == "new user".
  static Future<Map<String, dynamic>?> getUserProfile(String userId) async {
    final res = await _client
        .from('users')
        .select()
        .eq('id', userId)
        .maybeSingle();
    return res;
  }

  static Future<void> updateUserProfile(String userId, Map<String, dynamic> data) async {
    await _client.from('users').update(data).eq('id', userId);
  }

  // Upsert (not insert): a row may already exist if an auth trigger created
  // one on signup. Upsert inserts a new row OR updates the existing one by id.
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

  static Future<Map<String, dynamic>?> getServiceById(String id) async {
    final res = await _client
        .from('services')
        .select()
        .eq('id', id)
        .maybeSingle();
    return res;
  }

  // ── Addresses ───────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getAddresses(String userId) async {
    final res = await _client
        .from('addresses')
        .select()
        .eq('user_id', userId)
        .order('is_default', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }

  static Future<void> addAddress(Map<String, dynamic> data) async {
    await _client.from('addresses').insert(data);
  }

  // ── Bookings ────────────────────────────────────────────────
  static Future<List<Map<String, dynamic>>> getCustomerBookings(String customerId) async {
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

  static Future<Map<String, dynamic>?> getBookingById(String id) async {
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

  static Future<Map<String, dynamic>> createBooking(Map<String, dynamic> data) async {
    final res = await _client
        .from('bookings')
        .insert(data)
        .select()
        .single();
    return res;
  }

  static Future<void> updateBookingStatus(String id, String status) async {
    await _client.from('bookings').update({'status': status}).eq('id', id);
  }

  // ── Worker ─────────────────────────────────────────────────
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

  static Future<void> acceptJob(String jobId, String workerId) async {
    await _client
        .from('bookings')
        .update({'worker_id': workerId, 'status': 'accepted'})
        .eq('id', jobId)
        .eq('status', 'pending');
  }

  static Future<void> updateWorkerAvailability(String userId, bool available) async {
    await _client
        .from('workers')
        .update({'is_available': available})
        .eq('user_id', userId);
  }

  // ── Admin ──────────────────────────────────────────────────
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

  // ── Realtime ───────────────────────────────────────────────
  static RealtimeChannel subscribeToBookings(void Function() onEvent) {
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