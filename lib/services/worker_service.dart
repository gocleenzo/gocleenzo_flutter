import 'package:supabase_flutter/supabase_flutter.dart';

/// All Supabase reads/writes the worker app needs.
///
/// IMPORTANT consistency notes (so this stays in sync with admin + customer):
///  - The worker NEVER changes booking status. The customer flips
///    accepted -> in_progress by entering the worker's OTP, and the admin
///    flips in_progress -> completed. The worker app is read-only on bookings.
///  - The only thing the worker writes is workers.is_available.
///  - `worker_id` on bookings == users.id == auth.uid(), which is also
///    workers.user_id. So the logged-in worker id is auth.currentUser.id.
class WorkerService {
  WorkerService._();
  static final WorkerService instance = WorkerService._();

  final SupabaseClient _client = Supabase.instance.client;
  SupabaseClient get client => _client;

  String? get workerId => _client.auth.currentUser?.id;

  /// workers row joined with the users row.
  Future<Map<String, dynamic>?> getWorkerProfile() async {
    final id = workerId;
    if (id == null) return null;
    return _client
        .from('workers')
        .select('*, users(*)')
        .eq('user_id', id)
        .maybeSingle();
  }

  /// The permanent OTP the worker reads out to the customer.
  Future<String?> getWorkerOtp() async {
    final id = workerId;
    if (id == null) return null;
    final row = await _client
        .from('workers')
        .select('worker_otp')
        .eq('user_id', id)
        .maybeSingle();
    return row?['worker_otp']?.toString();
  }

  /// The single job currently being worked (status = in_progress).
  Future<Map<String, dynamic>?> getActiveJob() async {
    final id = workerId;
    if (id == null) return null;
    return _client
        .from('bookings')
        .select(
            '*, services(name, base_price), addresses(*), users!customer_id(full_name, phone)')
        .eq('worker_id', id)
        .eq('status', 'in_progress')
        .maybeSingle();
  }

  /// Jobs assigned but not yet started (status = accepted).
  Future<List<Map<String, dynamic>>> getUpcomingJobs() async {
    final id = workerId;
    if (id == null) return [];
    final rows = await _client
        .from('bookings')
        .select(
            '*, services(name, base_price), addresses(*), users!customer_id(full_name, phone)')
        .eq('worker_id', id)
        .eq('status', 'accepted')
        .order('scheduled_at');
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Full detail for one booking.
  Future<Map<String, dynamic>?> getJobById(String bookingId) async {
    return _client
        .from('bookings')
        .select(
            '*, services(name, base_price, description), addresses(*), users!customer_id(full_name, phone)')
        .eq('id', bookingId)
        .maybeSingle();
  }

  /// Completed jobs, newest first — feeds the Earnings screen.
  Future<List<Map<String, dynamic>>> getCompletedJobs() async {
    final id = workerId;
    if (id == null) return [];
    final rows = await _client
        .from('bookings')
        .select('*, services(name)')
        .eq('worker_id', id)
        .eq('status', 'completed')
        .order('work_ended_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Everything that's finished (completed + cancelled) — the History screen.
  Future<List<Map<String, dynamic>>> getHistory() async {
    final id = workerId;
    if (id == null) return [];
    final rows = await _client
        .from('bookings')
        .select('*, services(name), addresses(*)')
        .eq('worker_id', id)
        .inFilter('status', ['completed', 'cancelled'])
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Toggle the worker's availability (the only booking-independent write).
  Future<void> setAvailability(bool value) async {
    final id = workerId;
    if (id == null) return;
    await _client.from('workers').upsert(
      {'user_id': id, 'is_available': value},
      onConflict: 'user_id',
    );
  }

  /// Realtime: fires [onChange] whenever a booking for this worker changes.
  /// This is what makes the dashboard flip to the live timer the instant the
  /// customer enters the OTP, and surfaces newly-assigned jobs automatically.
  RealtimeChannel subscribeToJobs(void Function() onChange) {
    final id = workerId;
    final channel = _client.channel('worker_jobs_$id');
    channel
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'worker_id',
            value: id,
          ),
          callback: (_) => onChange(),
        )
        .subscribe();
    return channel;
  }

  Future<void> signOut() => _client.auth.signOut();
}
