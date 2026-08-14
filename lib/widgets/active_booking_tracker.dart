import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/supabase_service.dart';
import '../screens/customer/booking_detail_screen.dart';

/// A persistent, Zomato/Swiggy-style "track your order" pill shown above
/// the bottom nav bar on every customer tab whenever the customer has an
/// active booking (assigned, OTP-verified, or in progress). Tapping it
/// opens that booking's BookingDetailScreen — which already contains the
/// OTP-entry step, the live running timer once work starts, "Mark Work as
/// Done", and the post-completion rating prompt, so this widget's only
/// job is surfacing that there IS something to track, from anywhere in
/// the app, without the customer having to dig through the Bookings tab.
///
/// If several bookings are active at once (rare, but possible), the one
/// shown is whichever is furthest along: in_progress > otp_verified >
/// accepted > pending — i.e. whichever the customer most likely wants to
/// act on right now.
class ActiveBookingTracker extends StatefulWidget {
  const ActiveBookingTracker({super.key});

  @override
  State<ActiveBookingTracker> createState() => _ActiveBookingTrackerState();
}

class _ActiveBookingTrackerState extends State<ActiveBookingTracker> {
  final _supabase = Supabase.instance.client;

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _purple = Color(0xFF7C3AED);
  static const _amber  = Color(0xFFD97706);

  Map<String, dynamic>? _booking;
  RealtimeChannel? _channel;
  Timer? _tickTimer;
  String? _userId;

  // Same priority order used to pick which booking to surface if more
  // than one is active at once.
  static const _statusPriority = {
    'in_progress': 0,
    'otp_verified': 1,
    'accepted': 2,
    'pending': 3,
  };

  @override
  void initState() {
    super.initState();
    _init();
    // Only actually needed while a booking is in_progress (to tick the
    // live timer), but harmless to run generally — matches the same
    // lightweight 1s Timer pattern already used in booking_detail_screen.
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _booking?['status'] == 'in_progress') setState(() {});
    });
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _tickTimer?.cancel();
    super.dispose();
  }

  Future<void> _init() async {
    _userId = await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (_userId == null) return;
    await _load();
    _subscribeRealtime();
  }

  Future<void> _load() async {
    final id = _userId;
    if (id == null) return;
    try {
      final rows = await _supabase
          .from('bookings')
          .select('id, status, work_started_at, service_duration_minutes, '
              'booking_duration_minutes, extra_time_mins, services(name), '
              'worker:users!worker_id(full_name)')
          .eq('customer_id', id)
          .inFilter('status', ['pending', 'accepted', 'otp_verified', 'in_progress'])
          .order('scheduled_at', ascending: false);

      final list = (rows as List).cast<Map<String, dynamic>>();
      if (list.isEmpty) {
        if (mounted) setState(() => _booking = null);
        return;
      }
      list.sort((a, b) =>
          (_statusPriority[a['status']] ?? 9)
              .compareTo(_statusPriority[b['status']] ?? 9));
      if (mounted) setState(() => _booking = list.first);
    } catch (e) {
      debugPrint('ActiveBookingTracker load error: $e');
    }
  }

  void _subscribeRealtime() {
    final id = _userId;
    if (id == null) return;
    _channel = _supabase
        .channel('active_tracker_$id')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'customer_id',
              value: id),
          callback: (_) => _load(),
        )
        .subscribe();
  }

  ({Color color, String icon, String label}) _statusMeta(String status) {
    switch (status) {
      case 'in_progress':
        return (color: _cyan, icon: '⚡', label: 'Work in progress');
      case 'otp_verified':
        return (color: _purple, icon: '🔓', label: 'Starting shortly');
      case 'accepted':
        return (color: const Color(0xFF2563EB), icon: '👷', label: 'Pro assigned');
      default:
        return (color: _amber, icon: '⏳', label: 'Finding your pro');
    }
  }

  String? _elapsedText() {
    final b = _booking;
    if (b == null || b['status'] != 'in_progress') return null;
    final startedRaw = b['work_started_at'] as String?;
    if (startedRaw == null) return null;
    final started = DateTime.tryParse(startedRaw)?.toLocal();
    if (started == null) return null;
    final elapsed = DateTime.now().difference(started);
    final h = elapsed.inHours;
    final m = elapsed.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '${h.toString().padLeft(2, '0')}:$m:$s' : '$m:$s';
  }

  /// Customer-facing worker display uses first name only — matches the
  /// same convention as booking_detail_screen.dart's "Pro Assigned" card.
  String _firstName(String full) {
    final trimmed = full.trim();
    if (trimmed.isEmpty) return trimmed;
    return trimmed.split(RegExp(r'\s+')).first;
  }

  @override
  Widget build(BuildContext context) {
    final b = _booking;
    if (b == null) return const SizedBox.shrink();

    final meta = _statusMeta(b['status'] as String? ?? 'pending');
    final serviceName = (b['services']?['name'] as String?) ?? 'Service';
    final workerNameFull  = b['worker']?['full_name'] as String?;
    final workerName = workerNameFull != null ? _firstName(workerNameFull) : null;
    final elapsed     = _elapsedText();

    return GestureDetector(
      onTap: () {
        Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => BookingDetailScreen(bookingId: b['id'] as String),
        ));
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: [meta.color, meta.color.withValues(alpha: 0.82)]),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [BoxShadow(
              color: meta.color.withValues(alpha: 0.35),
              blurRadius: 16, offset: const Offset(0, 6))],
        ),
        child: Row(children: [
          Container(
            width: 38, height: 38,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12)),
            child: Center(child: Text(meta.icon, style: const TextStyle(fontSize: 18))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(meta.label,
                style: const TextStyle(color: Colors.white,
                    fontSize: 13, fontWeight: FontWeight.w900)),
            const SizedBox(height: 1),
            Text(
              workerName != null ? '$serviceName · $workerName' : serviceName,
              maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5)),
          ])),
          if (elapsed != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(10)),
              child: Text(elapsed,
                  style: const TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w900,
                      fontFeatures: [FontFeature.tabularFigures()])),
            ),
            const SizedBox(width: 8),
          ],
          const Icon(Icons.chevron_right_rounded, color: Colors.white, size: 22),
        ]),
      ),
    );
  }
}