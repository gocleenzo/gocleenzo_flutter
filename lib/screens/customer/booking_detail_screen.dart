import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/supabase_service.dart';
import 'review_popup.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final bool   isNew;

  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.isNew = false,
  });

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen>
    with SingleTickerProviderStateMixin {

  final _supabase = Supabase.instance.client;

  // ── Colors ──────────────────────────────────────────────────
  static const _cyan    = Color(0xFF06B6D4);
  static const _cyanDk  = Color(0xFF0891B2);
  static const _cyanBg  = Color(0xFFECFEFF);
  static const _cyanBg2 = Color(0xFFCFFAFE);
  static const _ink     = Color(0xFF0F172A);
  static const _muted   = Color(0xFF64748B);
  static const _faint   = Color(0xFF94A3B8);
  static const _border  = Color(0xFFE2E8F0);
  static const _bg      = Color(0xFFF8FAFC);
  static const _green   = Color(0xFF10B981);
  static const _greenDk = Color(0xFF059669);
  static const _line    = Color(0xFFF1F5F9);
  static const _purple  = Color(0xFF7C3AED);
  static const _purpleBg = Color(0xFFEDE9FE);
  static const _purpleBg2 = Color(0xFFF5F3FF);
  static const _purpleBorder = Color(0xFFDDD6FE);

  // ── Contact number shown in the worker row ─────────────────────
  // ⚠️ PLACEHOLDER — replace with the real helpline number before
  // shipping. Kept as a single constant so it's the one place to edit,
  // and so the app-wide "which number does the customer see" question
  // always has exactly one source of truth.
  static const String _helplineNumber = '9702728298';

  Map<String, dynamic>? _booking;
  bool _loading = true;

  String? _workerOtp;

  String? _customerPhone;
  String? _customerEmail;

  final _otpInputCtrl = TextEditingController();
  String? _otpError;
  bool _verifying = false;

  bool _markingDone = false;

  bool _addingExtraTime = false;
  late Razorpay _extraTimeRazorpay;
  static const _razorpayKey = 'rzp_live_TJIl6FAZg8I1ru';
  // Extra time offer — loaded from app_settings (editable from the
  // admin panel). These defaults are only used if that row can't be
  // read for some reason.
  int _xtAddMins = 20;
  int _xtPrice   = 80;
  // Locked in when a payment STARTS, so the amount written to the
  // booking always matches what the customer actually paid, even if
  // the admin changes the price while the payment screen is open.
  int? _xtPendingMins;
  int? _xtPendingPrice;

  // ── Reschedule feature ───────────────────────────────────────
  // NEW: customer-initiated reschedule. Backend does all the real
  // validation (eligibility, 1-hour cutoff, fee logic) via the
  // reschedule_booking_check / reschedule_booking_apply RPC functions
  // — this screen just drives the picker + payment and displays
  // whatever the backend says. Never trust a locally-computed fee;
  // always show what check() returns.
  bool _rescheduling = false;
  DateTime? _pendingRescheduleAt;
  late Razorpay _rescheduleRazorpay;

  // ── Live tracking ────────────────────────────────────────────
  // Polls get_booking_live_tracking() every 15s. The database itself
  // refuses to return a location before 30 min ahead of the slot, or
  // once the booking is past 'accepted' — this screen just displays
  // whatever it's given.
  Timer? _trackingTimer;
  GoogleMapController? _trackingMapCtrl;
  LatLng? _proLatLng;
  DateTime? _proUpdatedAt;
  String? _trackingReason; // null until the first fetch completes
  bool _trackingFetching = false;

  // ── API base URL for the admin backend's payment routes ─────────
  // Same host the app already calls for order creation elsewhere
  // (booking flow / recurring packages). Centralized here as a
  // constant so it's obvious where to change it if that host moves.
  static const _paymentsApiBase = 'https://gocleenzo-admin.vercel.app';

  bool _reviewPromptShown = false;

  late AnimationController _successCtrl;
  late Animation<double>   _successScale;

  RealtimeChannel? _channel;
  Timer? _tickTimer;
  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = CurvedAnimation(
        parent: _successCtrl, curve: Curves.elasticOut);

    _extraTimeRazorpay = Razorpay();
    _extraTimeRazorpay.on(
        Razorpay.EVENT_PAYMENT_SUCCESS, _onExtraTimePaymentSuccess);
    _extraTimeRazorpay.on(
        Razorpay.EVENT_PAYMENT_ERROR, _onExtraTimePaymentError);
    _extraTimeRazorpay.on(
        Razorpay.EVENT_EXTERNAL_WALLET, _onExtraTimeExternalWallet);

    _rescheduleRazorpay = Razorpay();
    _rescheduleRazorpay.on(
        Razorpay.EVENT_PAYMENT_SUCCESS, _onReschedulePaymentSuccess);
    _rescheduleRazorpay.on(
        Razorpay.EVENT_PAYMENT_ERROR, _onReschedulePaymentError);
    _rescheduleRazorpay.on(
        Razorpay.EVENT_EXTERNAL_WALLET, _onRescheduleExternalWallet);

    _loadBooking();
    _loadExtraTimeSettings();
    _subscribeRealtime();

    // 30-second tick — also what keeps the phone-number visibility gate
    // (30 minutes before scheduled time) re-evaluating live as the
    // clock crosses that threshold, without needing a page refresh.
    // Also keeps the reschedule 1-hour cutoff re-evaluating live.
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _status == 'in_progress') setState(() {});
    });

    _trackingTimer = Timer.periodic(
        const Duration(seconds: 15), (_) => _refreshTracking());

    if (widget.isNew) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _successCtrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _successCtrl.dispose();
    _extraTimeRazorpay.clear();
    _rescheduleRazorpay.clear();
    _channel?.unsubscribe();
    _countdownTimer?.cancel();
    _tickTimer?.cancel();
    _trackingTimer?.cancel();
    _trackingMapCtrl?.dispose();
    _otpInputCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadBooking() async {
    try {
      final data = await _supabase
          .from('bookings')
          .select('''
            *,
            services(name, duration_minutes, category),
            addresses(label, flat_no, building, area, city, pincode, latitude, longitude),
            worker:users!worker_id(full_name, phone),
            customer:users!customer_id(phone, email),
            booking_items(quantity, unit_price, total_price, service_name, services(name, duration_minutes, category))
          ''')
          .eq('id', widget.bookingId)
          .single();
      if (mounted) {
        setState(() {
          _booking = data;
          _loading = false;
          final customer = data['customer'] as Map<String, dynamic>?;
          _customerPhone = customer?['phone'] as String?;
          _customerEmail = customer?['email'] as String?;
        });
      }
      await _loadWorkerOtp();
      _refreshTracking();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptReview());
      }
    } catch (e) {
      debugPrint('booking detail load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadExtraTimeSettings() async {
    try {
      final data = await _supabase
          .from('app_settings')
          .select('extra_time_price, extra_time_minutes')
          .eq('id', 'global')
          .maybeSingle();
      if (data != null && mounted) {
        setState(() {
          _xtPrice   = (data['extra_time_price'] as num?)?.toInt() ?? _xtPrice;
          _xtAddMins = (data['extra_time_minutes'] as num?)?.toInt() ?? _xtAddMins;
        });
      }
    } catch (e) {
      debugPrint('extra time settings load error: $e');
    }
  }

  /// Price the customer actually paid for extra time on THIS booking
  /// (stored on the booking), falling back to the current setting.
  int get _bookingExtraTimePrice =>
      (_booking?['extra_time_price'] as num?)?.toInt() ?? _xtPrice;

  List<Map<String, dynamic>> get _bookedServices {
    final items = (_booking?['booking_items'] as List?) ?? const [];
    if (items.isNotEmpty) {
      return items.map((raw) {
        final item = raw as Map<String, dynamic>;
        final name = (item['service_name'] as String?) ??
            (item['services']?['name'] as String?) ?? 'Service';
        final qty = (item['quantity'] as num?)?.toInt() ?? 1;
        final unit = (item['unit_price'] as num?)?.toInt() ?? 0;
        return {'name': name, 'qty': qty, 'unit_price': unit};
      }).toList();
    }
    final svc = _booking?['services'] as Map<String, dynamic>?;
    final fallback = svc?['name'] as String? ?? 'Service';
    return [{'name': fallback, 'qty': 1, 'unit_price': (_booking?['base_price'] as num?)?.toInt() ?? 0}];
  }

  String get _bookedServicesLabel =>
      _bookedServices.map((s) {
        final qty = s['qty'] as int;
        return qty > 1 ? '${s['name']} ×$qty' : s['name'] as String;
      }).join(', ');

  /// Customer-facing display of the worker's name uses FIRST NAME ONLY —
  /// full names aren't shown to customers. Used everywhere this screen
  /// surfaces the assigned worker's name (the status card's worker row).
  /// Avatar initials still use the full name (so two workers sharing a
  /// first name still get distinct initials) — only the visible TEXT
  /// label is trimmed to first name.
  String _firstName(String full) {
    final trimmed = full.trim();
    if (trimmed.isEmpty) return 'Professional';
    return trimmed.split(RegExp(r'\s+')).first;
  }

  Future<void> _loadWorkerOtp() async {
    final workerId = _booking?['worker_id'] as String?;
    if (workerId == null) {
      if (mounted) setState(() => _workerOtp = null);
      return;
    }
    try {
      final data = await _supabase
          .from('workers')
          .select('worker_otp')
          .eq('user_id', workerId)
          .maybeSingle();
      if (mounted) {
        setState(() => _workerOtp = data?['worker_otp']?.toString());
      }
    } catch (e) {
      debugPrint('worker otp load error: $e');
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('booking:${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'id',
              value: widget.bookingId),
          callback: (_) => _loadBooking(),
        )
        .subscribe();
  }

  String get _status => _booking?['status'] as String? ?? 'pending';
  int    get _extraTimeMins => (_booking?['extra_time_mins'] as num?)?.toInt() ?? 0;
  String? get _extraTimePaymentStatus =>
      _booking?['extra_time_payment_status'] as String?;
  String get _paymentStatus => _booking?['payment_status'] as String? ?? 'cod';
  bool get _isInstant => (_booking?['booking_type'] as String?) == 'instant';
  bool get _hasWorker => _booking?['worker_id'] != null;

  DateTime? get _scheduledAt {
    final raw = _booking?['scheduled_at'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  bool get _otpWindowOpen {
    if (_isInstant) return true;
    final sched = _scheduledAt;
    if (sched == null) return false;
    final opensAt = sched.subtract(const Duration(minutes: 15));
    return !DateTime.now().isBefore(opensAt);
  }

  Duration? get _timeUntilOtpWindow {
    if (_isInstant) return null;
    final sched = _scheduledAt;
    if (sched == null) return null;
    final opensAt = sched.subtract(const Duration(minutes: 15));
    final diff = opensAt.difference(DateTime.now());
    return diff.isNegative ? null : diff;
  }

  /// Contact number visibility gate: true once we're within 30 minutes
  /// of the scheduled time (or past it) — i.e. the SAME 30-minute rule
  /// requested, independent of the 15-minute OTP window above (that's a
  /// separate, narrower gate for entering the worker's OTP). No
  /// scheduled_at at all (shouldn't normally happen) fails CLOSED —
  /// the number stays hidden rather than guessing it's fine to show.
  bool get _isPastContactWindow {
    final sched = _scheduledAt;
    if (sched == null) return false;
    final opensAt = sched.subtract(const Duration(minutes: 30));
    return !DateTime.now().isBefore(opensAt);
  }

  /// Combines both required conditions: a worker must actually be
  /// assigned AND we must be within the 30-minute contact window.
  /// Nothing about which number is shown lives in this getter — that's
  /// handled entirely by _helplineNumber below, so this purely answers
  /// "should ANY number be visible right now".
  bool get _showContactNumber => _hasWorker && _isPastContactWindow;

  /// Reschedule eligibility, mirrored client-side purely so the button
  /// can hide/disable itself without a round trip. The backend
  /// (reschedule_booking_check / _apply) re-validates all of this
  /// independently and is the actual source of truth — this getter is
  /// only a UI convenience and must never be trusted for anything that
  /// changes data.
  bool get _canReschedule {
    if (!_rescheduleEligibleStatus) return false;
    final left = _rescheduleTimeLeft;
    return left != null && left > Duration.zero;
  }

  /// Whether the "Modify your booking" card should appear AT ALL —
  /// open or closed. Only for bookings that haven't started yet;
  /// in_progress / completed / cancelled bookings never show it.
  bool get _rescheduleEligibleStatus =>
      ['pending', 'accepted', 'otp_verified'].contains(_status) &&
      _scheduledAt != null;

  /// Time remaining until the 1-hour-before cutoff. Negative once
  /// the cutoff has passed. Re-evaluated by the 30-second tick timer,
  /// so the card flips to "closed" on its own while the screen is open.
  Duration? get _rescheduleTimeLeft {
    final sched = _scheduledAt;
    if (sched == null) return null;
    final cutoff = sched.subtract(const Duration(hours: 1));
    return cutoff.difference(DateTime.now());
  }

  String _formatTimeLeft(Duration d) {
    if (d.inMinutes < 1) return 'less than a minute';
    final days  = d.inDays;
    final hours = d.inHours % 24;
    final mins  = d.inMinutes % 60;
    if (days > 0)  return hours > 0 ? '${days}d ${hours}h' : '${days}d';
    if (d.inHours > 0) return mins > 0 ? '${d.inHours}h ${mins}m' : '${d.inHours}h';
    return '${d.inMinutes}m';
  }

  Future<void> _callHelpline() async {
    HapticFeedback.selectionClick();
    final uri = Uri(scheme: 'tel', path: _helplineNumber);
    try {
      await launchUrl(uri);
    } catch (e) {
      debugPrint('launch tel: error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not open dialer. Number: $_helplineNumber'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    }
  }

  DateTime? get _workStartedAtLocal {
    final raw = _booking?['work_started_at'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  int get _totalServiceDurationMins {
    final raw = (_booking?['service_duration_minutes'] as num?)?.toInt();
    final base = raw ?? (_booking?['booking_duration_minutes'] as num?)?.toInt() ?? 60;
    return base + _extraTimeMins;
  }

  Duration? get _remainingServiceTime {
    final started = _workStartedAtLocal;
    if (started == null) return null;
    final endsAt = started.add(Duration(minutes: _totalServiceDurationMins));
    return endsAt.difference(DateTime.now());
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'pending':      return const Color(0xFFD97706);
      case 'accepted':     return const Color(0xFF2563EB);
      case 'otp_verified': return _purple;
      case 'in_progress':  return _cyan;
      case 'completed':    return _green;
      case 'cancelled':    return const Color(0xFFDC2626);
      default:             return _muted;
    }
  }

  Color _statusBg(String s) {
    switch (s) {
      case 'pending':      return const Color(0xFFFEF3C7);
      case 'accepted':     return const Color(0xFFDBEAFE);
      case 'otp_verified': return _purpleBg;
      case 'in_progress':  return _cyanBg;
      case 'completed':    return const Color(0xFFD1FAE5);
      case 'cancelled':    return const Color(0xFFFEE2E2);
      default:             return _bg;
    }
  }

  String _statusLabel(String s) {
    switch (s) {
      case 'pending':      return 'Booking Placed';
      case 'accepted':     return 'Pro Assigned';
      case 'otp_verified': return 'OTP Verified';
      case 'in_progress':  return 'Work In Progress';
      case 'completed':    return 'Completed';
      case 'cancelled':    return 'Cancelled';
      default:             return s;
    }
  }

  String _statusIcon(String s) {
    switch (s) {
      case 'pending':      return '⏳';
      case 'accepted':     return '👷';
      case 'otp_verified': return '🔓';
      case 'in_progress':  return '⚡';
      case 'completed':    return '✅';
      case 'cancelled':    return '❌';
      default:             return '📋';
    }
  }

  String _statusDescription(String s) {
    switch (s) {
      case 'pending':
        return _isInstant
            ? 'We\'re finding the nearest professional for you.'
            : 'Your booking is confirmed. A professional will be assigned soon.';
      case 'accepted':
        return 'A verified professional has been assigned to your booking.';
      case 'otp_verified':
        return 'OTP verified. The professional is ready to start work.';
      case 'in_progress':
        return 'Our professional is currently working at your location.';
      case 'completed':
        return 'Service completed! We hope you loved it. Please rate your experience.';
      case 'cancelled':
        return 'This booking has been cancelled.';
      default:
        return '';
    }
  }

  Future<void> _verifyOtp() async {
    final entered = _otpInputCtrl.text.trim();

    if (entered.length != 4) {
      setState(() => _otpError = 'Enter the 4-digit OTP');
      return;
    }
    if (_workerOtp == null || _workerOtp!.isEmpty) {
      setState(() => _otpError = 'Could not verify right now. Please contact support.');
      return;
    }
    if (entered != _workerOtp) {
      HapticFeedback.mediumImpact();
      setState(() => _otpError = 'Incorrect OTP. Please try again.');
      return;
    }

    setState(() { _verifying = true; _otpError = null; });
    try {
      await _supabase.from('bookings').update({
        'status':           'in_progress',
        'work_started_at':  DateTime.now().toUtc().toIso8601String(),
      }).eq('id', widget.bookingId);

      HapticFeedback.heavyImpact();
      await _loadBooking();
    } catch (e) {
      debugPrint('OTP verify update error: $e');
      if (mounted) setState(() => _otpError = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _verifying = false);
    }
  }

  Future<void> _markWorkDone() async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(
                  color: Color(0xFFECFDF5), shape: BoxShape.circle),
              child: const Center(
                  child: Text('✅', style: TextStyle(fontSize: 32)))),
            const SizedBox(height: 18),
            const Text('Mark Work as Done?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 10),
            const Text(
              'Confirm only once the professional has finished '
              'the service at your location. This will complete '
              'the booking and free up the professional for other jobs.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border)),
                    child: const Text('Not Yet',
                        style: TextStyle(color: _muted,
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_green, _greenDk]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                          color: _green.withValues(alpha: 0.35),
                          blurRadius: 12, offset: const Offset(0, 4))]),
                    child: const Text('Yes, Done',
                        style: TextStyle(color: Colors.white,
                            fontSize: 14, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );

    if (confirmed != true) return;

    setState(() => _markingDone = true);

    final startedAtRaw = _booking?['work_started_at'] as String?;
    final startedAt = startedAtRaw != null
        ? DateTime.tryParse(startedAtRaw)
        : null;
    final now = DateTime.now().toUtc();
    final durationSeconds = startedAt != null
        ? now.difference(startedAt).inSeconds
        : 0;

    try {
      await _supabase.from('bookings').update({
        'status':                'completed',
        'work_ended_at':         now.toIso8601String(),
        'work_duration_seconds': durationSeconds,
      }).eq('id', widget.bookingId);

      final workerId = _booking?['worker_id'] as String?;
      if (workerId != null) {
        try {
          final workerData = await _supabase
              .from('workers')
              .select('total_jobs_completed, total_work_seconds')
              .eq('user_id', workerId)
              .maybeSingle();
          final prevJobs = (workerData?['total_jobs_completed'] as num?)?.toInt() ?? 0;
          final prevSecs = (workerData?['total_work_seconds'] as num?)?.toInt() ?? 0;

          await _supabase.from('workers').update({
            'is_available':         true,
            'total_jobs_completed': prevJobs + 1,
            'total_work_seconds':   prevSecs + durationSeconds,
          }).eq('user_id', workerId);
        } catch (e) {
          debugPrint('worker free-up error: $e');
        }
      }

      HapticFeedback.heavyImpact();
      await _loadBooking();
    } catch (e) {
      debugPrint('mark work done error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('Could not mark as done. Please try again.'),
          backgroundColor: const Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ));
      }
    } finally {
      if (mounted) setState(() => _markingDone = false);
    }
  }

  Future<void> _maybePromptReview() async {
    if (_status != 'completed' || _reviewPromptShown) return;
    _reviewPromptShown = true;

    try {
      final existing = await _supabase
          .from('reviews')
          .select('id')
          .eq('booking_id', widget.bookingId)
          .maybeSingle();
      if (existing != null) return;
    } catch (e) {
      debugPrint('review check error: $e');
      return;
    }

    if (!mounted) return;
    await showReviewPopup(
      context,
      bookingId: widget.bookingId,
      workerId: _booking?['worker_id'] as String?,
      serviceId: _booking?['service_id'] as String?,
      serviceName: _bookedServicesLabel,
    );
  }

  // ── Reschedule feature ───────────────────────────────────────
  // Same fixed slot grid as the new-booking flow (booking_flow_screen.dart),
  // kept identical so a slot shown as open here is open there too.
  static const List<String> _rescheduleTimeSlots = [
    '07:00 AM','07:30 AM',
    '08:00 AM','08:30 AM',
    '09:00 AM','09:30 AM',
    '10:00 AM','10:30 AM',
    '11:00 AM','11:30 AM',
    '12:00 PM','12:30 PM',
    '01:00 PM','01:30 PM',
    '02:00 PM','02:30 PM',
    '03:00 PM','03:30 PM',
    '04:00 PM','04:30 PM',
    '05:00 PM','05:30 PM',
    '06:00 PM','06:30 PM',
    '07:00 PM',
  ];

  /// Opens the real slot-availability picker — NOT a free date/time
  /// picker. Reuses the exact same admin_get_area_slot_grid() RPC the
  /// new-booking flow (booking_flow_screen.dart) calls, against this
  /// booking's own address pincode and duration, so a slot shown as
  /// open here is guaranteed to be open there too (one shared source
  /// of truth, same as the schedule-booking fix already applied there).
  Future<DateTime?> _showRescheduleSlotSheet() async {
    final addr = _booking?['addresses'] as Map<String, dynamic>?;
    final pincode = (addr?['pincode'] as String?)?.trim() ?? '';
    final durationMins =
        (_booking?['booking_duration_minutes'] as num?)?.toInt() ?? 60;

    return showModalBottomSheet<DateTime>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _RescheduleSlotSheet(
        supabase: _supabase,
        pincode: pincode,
        durationMins: durationMins,
        timeSlots: _rescheduleTimeSlots,
      ),
    );
  }

  Future<void> _startReschedule() async {
    final newDateTime = await _showRescheduleSlotSheet();
    if (newDateTime == null || !mounted) return;

    setState(() => _rescheduling = true);

    try {
      final result = await _supabase.rpc('reschedule_booking_check', params: {
        'p_booking_id': widget.bookingId,
        'p_new_scheduled_at': newDateTime.toUtc().toIso8601String(),
      });

      final row = (result is List && result.isNotEmpty)
          ? result.first as Map<String, dynamic>
          : null;

      if (row == null || row['allowed'] != true) {
        final reason = row?['reason'] as String? ?? 'unknown_error';
        _showRescheduleSnack(_rescheduleReasonText(reason), isError: true);
        if (mounted) setState(() => _rescheduling = false);
        return;
      }

      final feeRequired = row['fee_required'] == true;
      final feeAmount = (row['fee_amount'] as num?)?.toInt() ?? 0;

      if (!mounted) return;

      final confirmed =
          await _confirmRescheduleDialog(newDateTime, feeRequired, feeAmount);
      if (confirmed != true) {
        if (mounted) setState(() => _rescheduling = false);
        return;
      }

      if (!feeRequired) {
        await _applyReschedule(newDateTime, paymentId: null);
        return;
      }

      _pendingRescheduleAt = newDateTime;
      await _openRescheduleFeePayment(feeAmount);
    } catch (e) {
      debugPrint('reschedule check error: $e');
      _showRescheduleSnack(
          'Something went wrong. Please try again.', isError: true);
      if (mounted) setState(() => _rescheduling = false);
    }
  }

  String _rescheduleReasonText(String reason) {
    switch (reason) {
      case 'not_eligible_status':
        return 'This booking can no longer be rescheduled.';
      case 'past_cutoff':
        return 'Too late to reschedule — it must be done at least 1 hour before the scheduled time.';
      case 'new_time_in_past':
        return 'Please pick a future date and time.';
      case 'booking_not_found':
        return 'Booking not found.';
      case 'payment_required':
        return 'Payment is required for this reschedule.';
      default:
        return 'Could not reschedule right now. Please try again.';
    }
  }

  Future<bool?> _confirmRescheduleDialog(
      DateTime newTime, bool feeRequired, int feeAmount) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr = '${newTime.day} ${months[newTime.month - 1]} ${newTime.year}';
    final h = newTime.hour > 12 ? newTime.hour - 12 : (newTime.hour == 0 ? 12 : newTime.hour);
    final m = newTime.minute.toString().padLeft(2, '0');
    final ampm = newTime.hour >= 12 ? 'PM' : 'AM';
    final timeStr = '$h:$m $ampm';

    return showDialog<bool>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(color: _cyanBg, shape: BoxShape.circle),
              child: const Center(
                  child: Text('🗓️', style: TextStyle(fontSize: 32)))),
            const SizedBox(height: 18),
            const Text('Reschedule Booking?',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 10),
            Text('New time:\n$dateStr, $timeStr',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
            if (feeRequired) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFBEB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFDE68A))),
                child: Text(
                    'A reschedule fee of ₹$feeAmount applies (this is not your first reschedule on this booking).',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Color(0xFF92400E), fontSize: 12, height: 1.4))),
            ] else ...[
              const SizedBox(height: 8),
              const Text('Your first reschedule on this booking is free.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _greenDk, fontSize: 12, fontWeight: FontWeight.w700)),
            ],
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, false),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: _bg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _border)),
                    child: const Text('Cancel',
                        style: TextStyle(color: _muted,
                            fontSize: 14, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx, true),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(
                            color: _cyan.withValues(alpha: 0.35),
                            blurRadius: 12, offset: const Offset(0, 4))]),
                    child: Text(
                        feeRequired ? 'Pay ₹$feeAmount & Confirm' : 'Confirm',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 14, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  Future<void> _openRescheduleFeePayment(int feeAmount) async {
    String orderId;
    try {
      final res = await http.post(
        Uri.parse('$_paymentsApiBase/api/payments/order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount':   feeAmount * 100, // paise
          'currency': 'INR',
          // Razorpay caps `receipt` at 40 characters — same constraint
          // handled the same way as the extra-time payment above.
          'receipt':  'rs_${widget.bookingId.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch % 1000000}',
          'notes': {
            'type':       'reschedule_fee',
            'booking_id': widget.bookingId,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('Order creation failed: ${res.statusCode} ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final id = data['order_id'] as String?;
      if (id == null) throw Exception('No order_id in response: ${res.body}');
      orderId = id;
    } catch (e) {
      debugPrint('Reschedule fee order creation error: $e');
      if (mounted) setState(() => _rescheduling = false);
      _showRescheduleSnack(
          'Could not start payment. Please try again.', isError: true);
      return;
    }

    final options = {
      'key':         _razorpayKey,
      'order_id':    orderId,
      'amount':      feeAmount * 100,
      'name':        'Cleenzo',
      'description': 'Reschedule Fee',
      'prefill':     {'contact': _customerPhone ?? '', 'email': _customerEmail ?? ''},
      'notes':       {'booking_id': widget.bookingId, 'type': 'reschedule_fee'},
      'theme':       {'color': '#06B6D4'},
      'method': {
        'upi': true, 'netbanking': true,
        'card': true, 'wallet': true,
        'emi': false, 'cardless_emi': false, 'paylater': false,
      },
    };

    try {
      _rescheduleRazorpay.open(options);
    } catch (e) {
      debugPrint('Reschedule Razorpay open error: $e');
      if (mounted) setState(() => _rescheduling = false);
      _showRescheduleSnack(
          'Could not open payment. Please try again.', isError: true);
    }
  }

  Future<void> _onReschedulePaymentSuccess(
      PaymentSuccessResponse response) async {
    final newTime = _pendingRescheduleAt;
    if (newTime == null) {
      if (mounted) setState(() => _rescheduling = false);
      return;
    }
    await _applyReschedule(newTime, paymentId: response.paymentId);
  }

  void _onReschedulePaymentError(PaymentFailureResponse response) {
    _pendingRescheduleAt = null;
    if (mounted) setState(() => _rescheduling = false);
    _showRescheduleSnack(
        'Payment failed: ${response.message ?? "Please try again"}',
        isError: true);
  }

  void _onRescheduleExternalWallet(ExternalWalletResponse response) {
    if (mounted) setState(() => _rescheduling = false);
    _showRescheduleSnack('External wallet: ${response.walletName}');
  }

  Future<void> _applyReschedule(DateTime newTime, {String? paymentId}) async {
    try {
      final result = await _supabase.rpc('reschedule_booking_apply', params: {
        'p_booking_id': widget.bookingId,
        'p_new_scheduled_at': newTime.toUtc().toIso8601String(),
        'p_payment_id': paymentId,
      });

      final row = (result is List && result.isNotEmpty)
          ? result.first as Map<String, dynamic>
          : null;

      if (row != null && row['success'] == true) {
        _pendingRescheduleAt = null;
        HapticFeedback.heavyImpact();
        await _loadBooking();
        _showRescheduleSnack(
            '✅ Booking rescheduled. We\'ll assign a professional for the new time.');
      } else {
        final reason = row?['reason'] as String? ?? 'unknown_error';
        _showRescheduleSnack(_rescheduleReasonText(reason), isError: true);
      }
    } catch (e) {
      debugPrint('reschedule apply error: $e');
      // Note: if a fee was already paid but this call fails (e.g. lost
      // network right here), the money isn't silently lost — it's tied
      // to a real Razorpay order/payment with notes identifying the
      // booking, so support can look it up and apply the reschedule
      // manually. Still worth surfacing the payment ID to the customer.
      _showRescheduleSnack(
          paymentId != null
              ? 'Payment succeeded but we couldn\'t confirm the reschedule. Contact support with payment ID $paymentId.'
              : 'Something went wrong. Please try again.',
          isError: true);
    } finally {
      if (mounted) setState(() => _rescheduling = false);
    }
  }

  void _showRescheduleSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: Navigator.canPop(context),
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        context.go('/bookings');
      },
      child: _buildContent(context),
    );
  }

  Widget _buildContent(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _cyan)));
    }

    if (_booking == null) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
            leading: _backBtn()),
        body: const Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Text('🔍', style: TextStyle(fontSize: 48)),
          SizedBox(height: 16),
          Text('Booking not found',
              style: TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 16, color: _ink)),
        ])));
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            child: Column(children: [
              if (widget.isNew) _buildSuccessBanner(),
              if (widget.isNew) const SizedBox(height: 16),
              _buildStatusCard(),
              const SizedBox(height: 14),
              if (_trackingStatusOk) _buildLiveTrackingCard(),
              if (_trackingStatusOk) const SizedBox(height: 14),
              if (_status == 'accepted') _buildVerifyProfessionalCard(),
              if (_status == 'accepted') const SizedBox(height: 14),
              if (_status == 'in_progress') _buildCountdownCard(),
              if (_status == 'in_progress') const SizedBox(height: 14),
              if (_status == 'in_progress') _buildMarkDoneCard(),
              if (_status == 'in_progress') const SizedBox(height: 14),
              if (_status == 'in_progress') _buildExtraTimeCard(),
              if (_status == 'in_progress') const SizedBox(height: 14),
              // NEW: reschedule card. Only ever shown while the backend
              // would even consider it eligible (status + 1-hour cutoff);
              // the RPC calls re-check all of this anyway before doing
              // anything.
              if (_rescheduleEligibleStatus) _buildRescheduleCard(),
              if (_rescheduleEligibleStatus) const SizedBox(height: 14),
              _buildBookingInfoCard(),
              const SizedBox(height: 14),
              _buildPriceCard(),
              const SizedBox(height: 14),
              _buildAddressCard(),
              if (_booking?['special_instructions'] != null) ...[
                const SizedBox(height: 14),
                _buildNotesCard(),
              ],
              if (_status == 'completed') ...[
                const SizedBox(height: 14),
                _buildCompletedCard(),
              ],
              const SizedBox(height: 14),
              _buildHelpCard(),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border))),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
          child: Row(children: [
            _backBtn(),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Booking Details',
                  style: TextStyle(fontSize: 17,
                      fontWeight: FontWeight.w900, color: _ink)),
              Text('#${widget.bookingId.substring(0, 8).toUpperCase()}',
                  style: const TextStyle(color: _faint,
                      fontSize: 11, fontFamily: 'monospace')),
            ])),
            if (['pending','accepted','in_progress'].contains(_status))
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: _cyanBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _cyanBg2)),
                child: Row(children: [
                  Container(
                    width: 6, height: 6,
                    decoration: const BoxDecoration(
                        color: _cyan, shape: BoxShape.circle)),
                  const SizedBox(width: 6),
                  const Text('Live',
                      style: TextStyle(color: _cyanDk,
                          fontSize: 11, fontWeight: FontWeight.w800)),
                ])),
          ]),
        ),
      ),
    );
  }

  Widget _backBtn() => GestureDetector(
    onTap: () {
      if (Navigator.canPop(context)) {
        Navigator.pop(context);
      } else {
        context.go('/bookings');
      }
    },
    child: Container(
      width: 40, height: 40,
      decoration: BoxDecoration(
        color: _cyanBg,
        borderRadius: BorderRadius.circular(12)),
      child: const Icon(Icons.arrow_back_ios_new_rounded,
          color: _cyanDk, size: 16)),
  );

  Widget _buildSuccessBanner() {
    return ScaleTransition(
      scale: _successScale,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFF10B981), Color(0xFF059669)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(
              color: _green.withValues(alpha: 0.35),
              blurRadius: 20, offset: const Offset(0, 8))]),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16)),
            child: const Center(
                child: Text('🎉', style: TextStyle(fontSize: 28)))),
          const SizedBox(width: 14),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Booking Confirmed!',
                style: TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w900)),
            SizedBox(height: 3),
            Text('We\'ll keep you updated on your booking status.',
                style: TextStyle(
                    color: Color(0xFFA7F3D0), fontSize: 12, height: 1.4)),
          ])),
        ]),
      ),
    );
  }

  Widget _buildStatusCard() {
    final color = _statusColor(_status);
    final bg    = _statusBg(_status);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Text(_statusIcon(_status),
              style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_statusLabel(_status),
                style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: color)),
            const SizedBox(height: 2),
            Text(_statusDescription(_status),
                style: TextStyle(
                    color: color.withValues(alpha: 0.8),
                    fontSize: 12, height: 1.4)),
          ])),
        ]),
        const SizedBox(height: 16),
        _buildProgressBar(),
        if (_hasWorker && _status != 'cancelled') ...[
          const SizedBox(height: 14),
          _buildWorkerRow(),
        ],
        if (_isInstant && _status == 'accepted') ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10)),
            child: const Row(children: [
              Icon(Icons.bolt_rounded, color: _cyanDk, size: 16),
              SizedBox(width: 6),
              Text('Est. arrival: 10–15 min',
                  style: TextStyle(color: _cyanDk,
                      fontSize: 12, fontWeight: FontWeight.w700)),
            ])),
        ],
      ]),
    );
  }

  Widget _buildProgressBar() {
    final steps = ['pending', 'accepted', 'in_progress', 'completed'];
    final currentIdx = steps.indexOf(_status);
    if (_status == 'cancelled') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFEE2E2),
          borderRadius: BorderRadius.circular(10)),
        child: const Row(children: [
          Icon(Icons.cancel_rounded, color: Color(0xFFDC2626), size: 16),
          SizedBox(width: 8),
          Text('Booking cancelled',
              style: TextStyle(color: Color(0xFFDC2626),
                  fontSize: 12, fontWeight: FontWeight.w700)),
        ]));
    }
    return Row(children: steps.asMap().entries.map((e) {
      final i     = e.key;
      final done  = i <= currentIdx;
      final color = _statusColor(steps[i]);
      return Expanded(child: Row(children: [
        Container(
          width: 20, height: 20,
          decoration: BoxDecoration(
            color: done ? color : _border,
            shape: BoxShape.circle),
          child: done
              ? const Icon(Icons.check_rounded,
                  color: Colors.white, size: 12)
              : null),
        if (i < steps.length - 1)
          Expanded(child: Container(
            height: 2,
            color: i < currentIdx ? color : _border)),
      ]));
    }).toList());
  }

  Widget _buildWorkerRow() {
    final worker = _booking?['worker'] as Map<String, dynamic>?;
    final fullName = worker?['full_name'] as String? ?? 'Professional';
    final displayName = _firstName(fullName);
    // Avatar initials still derived from the FULL name (so two workers
    // sharing a first name still get visually distinct initials) — only
    // the visible text label is trimmed to first name.
    final initials = fullName.trim().split(' ')
        .where((w) => w.isNotEmpty).take(2)
        .map((w) => w[0].toUpperCase()).join();

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(14)),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
            borderRadius: BorderRadius.circular(12)),
          child: Center(child: Text(initials,
              style: const TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 16)))),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(displayName, style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
          const Text('Verified Professional',
              style: TextStyle(color: _muted, fontSize: 11)),
        ])),
        // Contact number — the WORKER's own phone is never shown here;
        // this is always the helpline number, and only appears once a
        // worker is assigned AND we're within 30 minutes of the
        // scheduled time (or later). No "Worker"/"Helpline" label — just
        // the bare number, tappable to dial. Outside that window, or if
        // no worker is assigned, nothing is shown here at all (not even
        // a disabled icon), since there's genuinely no number to offer
        // yet.
        if (_showContactNumber)
          GestureDetector(
            onTap: _callHelpline,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: _cyanBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _cyanBg2)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.phone_rounded, color: _cyanDk, size: 16),
                const SizedBox(width: 6),
                Text(_helplineNumber,
                    style: const TextStyle(color: _cyanDk,
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ]),
            ),
          ),
      ]),
    );
  }

  Widget _buildVerifyProfessionalCard() {
    if (!_otpWindowOpen) {
      final remaining = _timeUntilOtpWindow;
      String remainingText = '';
      if (remaining != null) {
        final h = remaining.inHours;
        final m = remaining.inMinutes % 60;
        remainingText = h > 0 ? '${h}h ${m}m' : '${remaining.inMinutes}m';
      }
      return _card(
        icon: Icons.lock_clock_rounded,
        iconColor: _purple,
        iconBg: _purpleBg,
        title: 'Verify Professional',
        subtitle: 'Opens 15 minutes before your scheduled time',
        child: Container(
          padding: const EdgeInsets.all(16),
          width: double.infinity,
          decoration: BoxDecoration(
            color: _purpleBg2,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _purpleBorder)),
          child: Column(children: [
            const Icon(Icons.hourglass_top_rounded,
                color: _purple, size: 26),
            const SizedBox(height: 8),
            Text(
              remainingText.isNotEmpty
                  ? 'You can verify your professional in $remainingText'
                  : 'Verification will open shortly before your slot',
              textAlign: TextAlign.center,
              style: const TextStyle(color: _purple,
                  fontSize: 13, fontWeight: FontWeight.w700)),
          ]),
        ),
      );
    }

    return _card(
      icon: Icons.verified_user_rounded,
      iconColor: _purple,
      iconBg: _purpleBg,
      title: 'Verify Professional',
      subtitle: 'Ask your professional for their OTP and enter it below',
      child: Column(children: [
        TextField(
          controller: _otpInputCtrl,
          keyboardType: TextInputType.number,
          maxLength: 4,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900,
              letterSpacing: 14, color: _purple),
          decoration: InputDecoration(
            counterText: '',
            filled: true,
            fillColor: _purpleBg2,
            hintText: '0000',
            hintStyle: const TextStyle(color: Color(0xFFC4B5FD), letterSpacing: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _purpleBorder)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _purpleBorder)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _purple, width: 1.5)),
          ),
          onChanged: (_) {
            if (_otpError != null) setState(() => _otpError = null);
          },
        ),
        if (_otpError != null) ...[
          const SizedBox(height: 8),
          Text(_otpError!,
              style: const TextStyle(color: Color(0xFFDC2626),
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ],
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _verifying ? null : _verifyOtp,
          child: Container(
            height: 50,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [_purple, Color(0xFF6D28D9)]),
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(
                  color: _purple.withValues(alpha: 0.35),
                  blurRadius: 14, offset: const Offset(0, 5))]),
            child: _verifying
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.check_circle_outline_rounded,
                          color: Colors.white, size: 18),
                      SizedBox(width: 8),
                      Text('Verify & Start Service',
                          style: TextStyle(color: Colors.white,
                              fontWeight: FontWeight.w800, fontSize: 14)),
                    ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildCountdownCard() {
    final remaining = _remainingServiceTime;
    if (remaining == null) {
      return const SizedBox.shrink();
    }

    final isOvertime = remaining.isNegative;
    final display     = isOvertime ? -remaining : remaining;
    final mins        = display.inMinutes.remainder(60).toString().padLeft(2, '0');
    final secs        = display.inSeconds.remainder(60).toString().padLeft(2, '0');
    final hours       = display.inHours;
    final timeStr     = hours > 0
        ? '${hours.toString().padLeft(2, '0')}:$mins:$secs'
        : '$mins:$secs';

    final color   = isOvertime ? const Color(0xFFDC2626) : _cyan;
    final bgColor = isOvertime ? const Color(0xFFFEF2F2) : _cyanBg;
    final borderColor = isOvertime ? const Color(0xFFFECACA) : _cyanBg2;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: borderColor)),
      child: Column(children: [
        Row(children: [
          Icon(isOvertime ? Icons.timer_off_rounded : Icons.timer_rounded,
              color: color, size: 20),
          const SizedBox(width: 8),
          Text(
            isOvertime ? 'Running Over Time' : 'Time Remaining',
            style: TextStyle(color: color,
                fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        const SizedBox(height: 10),
        Text(timeStr,
            style: TextStyle(color: color,
                fontSize: 40, fontWeight: FontWeight.w900,
                fontFeatures: const [FontFeature.tabularFigures()],
                letterSpacing: 1)),
        const SizedBox(height: 6),
        Text(
          isOvertime
              ? 'The service is taking longer than the ${_totalServiceDurationMins} min booked'
              : 'of $_totalServiceDurationMins min booked'
                '${_extraTimeMins > 0 ? ' (incl. +$_extraTimeMins min extra)' : ''}',
          textAlign: TextAlign.center,
          style: TextStyle(color: color.withValues(alpha: 0.75),
              fontSize: 11.5)),
        if (isOvertime) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(10)),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Icon(Icons.info_outline_rounded,
                  color: Color(0xFFDC2626), size: 14),
              SizedBox(width: 6),
              Text('Need more time? Add extra time below',
                  style: TextStyle(color: Color(0xFFDC2626),
                      fontSize: 11.5, fontWeight: FontWeight.w700)),
            ])),
        ],
      ]),
    );
  }

  Widget _buildMarkDoneCard() {
    return _card(
      icon: Icons.task_alt_rounded,
      iconColor: _green,
      iconBg: const Color(0xFFECFDF5),
      title: 'Work Done?',
      subtitle: 'Confirm once the professional finishes the service',
      child: GestureDetector(
        onTap: _markingDone ? null : _markWorkDone,
        child: Container(
          height: 52,
          width: double.infinity,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_green, _greenDk]),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [BoxShadow(
                color: _green.withValues(alpha: 0.35),
                blurRadius: 14, offset: const Offset(0, 5))]),
          child: _markingDone
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Mark Work as Done',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w800, fontSize: 14)),
                  ]),
        ),
      ),
    );
  }

  // ── NEW: Live tracking ──────────────────────────────────────
  DateTime? get _trackingOpensAt =>
      _scheduledAt?.subtract(const Duration(minutes: 30));

  /// Tracking only applies while a pro is assigned and hasn't arrived
  /// yet. Once OTP is verified (pro is at the door), the card goes away.
  bool get _trackingStatusOk => _status == 'accepted' && _hasWorker;

  bool get _trackingWindowOpen {
    final opens = _trackingOpensAt;
    return opens != null && !DateTime.now().isBefore(opens);
  }

  LatLng? get _homeLatLng {
    final addr = _booking?['addresses'] as Map<String, dynamic>?;
    final lat = (addr?['latitude'] as num?)?.toDouble();
    final lng = (addr?['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  Future<void> _refreshTracking() async {
    if (!mounted || _trackingFetching) return;

    if (!_trackingStatusOk || !_trackingWindowOpen) {
      if (_proLatLng != null || _trackingReason != null) {
        setState(() {
          _proLatLng = null;
          _trackingReason = null;
          _trackingMapCtrl = null;
        });
      }
      return;
    }

    final customerId = SupabaseService.currentUserId;
    if (customerId == null) return;

    _trackingFetching = true;
    try {
      final res = await _supabase.rpc('get_booking_live_tracking', params: {
        'p_booking_id':  widget.bookingId,
        'p_customer_id': customerId,
      });
      final row = (res is List && res.isNotEmpty)
          ? res.first as Map<String, dynamic>
          : null;
      if (!mounted) return;

      final ok = row?['available'] == true;
      setState(() {
        _trackingReason = row?['reason'] as String? ?? 'error';
        if (ok) {
          _proLatLng = LatLng(
            (row!['worker_lat'] as num).toDouble(),
            (row['worker_lng'] as num).toDouble(),
          );
          _proUpdatedAt = DateTime.tryParse(
              row['location_updated_at']?.toString() ?? '')?.toLocal();
        } else {
          _proLatLng = null;
          _trackingMapCtrl = null;
        }
      });
      _fitTrackingCamera();
    } catch (e) {
      debugPrint('live tracking fetch error: $e');
      if (mounted && _trackingReason == null) {
        setState(() => _trackingReason = 'error');
      }
    } finally {
      _trackingFetching = false;
    }
  }

  /// Frames both pins (pro + customer's home) in the map. The map's
  /// own gestures are off (it sits inside a scrolling page), so this
  /// re-runs on every location update to keep both in view.
  void _fitTrackingCamera() {
    final ctrl = _trackingMapCtrl;
    final pro = _proLatLng;
    if (ctrl == null || pro == null) return;
    final home = _homeLatLng;

    try {
      if (home == null ||
          Geolocator.distanceBetween(pro.latitude, pro.longitude,
                  home.latitude, home.longitude) < 50) {
        ctrl.animateCamera(CameraUpdate.newLatLngZoom(pro, 15));
        return;
      }
      final bounds = LatLngBounds(
        southwest: LatLng(math.min(pro.latitude, home.latitude),
            math.min(pro.longitude, home.longitude)),
        northeast: LatLng(math.max(pro.latitude, home.latitude),
            math.max(pro.longitude, home.longitude)),
      );
      ctrl.animateCamera(CameraUpdate.newLatLngBounds(bounds, 50));
    } catch (e) {
      // newLatLngBounds can throw if the map hasn't been laid out yet —
      // the next 15s refresh will retry.
      debugPrint('fit tracking camera skipped: $e');
    }
  }

  String _fmtClock(DateTime dt) {
    final h = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
    final m = dt.minute.toString().padLeft(2, '0');
    return '$h:$m ${dt.hour >= 12 ? 'PM' : 'AM'}';
  }

  String _fmtDistance(double meters) => meters < 1000
      ? '${meters.round()} m away'
      : '${(meters / 1000).toStringAsFixed(1)} km away';

  String _fmtUpdatedAgo(DateTime? t) {
    if (t == null) return '';
    final secs = DateTime.now().difference(t).inSeconds;
    if (secs < 60) return 'Updated just now';
    return 'Updated ${secs ~/ 60} min ago';
  }

  Widget _buildLiveTrackingCard() {
    final worker = _booking?['worker'] as Map<String, dynamic>?;
    final proName = _firstName(worker?['full_name'] as String? ?? 'Professional');
    final opens = _trackingOpensAt;

    // Before the 30-min window: just say when tracking starts.
    if (!_trackingWindowOpen) {
      return _card(
        icon: Icons.near_me_rounded,
        title: 'Live Tracking',
        subtitle: 'See where your professional is',
        child: Row(children: [
          const Icon(Icons.schedule_rounded, color: _cyanDk, size: 18),
          const SizedBox(width: 10),
          Expanded(child: Text(
            opens != null
                ? 'Live tracking starts at ${_fmtClock(opens)} — 30 minutes before your booking.'
                : 'Live tracking starts 30 minutes before your booking.',
            style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.45))),
        ]),
      );
    }

    final pro = _proLatLng;
    final home = _homeLatLng;

    Widget body;
    if (pro != null) {
      final distance = home != null
          ? Geolocator.distanceBetween(
              pro.latitude, pro.longitude, home.latitude, home.longitude)
          : null;

      body = Column(children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            height: 220,
            child: GoogleMap(
              initialCameraPosition: CameraPosition(target: pro, zoom: 14),
              onMapCreated: (c) {
                _trackingMapCtrl = c;
                Future.delayed(
                    const Duration(milliseconds: 300), _fitTrackingCamera);
              },
              markers: {
                Marker(
                  markerId: const MarkerId('pro'),
                  position: pro,
                  icon: BitmapDescriptor.defaultMarkerWithHue(
                      BitmapDescriptor.hueAzure),
                  infoWindow: InfoWindow(title: proName),
                ),
                if (home != null)
                  Marker(
                    markerId: const MarkerId('home'),
                    position: home,
                    icon: BitmapDescriptor.defaultMarkerWithHue(
                        BitmapDescriptor.hueRed),
                    infoWindow: const InfoWindow(title: 'Your address'),
                  ),
              },
              zoomControlsEnabled: false,
              myLocationButtonEnabled: false,
              mapToolbarEnabled: false,
              scrollGesturesEnabled: false,
              zoomGesturesEnabled: false,
              rotateGesturesEnabled: false,
              tiltGesturesEnabled: false,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: _cyanBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _cyanBg2)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.directions_walk_rounded,
                  color: _cyanDk, size: 15),
              const SizedBox(width: 5),
              Text(
                distance != null ? _fmtDistance(distance) : 'On the way',
                style: const TextStyle(color: _cyanDk,
                    fontSize: 12.5, fontWeight: FontWeight.w800)),
            ]),
          ),
          const Spacer(),
          Text(_fmtUpdatedAgo(_proUpdatedAt),
              style: const TextStyle(color: _faint, fontSize: 11)),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          _trackingLegendDot(const Color(0xFF2196F3)),
          const SizedBox(width: 5),
          Text(proName, style: const TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(width: 16),
          _trackingLegendDot(const Color(0xFFE53935)),
          const SizedBox(width: 5),
          const Text('Your address',
              style: TextStyle(color: _muted, fontSize: 11)),
        ]),
      ]);
    } else if (_trackingReason == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 18),
        child: Center(child: Column(children: [
          SizedBox(width: 24, height: 24,
              child: CircularProgressIndicator(color: _cyan, strokeWidth: 2.5)),
          SizedBox(height: 10),
          Text('Finding your professional…',
              style: TextStyle(color: _faint, fontSize: 12)),
        ])),
      );
    } else {
      body = Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border)),
        child: Row(children: [
          const Icon(Icons.location_off_rounded, color: _faint, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(
            '$proName\'s location isn\'t available right now. '
            'It will appear here as soon as their phone shares it.',
            style: const TextStyle(color: _muted, fontSize: 12.5, height: 1.45))),
        ]),
      );
    }

    return _card(
      icon: Icons.near_me_rounded,
      title: 'Live Tracking',
      subtitle: '$proName is on the way',
      child: body,
    );
  }

  Widget _trackingLegendDot(Color c) => Container(
      width: 9, height: 9,
      decoration: BoxDecoration(color: c, shape: BoxShape.circle));

  // ── NEW: "Modify your booking" card ─────────────────────────
  // Styled after the reference design: a plain title + description,
  // then a single solid button — no cancel option sits next to it,
  // by design (this app doesn't offer self-serve cancellation here).
  Widget _buildRescheduleCard() {
    final open = _canReschedule;
    final left = _rescheduleTimeLeft;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Modify your booking',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900,
                color: _ink)),
        const SizedBox(height: 6),
        const Text(
            'Need to make changes? Reschedule your booking below.\n'
            'First reschedule is free, and must be done at least 1 hour '
            'before your slot.',
            style: TextStyle(color: _muted, fontSize: 12.5, height: 1.5)),
        const SizedBox(height: 14),
        // Countdown (open) or closed notice — sits right above the button.
        if (open && left != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: _cyanBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _cyanBg2)),
            child: Row(children: [
              const Icon(Icons.timer_outlined, color: _cyanDk, size: 16),
              const SizedBox(width: 8),
              Expanded(child: Text(
                  'Reschedule available for ${_formatTimeLeft(left)} more',
                  style: const TextStyle(color: _cyanDk,
                      fontSize: 12.5, fontWeight: FontWeight.w700))),
            ]),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFFEF2F2),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFECACA))),
            child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.lock_clock_rounded, color: Color(0xFFDC2626), size: 16),
              SizedBox(width: 8),
              Expanded(child: Text(
                  'Reschedule closed — it\'s only allowed up to 1 hour '
                  'before your scheduled time.',
                  style: TextStyle(color: Color(0xFFB91C1C),
                      fontSize: 12.5, fontWeight: FontWeight.w700,
                      height: 1.4))),
            ]),
          ),
        GestureDetector(
          onTap: (!open || _rescheduling) ? null : _startReschedule,
          child: Container(
            height: 50,
            width: double.infinity,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: open
                  ? const LinearGradient(colors: [_cyan, _cyanDk])
                  : null,
              color: open ? null : const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(14),
              boxShadow: open
                  ? [BoxShadow(
                      color: _cyan.withValues(alpha: 0.32),
                      blurRadius: 10, offset: const Offset(0, 4))]
                  : []),
            child: _rescheduling
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2.5))
                : Text('RESCHEDULE',
                    style: TextStyle(
                        color: open ? Colors.white : _faint,
                        fontWeight: FontWeight.w900, fontSize: 14,
                        letterSpacing: 0.5)),
          ),
        ),
        const SizedBox(height: 12),
        GestureDetector(
          onTap: _showCancellationInfoSheet,
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
            Icon(Icons.info_outline_rounded, color: _cyanDk, size: 15),
            SizedBox(width: 6),
            Text('Want to cancel instead? See how',
                style: TextStyle(color: _cyanDk,
                    fontSize: 12.5, fontWeight: FontWeight.w700)),
          ]),
        ),
      ]),
    );
  }

  // ── NEW: Cancellation info sheet ─────────────────────────────
  // There's no self-serve cancel button in this app (by design — see
  // _buildRescheduleCard above), so this explains the actual process
  // instead of leaving the customer with no path at all. Styled after
  // the same "100% Refund Guarantee" info-sheet pattern, in this app's
  // cyan rather than black/purple.
  void _showCancellationInfoSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: EdgeInsets.fromLTRB(
            24, 14, 24, 24 + MediaQuery.of(ctx).padding.bottom),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 40, height: 4,
            margin: const EdgeInsets.only(bottom: 18),
            decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2))),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: _cyanBg, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.cancel_outlined,
                  color: _cyanDk, size: 20)),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Need to Cancel?',
                  style: TextStyle(fontSize: 17,
                      fontWeight: FontWeight.w900, color: _ink)),
            ),
          ]),
          const SizedBox(height: 16),
          const Text(
              'We don\'t support cancelling a booking directly in the app '
              'right now. To cancel, please contact our support team at '
              'least 1 hour before your scheduled time and we\'ll cancel '
              'it for you.',
              style: TextStyle(color: _muted, fontSize: 13.5, height: 1.6)),
          const SizedBox(height: 10),
          const Text(
              'If you\'ve already paid online, any eligible refund will be '
              'issued to your original payment method and may take 5–7 '
              'business days to reflect in your account.',
              style: TextStyle(color: _muted, fontSize: 13.5, height: 1.6)),
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () { Navigator.pop(ctx); _callHelpline(); },
            child: Container(
              height: 50,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _cyanBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _cyanBg2)),
              child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.phone_rounded, color: _cyanDk, size: 17),
                SizedBox(width: 8),
                Text('Call Support',
                    style: TextStyle(color: _cyanDk,
                        fontWeight: FontWeight.w800, fontSize: 14)),
              ]),
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.pop(ctx),
            child: Container(
              height: 50,
              width: double.infinity,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [BoxShadow(
                    color: _cyan.withValues(alpha: 0.32),
                    blurRadius: 10, offset: const Offset(0, 4))]),
              child: const Text('Got it',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 14)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildBookingInfoCard() {
    final scheduledAt = _booking?['scheduled_at'] as String?;
    final bookingType = _booking?['booking_type'] as String? ?? 'schedule';
    final svc         = _booking?['services'] as Map<String, dynamic>?;
    final rawDuration = (_booking?['service_duration_minutes'] as num?)?.toInt();
    final duration    = rawDuration != null
        ? rawDuration + _extraTimeMins
        : (_booking?['booking_duration_minutes'] as int?
            ?? svc?['duration_minutes'] as int?);
    final services    = _bookedServices;

    String formattedDate = '—';
    String formattedTime = '—';
    if (scheduledAt != null) {
      final dt = DateTime.tryParse(scheduledAt)?.toLocal();
      if (dt != null) {
        const months = ['Jan','Feb','Mar','Apr','May','Jun',
            'Jul','Aug','Sep','Oct','Nov','Dec'];
        formattedDate = '${dt.day} ${months[dt.month - 1]} ${dt.year}';
        final h   = dt.hour > 12 ? dt.hour - 12 : (dt.hour == 0 ? 12 : dt.hour);
        final m   = dt.minute.toString().padLeft(2, '0');
        final ampm = dt.hour >= 12 ? 'PM' : 'AM';
        formattedTime = '$h:$m $ampm';
      }
    }

    final serviceRows = <Map<String, dynamic>>[
      for (final s in services)
        {
          'icon': Icons.cleaning_services_rounded,
          'label': (s['qty'] as int) > 1 ? '${s['name']} ×${s['qty']}' : s['name'],
          'value': '₹${(s['unit_price'] as int) * (s['qty'] as int)}',
        },
    ];

    final rows = <Map<String, dynamic>>[
      ...serviceRows,
      {'icon': bookingType == 'instant'
          ? Icons.bolt_rounded : Icons.calendar_month_rounded,
        'label': 'Type',
        'value': bookingType == 'instant' ? 'Instant Booking' : 'Scheduled'},
      if (bookingType != 'instant')
        {'icon': Icons.calendar_today_rounded,
          'label': 'Date', 'value': formattedDate},
      {'icon': Icons.access_time_rounded,
        'label': bookingType == 'instant' ? 'Booked At' : 'Time',
        'value': formattedTime},
      if (duration != null)
        {'icon': Icons.timelapse_rounded,
          'label': 'Duration', 'value': '~$duration min'},
      {'icon': Icons.payments_rounded,
        'label': 'Payment',
        'value': _paymentStatus == 'paid' ? 'Paid ✓' : 'Cash on Delivery'},
    ];

    return _card(
      icon: Icons.receipt_long_rounded,
      title: 'Booking Info',
      subtitle: services.length > 1
          ? '${services.length} services in this order'
          : 'Your service details',
      child: Column(children: [
        for (int i = 0; i < rows.length; i++) ...[
          Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _cyanBg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _cyanBg2)),
              child: Icon(rows[i]['icon'] as IconData,
                  color: _cyanDk, size: 17)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(rows[i]['label'] as String,
                  style: const TextStyle(color: _faint,
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
              Text(rows[i]['value'] as String,
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: _ink)),
            ])),
          ]),
          if (i < rows.length - 1)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 10),
              child: Divider(height: 1, color: _line)),
        ],
      ]),
    );
  }

  Widget _buildPriceCard() {
    final base     = (_booking?['base_price'] as num?)?.toInt() ?? 0;
    final discount = (_booking?['discount_amount'] as num?)?.toInt() ?? 0;
    final final_   = (_booking?['final_amount'] as num?)?.toInt() ?? 0;
    final promo    = _booking?['promo_code'] as String?;
    final services = _bookedServices;
    final hasMultiple = services.length > 1;
    final extraTimePrice = (_booking?['extra_time_price'] as num?)?.toInt() ?? 0;
    final extraTimePaid  = _extraTimePaymentStatus == 'paid';

    return _card(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Price Breakdown',
      subtitle: 'Payment summary',
      child: Column(children: [
        if (hasMultiple)
          for (final s in services)
            _priceRow(
              (s['qty'] as int) > 1 ? '${s['name']} ×${s['qty']}' : s['name'] as String,
              '₹${(s['unit_price'] as int) * (s['qty'] as int)}',
              _muted, _ink)
        else
          _priceRow('Service Total', '₹$base', _muted, _ink),
        if (discount > 0)
          _priceRow(
              promo != null ? 'Promo ($promo)' : 'Discount',
              '− ₹$discount', _muted, _greenDk),
        const Divider(color: _line, height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
              _paymentStatus == 'paid' ? 'Amount Paid Online' : 'Cash Due to Worker',
              style: const TextStyle(fontSize: 15,
                  fontWeight: FontWeight.w900, color: _ink)),
          Text('₹$final_',
              style: const TextStyle(fontSize: 26,
                  fontWeight: FontWeight.w900, color: _cyanDk)),
        ]),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: _cyanBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cyanBg2)),
          child: Row(children: [
            const Icon(Icons.payments_rounded, color: _cyanDk, size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              _paymentStatus == 'paid'
                  ? 'Paid online ✓ — no cash needed'
                  : 'Pay ₹$final_ cash to the worker after service',
              style: TextStyle(
                color: _paymentStatus == 'paid' ? _greenDk : _muted,
                fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        ),
        if (extraTimePrice > 0) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F3FF),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFDDD6FE))),
            child: Row(children: [
              const Icon(Icons.more_time_rounded,
                  color: Color(0xFF7C3AED), size: 18),
              const SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('+$_extraTimeMins min Extra Time',
                    style: const TextStyle(color: Color(0xFF7C3AED),
                        fontSize: 12, fontWeight: FontWeight.w700)),
                Text(
                  extraTimePaid
                      ? 'Paid separately online ✓'
                      : 'Payment pending',
                  style: TextStyle(
                      color: extraTimePaid
                          ? const Color(0xFF059669) : _muted,
                      fontSize: 10.5)),
              ])),
              Text('₹$extraTimePrice',
                  style: const TextStyle(color: Color(0xFF7C3AED),
                      fontSize: 14, fontWeight: FontWeight.w900)),
            ]),
          ),
        ],
      ]),
    );
  }

  Widget _priceRow(String l, String v, Color lc, Color vc) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
      Text(l, style: TextStyle(color: lc, fontSize: 13)),
      Text(v, style: TextStyle(
          color: vc, fontSize: 13, fontWeight: FontWeight.bold)),
    ]));

  Widget _buildAddressCard() {
    final addr = _booking?['addresses'] as Map<String, dynamic>?;
    if (addr == null) return const SizedBox.shrink();

    final parts = [
      if (addr['flat_no'] != null) addr['flat_no'],
      if (addr['building'] != null) addr['building'],
      addr['area'], addr['city'],
      if (addr['pincode'] != null) addr['pincode'],
    ].where((e) => e != null).join(', ');

    final label = addr['label'] as String? ?? 'Address';
    final icon  = label == 'Home'
        ? Icons.home_rounded
        : label == 'Office'
            ? Icons.business_rounded
            : Icons.location_on_rounded;

    return _card(
      icon: Icons.location_on_rounded,
      title: 'Service Address',
      subtitle: 'Where the service will be done',
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: _cyanBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _cyanBg2)),
          child: Icon(icon, color: _cyanDk, size: 20)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
          const SizedBox(height: 2),
          Text(parts, style: const TextStyle(
              color: _muted, fontSize: 12, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _buildNotesCard() {
    final notes = _booking?['special_instructions'] as String? ?? '';
    return _card(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'Special Instructions',
      subtitle: 'Notes for the professional',
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFBEB),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFDE68A))),
        child: Text(notes,
            style: const TextStyle(
                color: Color(0xFF92400E), fontSize: 13, height: 1.5))),
    );
  }

  Widget _buildCompletedCard() {
    final startedAt = _booking?['work_started_at'] as String?;
    final endedAt   = _booking?['work_ended_at'] as String?;
    final durSec    = (_booking?['work_duration_seconds'] as num?)?.toInt();

    String duration = '';
    if (durSec != null) {
      final h = durSec ~/ 3600;
      final m = (durSec % 3600) ~/ 60;
      final s = durSec % 60;
      if (h > 0) {
        duration = '${h}h ${m}m ${s}s';
      } else if (m > 0) duration = '${m}m ${s}s';
      else duration = '${s}s';
    }

    return _card(
      icon: Icons.task_alt_rounded,
      iconColor: _green,
      iconBg: const Color(0xFFECFDF5),
      title: 'Work Summary',
      subtitle: 'Service completed successfully',
      child: Column(children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFF6EE7B7))),
          child: const Row(children: [
            Text('✅', style: TextStyle(fontSize: 28)),
            SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Service Completed!',
                  style: TextStyle(fontWeight: FontWeight.w900,
                      fontSize: 14, color: _greenDk)),
              SizedBox(height: 2),
              Text('Thank you for choosing Cleenzo.',
                  style: TextStyle(color: _green, fontSize: 11)),
            ])),
          ]),
        ),
        if (duration.isNotEmpty) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _bg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _border)),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
              const Text('Work Duration',
                  style: TextStyle(color: _muted, fontSize: 13)),
              Text(duration,
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      color: _ink, fontSize: 13)),
            ])),
        ],
      ]),
    );
  }

  Widget _buildHelpCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border)),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFFFFF7ED),
            borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.support_agent_rounded,
              color: Color(0xFFEA580C), size: 22)),
        const SizedBox(width: 12),
        const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Need Help?',
              style: TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 14, color: _ink)),
          Text('Contact our support team',
              style: TextStyle(color: _faint, fontSize: 11)),
        ])),
        GestureDetector(
          onTap: () => context.push('/help'),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFFED7AA))),
            child: const Text('Help',
                style: TextStyle(color: Color(0xFFEA580C),
                    fontSize: 12, fontWeight: FontWeight.w800)))),
      ]),
    );
  }

  Widget _buildExtraTimeCard() {
    final alreadyAdded = _extraTimeMins > 0;

    return _card(
      icon: Icons.more_time_rounded,
      iconColor: const Color(0xFF7C3AED),
      iconBg: const Color(0xFFEDE9FE),
      title: 'Need More Time?',
      subtitle: 'Add $_xtAddMins extra minutes if the service is still in progress',
      child: alreadyAdded
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF6EE7B7))),
              child: Row(children: [
                const Icon(Icons.check_circle_rounded,
                    color: Color(0xFF059669), size: 18),
                const SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('+$_extraTimeMins min added · ₹$_bookingExtraTimePrice extra',
                      style: const TextStyle(color: Color(0xFF059669),
                          fontWeight: FontWeight.w900, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(
                    _extraTimePaymentStatus == 'paid'
                        ? 'Paid online ✓ — no extra cash needed for this'
                        : 'Payment pending — try adding extra time again',
                    style: const TextStyle(color: Color(0xFF6EE7B7),
                        fontSize: 11)),
                ])),
              ]))
          : GestureDetector(
              onTap: _addingExtraTime ? null : _startExtraTimePayment,
              child: Container(
                height: 52,
                width: double.infinity,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF7C3AED), Color(0xFF6D28D9)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF7C3AED).withValues(alpha: 0.35),
                      blurRadius: 14, offset: const Offset(0, 5))]),
                child: _addingExtraTime
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.more_time_rounded,
                              color: Colors.white, size: 18),
                          const SizedBox(width: 8),
                          Text('+$_xtAddMins min · ₹$_xtPrice',
                              style: const TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w900, fontSize: 15)),
                          const SizedBox(width: 8),
                          const Text('Pay & Add Extra Time',
                              style: TextStyle(color: Colors.white70,
                                  fontSize: 13)),
                        ]),
              )),
    );
  }

  // ── Extra time payment ───────────────────────────────────────
  Future<void> _startExtraTimePayment() async {
    if (_addingExtraTime) return;
    // Re-read the latest admin setting right before charging, so a
    // customer who opened this screen before a price change still
    // pays the current price — then lock it in for this payment.
    await _loadExtraTimeSettings();
    if (!mounted) return;
    final price = _xtPrice;
    final mins  = _xtAddMins;
    _xtPendingPrice = price;
    _xtPendingMins  = mins;
    setState(() => _addingExtraTime = true);

    String orderId;
    try {
      final res = await http.post(
        Uri.parse('$_paymentsApiBase/api/payments/order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount':   price * 100, // paise
          'currency': 'INR',
          'receipt':  'xt_${widget.bookingId.substring(0, 8)}_${DateTime.now().millisecondsSinceEpoch % 1000000}',
          'notes': {
            'type':       'extra_time',
            'booking_id': widget.bookingId,
          },
        }),
      ).timeout(const Duration(seconds: 15));

      if (res.statusCode != 200) {
        throw Exception('Order creation failed: ${res.statusCode} ${res.body}');
      }
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final id = data['order_id'] as String?;
      if (id == null) throw Exception('No order_id in response: ${res.body}');
      orderId = id;
    } catch (e) {
      debugPrint('Extra time order creation error: $e');
      if (mounted) setState(() => _addingExtraTime = false);
      _showExtraTimeSnack('Could not start payment. Please try again.',
          isError: true);
      return;
    }

    final options = {
      'key':         _razorpayKey,
      'order_id':    orderId,
      'amount':      price * 100,
      'name':        'Cleenzo',
      'description': '+$mins min Extra Time',
      'prefill':     {'contact': _customerPhone ?? '', 'email': _customerEmail ?? ''},
      'notes':       {'booking_id': widget.bookingId, 'type': 'extra_time'},
      'theme':       {'color': '#7C3AED'},
      'method': {
        'upi': true, 'netbanking': true,
        'card': true, 'wallet': true,
        'emi': false, 'cardless_emi': false, 'paylater': false,
      },
    };

    try {
      _extraTimeRazorpay.open(options);
    } catch (e) {
      debugPrint('Extra time Razorpay open error: $e');
      if (mounted) setState(() => _addingExtraTime = false);
      _showExtraTimeSnack('Could not open payment. Please try again.',
          isError: true);
    }
  }

  Future<void> _onExtraTimePaymentSuccess(
      PaymentSuccessResponse response) async {
    try {
      final bookingId  = widget.bookingId;
      final currentDur = (_booking?['booking_duration_minutes'] as num?)?.toInt() ?? 0;
      final mins  = _xtPendingMins ?? _xtAddMins;
      final price = _xtPendingPrice ?? _xtPrice;

      await _supabase.from('bookings').update({
        'extra_time_mins':           mins,
        'extra_time_price':          price,
        'booking_duration_minutes':  currentDur + mins,
        'extra_time_payment_id':     response.paymentId,
        'extra_time_payment_status': 'paid',
      }).eq('id', bookingId);

      await _loadBooking();

      _showExtraTimeSnack(
          '✅ +$mins min added! ₹$price paid — no extra cash needed for this.');
    } catch (e) {
      debugPrint('Extra time DB update error: $e');
      _showExtraTimeSnack(
          'Payment succeeded — confirming it now. If it doesn\'t show up '
          'in a minute, contact support with payment ID ${response.paymentId}.',
          isError: true);
    } finally {
      if (mounted) setState(() => _addingExtraTime = false);
    }
  }

  void _onExtraTimePaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _addingExtraTime = false);
    _showExtraTimeSnack(
        'Payment failed: ${response.message ?? "Please try again"}',
        isError: true);
  }

  void _onExtraTimeExternalWallet(ExternalWalletResponse response) {
    if (mounted) setState(() => _addingExtraTime = false);
    _showExtraTimeSnack('External wallet: ${response.walletName}');
  }

  void _showExtraTimeSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFDC2626) : const Color(0xFF059669),
      duration: const Duration(seconds: 3),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  Widget _card({
    required IconData icon,
    Color? iconColor,
    Color? iconBg,
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 12, offset: const Offset(0, 4))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: iconBg ?? _cyanBg,
                borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: iconColor ?? _cyanDk, size: 18)),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
              Text(subtitle, style: const TextStyle(
                  color: _faint, fontSize: 10.5)),
            ])),
          ]),
        ),
        const Divider(height: 1, color: _line),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }
}

// ── Reschedule slot picker sheet ────────────────────────────────
// Shows real availability (via admin_get_area_slot_grid — the same RPC
// the new-booking flow uses) instead of a free-form date/time picker,
// so a customer can only pick a slot that's actually open. Returns the
// chosen DateTime via Navigator.pop, or null if dismissed.
class _RescheduleSlotSheet extends StatefulWidget {
  final SupabaseClient supabase;
  final String pincode;
  final int durationMins;
  final List<String> timeSlots;

  const _RescheduleSlotSheet({
    required this.supabase,
    required this.pincode,
    required this.durationMins,
    required this.timeSlots,
  });

  @override
  State<_RescheduleSlotSheet> createState() => _RescheduleSlotSheetState();
}

class _RescheduleSlotSheetState extends State<_RescheduleSlotSheet> {
  static const _cyan    = Color(0xFF06B6D4);
  static const _cyanDk  = Color(0xFF0891B2);
  static const _cyanBg  = Color(0xFFECFEFF);
  static const _cyanBg2 = Color(0xFFD6F6FB);
  static const _border  = Color(0xFFE8EDF2);
  static const _ink     = Color(0xFF0F172A);
  static const _muted   = Color(0xFF64748B);
  static const _faint   = Color(0xFF94A3B8);
  static const _bg      = Color(0xFFF8FAFC);

  // Same as reschedule_booking_check()'s cutoff — kept in sync so the
  // UI never offers a time the backend would reject anyway. Also used
  // as the minimum notice period, same spirit as the new-booking flow's
  // 30-min notice but matching the 1-hour reschedule rule specifically.
  static const _cutoffHours = 1;

  late DateTime _selectedDate;
  String _selectedTime = '';
  Map<String, bool> _slotAvailability = {};
  bool _loading = false;

  List<DateTime> get _dates =>
      List.generate(14, (i) => DateTime.now().add(Duration(days: i)));

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _loadSlots(_selectedDate);
  }

  DateTime _slotToDateTime(DateTime date, String slot) {
    final parts = slot.split(' ');
    final hm    = parts[0].split(':');
    int hh      = int.parse(hm[0]);
    final mm    = int.parse(hm[1]);
    final pm    = parts[1] == 'PM';
    if (pm && hh != 12) hh += 12;
    if (!pm && hh == 12) hh = 0;
    return DateTime(date.year, date.month, date.day, hh, mm);
  }

  Future<void> _loadSlots(DateTime date) async {
    setState(() { _loading = true; _slotAvailability = {}; });
    try {
      final dateStr = '${date.year}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';

      final result = await widget.supabase.rpc('admin_get_area_slot_grid', params: {
        'p_pincode':       widget.pincode,
        'p_date':          dateStr,
        'p_duration_mins': widget.durationMins,
      });
      final rows = (result as List).cast<Map<String, dynamic>>();

      final byTwentyFourHour = <String, bool>{
        for (final row in rows)
          row['time_slot'] as String: row['available'] as bool? ?? false,
      };

      final cutoff = DateTime.now().add(const Duration(hours: _cutoffHours));
      final availability = <String, bool>{};

      for (final slot in widget.timeSlots) {
        final slotDt = _slotToDateTime(date, slot);
        if (slotDt.isBefore(cutoff)) { availability[slot] = false; continue; }
        final hh  = slotDt.hour.toString().padLeft(2, '0');
        final mm  = slotDt.minute.toString().padLeft(2, '0');
        availability[slot] = byTwentyFourHour['$hh:$mm'] ?? false;
      }

      if (mounted) {
        setState(() {
          _slotAvailability = availability;
          _loading = false;
          if (_selectedTime.isNotEmpty &&
              availability[_selectedTime] == false) {
            _selectedTime = '';
          }
        });
      }
    } catch (e) {
      debugPrint('reschedule slot grid error: $e');
      if (mounted) {
        setState(() {
          // Fail open with everything shown unavailable is safer than
          // fail-open-available here — worse to let a customer pick a
          // slot we couldn't actually verify than to show "none found".
          _slotAvailability = {for (final s in widget.timeSlots) s: false};
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final availableCount =
        _slotAvailability.values.where((v) => v == true).length;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.5,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
        child: Column(children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40, height: 4,
            decoration: BoxDecoration(
                color: const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
            child: Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: _cyanBg, borderRadius: BorderRadius.circular(11)),
                child: const Icon(Icons.event_repeat_rounded,
                    color: _cyanDk, size: 20)),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pick a New Slot',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                        color: _ink)),
                Text('Only open time slots are shown',
                    style: TextStyle(color: _faint, fontSize: 11)),
              ])),
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.close_rounded,
                      size: 16, color: Color(0xFF64748B)))),
            ]),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
              children: [
                const Text('Choose Date',
                    style: TextStyle(fontWeight: FontWeight.w800,
                        fontSize: 13, color: _ink)),
                const SizedBox(height: 10),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _dates.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 10),
                    itemBuilder: (_, i) {
                      final d = _dates[i];
                      final active = d.day == _selectedDate.day &&
                          d.month == _selectedDate.month;
                      return GestureDetector(
                        onTap: () {
                          setState(() { _selectedDate = d; _selectedTime = ''; });
                          HapticFeedback.selectionClick();
                          _loadSlots(d);
                        },
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 56,
                          decoration: BoxDecoration(
                            gradient: active
                                ? const LinearGradient(colors: [_cyan, _cyanDk])
                                : null,
                            color: active ? null : _bg,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: active ? _cyan : _border)),
                          child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                            Text(
                                ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d.weekday - 1],
                                style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                                    color: active ? const Color(0xFFDFFAFE) : _faint)),
                            Text('${d.day}',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900,
                                    color: active ? Colors.white : _ink)),
                            Text(i == 0 ? 'TODAY' : '·',
                                style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900,
                                    color: active
                                        ? Colors.white
                                        : (i == 0 ? _cyan : Colors.transparent))),
                          ]),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 18),
                Row(children: [
                  const Text('Choose Time',
                      style: TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 13, color: _ink)),
                  const Spacer(),
                  Text(
                      _loading ? 'Checking…' : '$availableCount slots open',
                      style: const TextStyle(color: _faint, fontSize: 11.5,
                          fontWeight: FontWeight.w700)),
                ]),
                const SizedBox(height: 10),
                _loading
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 24),
                        child: Center(child: CircularProgressIndicator(color: _cyan)))
                    : GridView.count(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        crossAxisCount: 3,
                        childAspectRatio: 2.0,
                        crossAxisSpacing: 10, mainAxisSpacing: 10,
                        children: widget.timeSlots.map((slot) {
                          final active  = _selectedTime == slot;
                          final isAvail = _slotAvailability[slot] ?? false;
                          final isFull  = !isAvail;
                          return GestureDetector(
                            onTap: isFull ? null : () {
                              setState(() => _selectedTime = slot);
                              HapticFeedback.selectionClick();
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              decoration: BoxDecoration(
                                gradient: active && !isFull
                                    ? const LinearGradient(colors: [_cyan, _cyanDk])
                                    : null,
                                color: isFull ? _bg : active ? null : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: isFull ? _border : active ? _cyan : _border)),
                              child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                Text(slot, style: TextStyle(
                                    fontSize: 11, fontWeight: FontWeight.w800,
                                    color: isFull
                                        ? const Color(0xFFCBD5E1)
                                        : active ? Colors.white
                                        : const Color(0xFF334155))),
                                const SizedBox(height: 2),
                                if (isFull)
                                  const Text('Full', style: TextStyle(
                                      fontSize: 9, fontWeight: FontWeight.w600,
                                      color: Color(0xFFCBD5E1)))
                                else
                                  Container(width: 5, height: 5,
                                    decoration: BoxDecoration(
                                      color: active
                                          ? Colors.white.withValues(alpha: 0.8)
                                          : _cyan,
                                      shape: BoxShape.circle)),
                              ]),
                            ),
                          );
                        }).toList(),
                      ),
                if (!_loading && availableCount == 0) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFED7AA))),
                    child: const Row(children: [
                      Icon(Icons.event_busy_rounded,
                          color: Color(0xFFEA580C), size: 22),
                      SizedBox(width: 10),
                      Expanded(child: Text(
                          'No open slots on this date — try another day',
                          style: TextStyle(color: Color(0xFF92400E),
                              fontSize: 12.5, fontWeight: FontWeight.w700))),
                    ]),
                  ),
                ],
                const SizedBox(height: 18),
                GestureDetector(
                  onTap: _selectedTime.isEmpty
                      ? null
                      : () => Navigator.pop(
                          context, _slotToDateTime(_selectedDate, _selectedTime)),
                  child: Container(
                    height: 52,
                    width: double.infinity,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: _selectedTime.isNotEmpty
                          ? const LinearGradient(colors: [_cyan, _cyanDk])
                          : null,
                      color: _selectedTime.isEmpty ? const Color(0xFFE2E8F0) : null,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: _selectedTime.isNotEmpty
                          ? [BoxShadow(
                              color: _cyan.withValues(alpha: 0.35),
                              blurRadius: 14, offset: const Offset(0, 5))]
                          : []),
                    child: Text(
                        _selectedTime.isEmpty
                            ? 'Select a time slot'
                            : 'Use This Slot',
                        style: TextStyle(
                            color: _selectedTime.isNotEmpty ? Colors.white : _muted,
                            fontSize: 15, fontWeight: FontWeight.w900)),
                  ),
                ),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}