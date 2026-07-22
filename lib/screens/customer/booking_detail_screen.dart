import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
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

  Map<String, dynamic>? _booking;
  bool _loading = true;

  // Worker's permanent OTP (from `workers` table), fetched separately.
  String? _workerOtp;

  // OTP input state
  final _otpInputCtrl = TextEditingController();
  String? _otpError;
  bool _verifying = false;

  // Mark-work-done state
  bool _markingDone = false;

  // Extra time state
  bool _addingExtraTime = false;

  // Review popup state
  bool _reviewPromptShown = false;

  late AnimationController _successCtrl;
  late Animation<double>   _successScale;

  RealtimeChannel? _channel;
  Timer? _tickTimer;

  @override
  void initState() {
    super.initState();
    _successCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600));
    _successScale = CurvedAnimation(
        parent: _successCtrl, curve: Curves.elasticOut);

    _loadBooking();
    _subscribeRealtime();

    // Re-check the 15-minute OTP window periodically so the card
    // unlocks on its own without needing a realtime event.
    _tickTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });

    if (widget.isNew) {
      Future.delayed(const Duration(milliseconds: 300), () {
        if (mounted) _successCtrl.forward();
      });
    }
  }

  @override
  void dispose() {
    _successCtrl.dispose();
    _channel?.unsubscribe();
    _tickTimer?.cancel();
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
            addresses(label, flat_no, building, area, city, pincode),
            worker:users!worker_id(full_name, phone)
          ''')
          .eq('id', widget.bookingId)
          .single();
      if (mounted) setState(() { _booking = data; _loading = false; });
      await _loadWorkerOtp();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _maybePromptReview());
      }
    } catch (e) {
      debugPrint('booking detail load error: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  // Worker's permanent OTP lives in a separate `workers` table,
  // keyed by user_id (matching bookings.worker_id), in the
  // `worker_otp` column.
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

  // ── Status helpers ───────────────────────────────────────────
  String get _status => _booking?['status'] as String? ?? 'pending';
  int    get _extraTimeMins => (_booking?['extra_time_mins'] as num?)?.toInt() ?? 0;
  String get _paymentStatus => _booking?['payment_status'] as String? ?? 'cod';
  bool get _isInstant => (_booking?['booking_type'] as String?) == 'instant';
  bool get _hasWorker => _booking?['worker_id'] != null;

  DateTime? get _scheduledAt {
    final raw = _booking?['scheduled_at'] as String?;
    if (raw == null) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  // Instant bookings: verification opens immediately once a worker
  // is accepted. Scheduled bookings: opens 15 minutes before slot.
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
        return 'Your professional is currently working at your location.';
      case 'completed':
        return 'Service completed! We hope you loved it. Please rate your experience.';
      case 'cancelled':
        return 'This booking has been cancelled.';
      default:
        return '';
    }
  }

  // ── OTP verification ─────────────────────────────────────────
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

  // ── Mark work done (customer confirms → completes booking, frees worker) ─
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

      // Free up the worker so they can be assigned new jobs.
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

  // ── Review prompt (mandatory once booking is completed) ───────
  Future<void> _maybePromptReview() async {
    if (_status != 'completed' || _reviewPromptShown) return;
    _reviewPromptShown = true;

    try {
      final existing = await _supabase
          .from('reviews')
          .select('id')
          .eq('booking_id', widget.bookingId)
          .maybeSingle();
      if (existing != null) return; // already reviewed
    } catch (e) {
      debugPrint('review check error: $e');
      return; // fail safe — don't force a popup if the check itself errors
    }

    if (!mounted) return;
    final svc = _booking?['services'] as Map<String, dynamic>?;
    await showReviewPopup(
      context,
      bookingId: widget.bookingId,
      workerId: _booking?['worker_id'] as String?,
      serviceId: _booking?['service_id'] as String?,
      serviceName: svc?['name'] as String?,
    );
  }

  // ── Build ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
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
              if (_status == 'accepted') _buildVerifyProfessionalCard(),
              if (_status == 'accepted') const SizedBox(height: 14),
              if (_status == 'in_progress') _buildMarkDoneCard(),
              if (_status == 'in_progress') const SizedBox(height: 14),
              if (_status == 'in_progress') _buildExtraTimeCard(),
              if (_status == 'in_progress') const SizedBox(height: 14),
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

  // ── Header ───────────────────────────────────────────────────
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
            // Live indicator for active bookings
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

  // ── Success banner ───────────────────────────────────────────
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

  // ── Status card ──────────────────────────────────────────────
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
        // Progress bar
        const SizedBox(height: 16),
        _buildProgressBar(),
        // Worker info if assigned
        if (_hasWorker && _status != 'cancelled') ...[
          const SizedBox(height: 14),
          _buildWorkerRow(),
        ],
        // Instant arrival estimate
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
    final name   = worker?['full_name'] as String? ?? 'Professional';
    final phone  = worker?['phone'] as String? ?? '';
    final initials = name.trim().split(' ')
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
          Text(name, style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
          const Text('Verified Professional',
              style: TextStyle(color: _muted, fontSize: 11)),
        ])),
        if (phone.isNotEmpty)
          GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              // Could launch URL tel:phone
            },
            child: Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                color: _cyanBg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _cyanBg2)),
              child: const Icon(Icons.phone_rounded,
                  color: _cyanDk, size: 18))),
      ]),
    );
  }

  // ── Verify Professional card (replaces old "Your OTP" display) ─
  Widget _buildVerifyProfessionalCard() {
    // Window not open yet — show locked/countdown state.
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

    // Window open — show OTP input.
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

  // ── Mark Work Done card (shown while in_progress) ──────────────
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

  // ── Booking info card ────────────────────────────────────────
  Widget _buildBookingInfoCard() {
    final svc         = _booking?['services'] as Map<String, dynamic>?;
    final serviceName = svc?['name'] as String? ?? 'Service';
    final scheduledAt = _booking?['scheduled_at'] as String?;
    final bookingType = _booking?['booking_type'] as String? ?? 'schedule';
    final duration    = _booking?['booking_duration_minutes'] as int?
        ?? svc?['duration_minutes'] as int?;

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

    final rows = <Map<String, dynamic>>[
      {'icon': Icons.cleaning_services_rounded,
        'label': 'Service', 'value': serviceName},
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
      subtitle: 'Your service details',
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

  // ── Price card ───────────────────────────────────────────────
  Widget _buildPriceCard() {
    final base     = (_booking?['base_price'] as num?)?.toInt() ?? 0;
    final discount = (_booking?['discount_amount'] as num?)?.toInt() ?? 0;
    final final_   = (_booking?['final_amount'] as num?)?.toInt() ?? 0;
    final promo    = _booking?['promo_code'] as String?;

    return _card(
      icon: Icons.account_balance_wallet_rounded,
      title: 'Price Breakdown',
      subtitle: 'Payment summary',
      child: Column(children: [
        _priceRow('Service Total', '₹$base', _muted, _ink),
        if (((_booking?['extra_time_price'] as num?)?.toInt() ?? 0) > 0)
          _priceRow(
            '+20 min Extra Time',
            '₹${(_booking!['extra_time_price'] as num).toInt()}',
            _muted, const Color(0xFF7C3AED)),
        if (discount > 0)
          _priceRow(
              promo != null ? 'Promo ($promo)' : 'Discount',
              '− ₹$discount', _muted, _greenDk),
        const Divider(color: _line, height: 20),
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Total Amount',
              style: TextStyle(fontSize: 15,
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
                  ? 'Payment received ✓'
                  : 'Pay ₹$final_ cash to the worker after service',
              style: TextStyle(
                color: _paymentStatus == 'paid' ? _greenDk : _muted,
                fontSize: 12, fontWeight: FontWeight.w600))),
          ]),
        ),
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

  // ── Address card ─────────────────────────────────────────────
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

  // ── Notes card ───────────────────────────────────────────────
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

  // ── Completed card ───────────────────────────────────────────
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

  // ── Help card ────────────────────────────────────────────────
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
          onTap: () => context.go('/help'),
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

  // ── Card helper ──────────────────────────────────────────────

  // ── Extra Time Card (shown while in_progress) ─────────────────
  Widget _buildExtraTimeCard() {
    final alreadyAdded = _extraTimeMins > 0;

    return _card(
      icon: Icons.more_time_rounded,
      iconColor: const Color(0xFF7C3AED),
      iconBg: const Color(0xFFEDE9FE),
      title: 'Need More Time?',
      subtitle: 'Add 20 extra minutes if the service is still in progress',
      child: alreadyAdded
          // ── Already added: show confirmation chip ────────────
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF6EE7B7))),
              child: const Row(children: [
                Icon(Icons.check_circle_rounded,
                    color: Color(0xFF059669), size: 18),
                SizedBox(width: 10),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('+20 min added · ₹59 extra',
                      style: TextStyle(color: Color(0xFF059669),
                          fontWeight: FontWeight.w900, fontSize: 13)),
                  SizedBox(height: 2),
                  Text('Pay ₹59 extra to the worker in cash',
                      style: TextStyle(color: Color(0xFF6EE7B7),
                          fontSize: 11)),
                ])),
              ]))
          // ── Not yet added: show Add button ───────────────────
          : GestureDetector(
              onTap: _addingExtraTime ? null : _addExtraTime,
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
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.more_time_rounded,
                              color: Colors.white, size: 18),
                          SizedBox(width: 8),
                          Text('+20 min · ₹59',
                              style: TextStyle(color: Colors.white,
                                  fontWeight: FontWeight.w900, fontSize: 15)),
                          SizedBox(width: 8),
                          Text('Add Extra Time',
                              style: TextStyle(color: Colors.white70,
                                  fontSize: 13)),
                        ]),
              )),
    );
  }

  // ── Add extra time logic ────────────────────────────────────────
  Future<void> _addExtraTime() async {
    if (_addingExtraTime) return;
    setState(() => _addingExtraTime = true);

    try {
      final bookingId   = widget.bookingId;
      final currentDur  = (_booking?['booking_duration_minutes'] as num?)?.toInt() ?? 0;
      final currentFinal = (_booking?['final_amount'] as num?)?.toInt() ?? 0;

      // Update booking: +20 mins duration, +₹59 final amount,
      // set extra_time_mins = 20, extra_time_price = 59
      await _supabase.from('bookings').update({
        'extra_time_mins':         20,
        'extra_time_price':        59,
        'booking_duration_minutes': currentDur + 20,
        'final_amount':             currentFinal + 59,
      }).eq('id', bookingId);

      // Reload booking to reflect changes in UI
      await _loadBooking();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('✅ +20 min added! Pay ₹59 extra to the worker.'),
          backgroundColor: Color(0xFF059669),
          duration: Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } catch (e) {
      debugPrint('Extra time error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Failed to add extra time. Please try again.'),
          backgroundColor: Color(0xFFDC2626),
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _addingExtraTime = false);
    }
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