import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';
import 'review_popup.dart';

class BookingDetailScreen extends StatefulWidget {
  final String bookingId;
  final bool isNew;

  const BookingDetailScreen({
    super.key,
    required this.bookingId,
    this.isNew = false,
  });

  @override
  State<BookingDetailScreen> createState() => _BookingDetailScreenState();
}

class _BookingDetailScreenState extends State<BookingDetailScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  Map<String, dynamic>? _booking;
  bool _loading = true;

  bool _reviewPrompted = false;

  // OTP
  final _otpCtrl   = TextEditingController();
  final _otpFocus  = FocusNode();
  bool    _otpVerifying = false;
  bool    _otpSuccess   = false;
  String? _otpError;
  String? _workerOtp;

  // OTP animations
  late final AnimationController _caretCtrl;
  late final AnimationController _pulseCtrl;

  // ── Cyan / white palette ──────────────────────────────────────
  static const _cyan      = Color(0xFF06B6D4);
  static const _cyanDk    = Color(0xFF0891B2);
  static const _cyanDeep  = Color(0xFF0E7490);
  static const _tint      = Color(0xFFEAFBFE); // page wash
  static const _tint2     = Color(0xFFD6F6FB); // card wash
  static const _border    = Color(0xFFDDF1F5);
  static const _ink       = Color(0xFF0E2A33);
  static const _inkSoft   = Color(0xFF5B7480);
  static const _green     = Color(0xFF10B981);
  static const _red       = Color(0xFFF2545B);
  static const _amber     = Color(0xFFF59E0B);

  static const _otpAccent   = _cyan;
  static const _otpAccentDk = _cyanDk;
  static const _otpTint     = _tint2;
  static const _otpBorder   = _border;
  static const _otpInk      = _ink;
  static const _otpGreen    = _green;
  static const _otpRed      = _red;

  // Timer
  Timer? _timer;
  int _elapsedSeconds = 0;

  // Refresh timer — re-check OTP window every minute
  Timer? _windowTimer;

  static const _completedStatuses = {'completed', 'done', 'finished', 'work_done'};

  // Ordered journey for the timeline stepper
  static const _journey = [
    'pending', 'accepted', 'otp_verified', 'in_progress', 'completed'
  ];

  static const _statusColor = {
    'pending':      Color(0xFFF59E0B),
    'confirmed':    _cyan,
    'accepted':     Color(0xFF2563EB),
    'otp_verified': Color(0xFF7C3AED),
    'in_progress':  _cyanDk,
    'completed':    _green,
    'cancelled':    Color(0xFFEF4444),
  };

  static const _statusLabel = {
    'pending':      'Pending',
    'confirmed':    'Confirmed',
    'accepted':     'Worker Assigned',
    'otp_verified': 'OTP Verified',
    'in_progress':  'In Progress',
    'completed':    'Completed',
    'cancelled':    'Cancelled',
  };

  static const _stepIcons = {
    'pending':      Icons.hourglass_top_rounded,
    'accepted':     Icons.engineering_rounded,
    'otp_verified': Icons.verified_rounded,
    'in_progress':  Icons.cleaning_services_rounded,
    'completed':    Icons.task_alt_rounded,
  };

  static const _stepShortLabel = {
    'pending':      'Placed',
    'accepted':     'Assigned',
    'otp_verified': 'Verified',
    'in_progress':  'Working',
    'completed':    'Done',
  };

  @override
  void initState() {
    super.initState();
    _caretCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 600))
      ..repeat(reverse: true);
    _pulseCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2100))
      ..repeat();
    _load();
    _subscribeToBooking();
    _windowTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _windowTimer?.cancel();
    _caretCtrl.dispose();
    _pulseCtrl.dispose();
    _otpFocus.dispose();
    _otpCtrl.dispose();
    _supabase.removeAllChannels();
    super.dispose();
  }

  // ── Realtime subscription ────────────────────────────────────
  void _subscribeToBooking() {
    _supabase
        .channel('booking_${widget.bookingId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'bookings',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'id',
            value: widget.bookingId,
          ),
          callback: (payload) { if (mounted) _load(); },
        )
        .subscribe();
  }

  Future<void> _load() async {
    try {
      final data = await _supabase
          .from('bookings')
          .select('*, services(name, base_price, duration_minutes), '
              'addresses(label, flat_no, building, area, city)')
          .eq('id', widget.bookingId)
          .single();

      if (data['status'] == 'accepted' && data['worker_id'] != null) {
        await _loadWorkerOtp(data['worker_id'] as String);
      }
      if (mounted) {
        setState(() { _booking = data; _loading = false; });
        if (data['status'] == 'in_progress' &&
            data['work_started_at'] != null) {
          _startTimer(data['work_started_at'] as String);
        }
        final status = (data['status'] as String?)?.toLowerCase() ?? '';
        if (_completedStatuses.contains(status)) {
          _maybePromptReview(data);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  // ── Review prompt ────────────────────────────────────────────
  Future<void> _maybePromptReview(Map<String, dynamic> b) async {
    if (_reviewPrompted) return;
    _reviewPrompted = true;
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) { _reviewPrompted = false; return; }

    bool alreadyReviewed = false;
    try {
      final rows = await _supabase
          .from('reviews')
          .select('id')
          .eq('booking_id', widget.bookingId)
          .limit(1);
      alreadyReviewed = (rows as List).isNotEmpty;
    } catch (_) {}
    if (alreadyReviewed) return;

    if (!mounted) { _reviewPrompted = false; return; }
    await Future.delayed(const Duration(milliseconds: 400));
    if (!mounted) { _reviewPrompted = false; return; }

    final svc = b['services'] as Map<String, dynamic>?;
    final result = await showReviewPopup(
      context,
      bookingId: widget.bookingId,
      workerId:    b['worker_id']  as String?,
      serviceId:   b['service_id'] as String?,
      serviceName: svc?['name']    as String?,
    );
    if (mounted && result == true) _load();
  }

  void _startTimer(String workStartedAt) {
    _timer?.cancel();
    final start   = DateTime.parse(workStartedAt).toUtc();
    final now     = DateTime.now().toUtc();
    final elapsed = now.difference(start).inSeconds;
    _elapsedSeconds = elapsed < 0 ? 0 : elapsed;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsedSeconds++);
    });
  }

  String _formatElapsed(int secs) {
    final h = secs ~/ 3600;
    final m = (secs % 3600) ~/ 60;
    final s = secs % 60;
    if (h > 0) return '${h}h ${m.toString().padLeft(2, '0')}m';
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  // ── Load worker OTP ──────────────────────────────────────────
  Future<void> _loadWorkerOtp(String workerId) async {
    if (_workerOtp != null) return;
    try {
      final row = await _supabase
          .from('workers')
          .select('worker_otp')
          .eq('user_id', workerId)
          .maybeSingle();
      _workerOtp = row?['worker_otp']?.toString();
    } catch (_) {}
  }

  // ── OTP Time Window Check ────────────────────────────────────
  String? _otpWindowError() {
    final b = _booking;
    if (b == null) return null;
    final scheduledStr = b['scheduled_at'] as String?;
    if (scheduledStr == null) return null;

    final scheduled = DateTime.parse(scheduledStr).toUtc().toLocal();
    final now       = DateTime.now();

    final windowStart = scheduled.subtract(const Duration(minutes: 30));

    final durationMins =
        (b['services']?['duration_minutes'] as num?)?.toInt() ?? 60;
    final windowEnd = scheduled.add(Duration(minutes: durationMins));

    if (now.isBefore(windowStart)) {
      final minsUntil = windowStart.difference(now).inMinutes + 1;
      if (minsUntil >= 60) {
        final hrs  = minsUntil ~/ 60;
        final mins = minsUntil % 60;
        return mins > 0
            ? 'OTP entry opens in ${hrs}h ${mins}m'
            : 'OTP entry opens in ${hrs}h';
      }
      return 'OTP entry opens in ${minsUntil}m\n'
          '(30 min before your ${_formatTime(scheduledStr)} slot)';
    }

    if (now.isAfter(windowEnd)) {
      return 'Booking window has passed.\nPlease contact support.';
    }

    return null;
  }

  // ── Auto-verify on keystroke ─────────────────────────────────
  Future<void> _onOtpChanged(String value) async {
    setState(() => _otpError = null);
    final b = _booking;
    if (b == null) return;

    final windowErr = _otpWindowError();
    if (windowErr != null) {
      setState(() => _otpError = windowErr);
      _otpCtrl.clear();
      return;
    }

    final workerId = b['worker_id'] as String?;
    if (workerId == null) return;

    if (_workerOtp == null) {
      await _loadWorkerOtp(workerId);
      if (mounted) setState(() {});
    }
    final workerOtp = _workerOtp;

    if (workerOtp == null || workerOtp.isEmpty) {
      setState(() => _otpError = 'Worker OTP not set. Contact support.');
      return;
    }

    if (value.length < workerOtp.length) return;

    if (value != workerOtp) {
      setState(() =>
          _otpError = 'Incorrect OTP. Please check with your worker.');
      HapticFeedback.vibrate();
      return;
    }

    setState(() { _otpVerifying = true; _otpError = null; });
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('bookings').update({
        'status':          'in_progress',
        'work_started_at': now,
        'otp_verified_at': now,
      }).eq('id', widget.bookingId);
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _otpSuccess = true);
      await Future.delayed(const Duration(milliseconds: 650));
      _otpCtrl.clear();
      await _load();
      if (mounted) setState(() { _otpVerifying = false; _otpSuccess = false; });
    } catch (e) {
      setState(() {
        _otpError    = 'Failed to start. Try again.';
        _otpVerifying = false;
      });
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun',
          'Jul','Aug','Sep','Oct','Nov','Dec'];
      const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
      return '${days[d.weekday - 1]}, ${d.day} ${months[d.month - 1]} ${d.year}';
    } catch (_) { return '—'; }
  }

  String _formatTime(String? iso) {
    if (iso == null) return '—';
    try {
      final d    = DateTime.parse(iso).toLocal();
      final h    = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
      final m    = d.minute.toString().padLeft(2, '0');
      final ampm = d.hour >= 12 ? 'PM' : 'AM';
      return '$h:$m $ampm';
    } catch (_) { return '—'; }
  }

  String _formatAddress(Map<String, dynamic>? addr) {
    if (addr == null) return '—';
    return [
      if (addr['flat_no']  != null) addr['flat_no'],
      if (addr['building'] != null) addr['building'],
      addr['area'], addr['city'],
    ].where((e) => e != null).join(', ');
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _tint,
        body: Center(child: CircularProgressIndicator(color: _cyan)),
      );
    }
    if (_booking == null) {
      return Scaffold(
        backgroundColor: _tint,
        appBar: AppBar(
            title: const Text('Booking Details'),
            backgroundColor: Colors.white, elevation: 0,
            foregroundColor: _ink),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final b           = _booking!;
    final svc         = b['services']  as Map<String, dynamic>?;
    final addr        = b['addresses'] as Map<String, dynamic>?;
    final scheduledAt = b['scheduled_at']    as String?;
    final status      = b['status']          as String? ?? 'pending';
    final statusColor = _statusColor[status] ?? const Color(0xFF9CA3AF);
    final statusText  = _statusLabel[status] ?? status;
    final finalAmt    = b['final_amount'] ?? b['base_price'];
    final workerId    = b['worker_id']    as String?;
    final workStarted = b['work_started_at'] as String?;

    final windowErr  = _otpWindowError();
    final inWindow   = status == 'accepted' &&
        workerId != null && windowErr == null;
    final notYet     = status == 'accepted' &&
        workerId != null && windowErr != null &&
        windowErr.contains('opens in');
    final isCancelled = status == 'cancelled';

    return Scaffold(
      backgroundColor: _tint,
      body: Stack(children: [
        CustomScrollView(
          slivers: [
            // ── Hero header ───────────────────────────────────
            SliverToBoxAdapter(
              child: _buildHero(svc, statusColor, statusText, status, isCancelled),
            ),

            // ── Timeline ────────────────────────────────────
            if (!isCancelled)
              SliverToBoxAdapter(child: _buildTimeline(status)),

            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 140),
                child: Column(children: [

                  if (widget.isNew) _buildBanner(
                    emoji: '🎉', title: 'Booking Confirmed!',
                    sub: 'Your booking is placed. A worker will be assigned soon.',
                    bg1: const Color(0xFFECFDF5), bg2: const Color(0xFFD1FAE5),
                    border: const Color(0xFF6EE7B7), titleColor: const Color(0xFF065F46),
                    subColor: const Color(0xFF047857)),

                  if (status == 'pending') _buildBanner(
                    emoji: '⏳', title: 'Waiting for Worker',
                    sub: 'Admin is assigning a worker to your booking.',
                    bg1: const Color(0xFFFFFBEB), bg2: const Color(0xFFFFFBEB),
                    border: const Color(0xFFFDE68A), titleColor: const Color(0xFF92400E),
                    subColor: const Color(0xFFB45309)),

                  if (notYet) _buildWaitingCard(windowErr!),

                  if (inWindow) _buildOtpCard(),

                  if (status == 'in_progress' && workStarted != null)
                    _buildInProgressCard(workStarted),

                  if (status == 'completed')
                    _buildCompletedSection(b),

                  // ── Trip card (merged info) ────────────────
                  _buildTripCard(svc, scheduledAt, addr, status),

                  const SizedBox(height: 8),
                ]),
              ),
            ),
          ],
        ),

        // ── Sticky bottom bar ───────────────────────────────
        Positioned(
          left: 0, right: 0, bottom: 0,
          child: _buildBottomBar(finalAmt),
        ),
      ]),
    );
  }

  // ── Hero header ────────────────────────────────────────────
  Widget _buildHero(Map<String, dynamic>? svc, Color statusColor,
      String statusText, String status, bool isCancelled) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [_cyan, _cyanDeep]),
      ),
      child: Stack(children: [
        // decorative glow
        Positioned(
          top: -40, right: -30,
          child: Container(
            width: 160, height: 160,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        Positioned(
          bottom: -60, left: -20,
          child: Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.06)),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 26),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () => Navigator.canPop(context)
                      ? Navigator.pop(context)
                      : context.go('/bookings'),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      borderRadius: BorderRadius.circular(13),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(
                      width: 7, height: 7,
                      decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(statusText,
                        style: TextStyle(color: _cyanDeep,
                            fontSize: 12, fontWeight: FontWeight.w800)),
                  ]),
                ),
              ]),
              const SizedBox(height: 22),
              Text(svc?['name'] as String? ?? 'Service Booking',
                  style: const TextStyle(color: Colors.white,
                      fontSize: 22, fontWeight: FontWeight.w900)),
              const SizedBox(height: 4),
              Text('Booking #${widget.bookingId.substring(0, 8).toUpperCase()}',
                  style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.78), fontSize: 12.5,
                      letterSpacing: 0.4)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Timeline stepper ──────────────────────────────────────
  Widget _buildTimeline(String status) {
    final idx = _journey.indexOf(status);
    final activeIdx = idx < 0 ? 0 : idx;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 6),
      padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: _cyan.withValues(alpha: 0.08),
            blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: List.generate(_journey.length, (i) {
          final key   = _journey[i];
          final done  = i < activeIdx;
          final cur   = i == activeIdx;
          final color = done || cur ? _cyan : const Color(0xFFE2E8F0);

          return Expanded(
            child: Row(children: [
              Expanded(
                child: Column(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    width: cur ? 38 : 32, height: cur ? 38 : 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: done ? _cyan
                          : cur ? Colors.white : const Color(0xFFF1F5F9),
                      border: Border.all(
                          color: color, width: cur ? 2.4 : 1.6),
                      boxShadow: cur ? [BoxShadow(
                          color: _cyan.withValues(alpha: 0.35),
                          blurRadius: 10, offset: const Offset(0, 3))] : [],
                    ),
                    child: Icon(
                      done ? Icons.check_rounded : _stepIcons[key],
                      size: cur ? 18 : 15,
                      color: done ? Colors.white
                          : cur ? _cyan : const Color(0xFFB6C2CB)),
                  ),
                  const SizedBox(height: 6),
                  Text(_stepShortLabel[key] ?? '',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: cur ? FontWeight.w800 : FontWeight.w600,
                        color: cur ? _cyanDeep
                            : done ? _inkSoft : const Color(0xFFB6C2CB))),
                ]),
              ),
              if (i < _journey.length - 1)
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Container(
                    width: 14, height: 2,
                    color: done ? _cyan : const Color(0xFFE2E8F0)),
                ),
            ]),
          );
        }),
      ),
    );
  }

  Widget _buildBanner({
    required String emoji, required String title, required String sub,
    required Color bg1, required Color bg2, required Color border,
    required Color titleColor, required Color subColor,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [bg1, bg2]),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
      ),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: TextStyle(color: titleColor,
              fontWeight: FontWeight.w900, fontSize: 14.5)),
          const SizedBox(height: 2),
          Text(sub, style: TextStyle(color: subColor, fontSize: 12, height: 1.3)),
        ])),
      ]),
    );
  }

  Widget _buildWaitingCard(String windowErr) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(
            color: _cyan.withValues(alpha: 0.06), blurRadius: 14,
            offset: const Offset(0, 4))],
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: _tint2, borderRadius: BorderRadius.circular(14)),
          child: const Center(child: Text('🕐', style: TextStyle(fontSize: 24))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Worker Assigned ✓',
              style: TextStyle(color: _cyanDeep,
                  fontWeight: FontWeight.w900, fontSize: 14)),
          const SizedBox(height: 4),
          Text(windowErr,
              style: const TextStyle(color: _inkSoft, fontSize: 12, height: 1.4)),
        ])),
      ]),
    );
  }

  Widget _buildInProgressCard(String workStarted) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_cyan, _cyanDeep]),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: _cyan.withValues(alpha: 0.32),
            blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        Row(children: [
          Container(
            width: 44, height: 44,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(14)),
            child: const Center(child: Text('🧹', style: TextStyle(fontSize: 22))),
          ),
          const SizedBox(width: 14),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Work In Progress',
                style: TextStyle(color: Colors.white,
                    fontSize: 15, fontWeight: FontWeight.w900)),
            SizedBox(height: 2),
            Text('Your cleaner is working right now',
                style: TextStyle(color: Color(0xFFD6F6FB), fontSize: 12)),
          ])),
          _liveDot(),
        ]),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text(_formatElapsed(_elapsedSeconds),
                style: const TextStyle(
                  color: Colors.white, fontSize: 40,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace', letterSpacing: 2)),
            const SizedBox(height: 4),
            Text('Started at ${_formatTime(workStarted)}',
                style: const TextStyle(color: Color(0xFFD6F6FB), fontSize: 12)),
          ]),
        ),
      ]),
    );
  }

  Widget _buildCompletedSection(Map<String, dynamic> b) {
    return Column(children: [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFF6EE7B7)),
        ),
        child: Row(children: [
          const Text('✅', style: TextStyle(fontSize: 28)),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Work Completed!',
                style: TextStyle(color: Color(0xFF065F46),
                    fontWeight: FontWeight.w900, fontSize: 15)),
            const SizedBox(height: 2),
            if (b['work_started_at'] != null && b['work_ended_at'] != null)
              Text(
                'Duration: ${_formatElapsed(DateTime.parse(b['work_ended_at']).difference(DateTime.parse(b['work_started_at'])).inSeconds)}',
                style: const TextStyle(color: Color(0xFF047857), fontSize: 12),
              ),
          ])),
        ]),
      ),
      GestureDetector(
        onTap: () { _reviewPrompted = false; _maybePromptReview(b); },
        child: Container(
          margin: const EdgeInsets.only(bottom: 14),
          height: 52,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _cyan, width: 1.6),
            boxShadow: [BoxShadow(
                color: _cyan.withValues(alpha: 0.10), blurRadius: 10,
                offset: const Offset(0, 3))],
          ),
          child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.star_rounded, color: _amber, size: 20),
            SizedBox(width: 8),
            Text('Rate this service',
                style: TextStyle(color: _cyanDk,
                    fontWeight: FontWeight.w800, fontSize: 14)),
          ]),
        ),
      ),
    ]);
  }

  // ── Merged trip card ──────────────────────────────────────
  Widget _buildTripCard(Map<String, dynamic>? svc, String? scheduledAt,
      Map<String, dynamic>? addr, String status) {
    final rows = [
      ('🧹', 'Service', svc?['name'] as String? ?? '—'),
      ('📅', 'Date', _formatDate(scheduledAt)),
      ('⏰', 'Time', _formatTime(scheduledAt)),
      ('📍', 'Address', _formatAddress(addr)),
    ];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: _cyan.withValues(alpha: 0.07),
            blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
          child: Row(children: [
            Container(
              width: 34, height: 34,
              decoration: BoxDecoration(
                  color: _tint2, borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.receipt_long_rounded,
                  color: _cyanDk, size: 18)),
            const SizedBox(width: 10),
            const Text('Booking Summary',
                style: TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 14.5, color: _ink)),
          ]),
        ),
        for (int i = 0; i < rows.length; i++) ...[
          if (i > 0)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 18),
              child: Divider(height: 1, color: Color(0xFFF1F5F9)),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(children: [
              SizedBox(width: 26, child: Text(rows[i].$1,
                  style: const TextStyle(fontSize: 16))),
              const SizedBox(width: 8),
              Text(rows[i].$2, style: const TextStyle(
                  color: _inkSoft, fontSize: 12.5, fontWeight: FontWeight.w600)),
              const Spacer(),
              Flexible(child: Text(rows[i].$3, textAlign: TextAlign.right,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800,
                      fontSize: 13.5, color: _ink))),
            ]),
          ),
        ],
        const SizedBox(height: 4),
      ]),
    );
  }

  // ── Sticky bottom bar ──────────────────────────────────────
  Widget _buildBottomBar(dynamic finalAmt) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(18, 14, 18, 14 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22, offset: const Offset(0, -6))],
      ),
      child: Row(children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Total Amount',
              style: TextStyle(color: _inkSoft, fontSize: 11.5,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text('₹${finalAmt ?? '—'}',
              style: const TextStyle(color: _ink, fontSize: 24,
                  fontWeight: FontWeight.w900)),
        ])),
        GestureDetector(
          onTap: () => context.go('/bookings'),
          child: Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
              borderRadius: BorderRadius.circular(16),
              boxShadow: [BoxShadow(
                  color: _cyan.withValues(alpha: 0.38),
                  blurRadius: 14, offset: const Offset(0, 5))],
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.receipt_long_outlined, color: Colors.white, size: 18),
              SizedBox(width: 9),
              Text('All Bookings',
                  style: TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 14.5)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── OTP Card ─────────────────────────────────────────────────
  Widget _buildOtpCard() {
    final otpLen = (_workerOtp != null && _workerOtp!.isNotEmpty)
        ? _workerOtp!.length.clamp(4, 6)
        : 4;
    final boxW   = otpLen <= 4 ? 60.0 : 46.0;
    final fontSz = otpLen <= 4 ? 26.0 : 22.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _otpError != null ? const Color(0xFFFCA5A5) : _border),
        boxShadow: [BoxShadow(
            color: _cyan.withValues(alpha: 0.10),
            blurRadius: 20, offset: const Offset(0, 8))],
      ),
      child: Column(children: [
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [_tint, _tint2]),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(22), topRight: Radius.circular(22)),
          ),
          child: Row(children: [
            Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [_otpAccent, _otpAccentDk]),
                borderRadius: BorderRadius.circular(15),
                boxShadow: [BoxShadow(
                    color: _otpAccent.withValues(alpha: 0.38),
                    blurRadius: 14, offset: const Offset(0, 6))],
              ),
              child: const Icon(Icons.vpn_key_rounded, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 13),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Worker has arrived!',
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5,
                        color: _otpInk, letterSpacing: 0.2)),
                const SizedBox(width: 9),
                _liveDot(),
              ]),
              const SizedBox(height: 4),
              Text('Enter the $otpLen-digit code your worker gives you',
                  style: const TextStyle(color: _inkSoft,
                      fontSize: 12.5, fontWeight: FontWeight.w500)),
            ])),
          ]),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(children: [
            SizedBox(
              height: 64,
              child: Stack(children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_otpCtrl, _otpFocus]),
                    builder: (context, _) {
                      final text    = _otpCtrl.text;
                      final focused = _otpFocus.hasFocus;
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          for (int i = 0; i < otpLen; i++) ...[
                            if (i > 0) const SizedBox(width: 10),
                            _otpBox(i, text, focused, boxW, fontSz),
                          ],
                        ],
                      );
                    },
                  ),
                ),
                Positioned.fill(
                  child: Opacity(
                    opacity: 0.0,
                    child: TextField(
                      controller: _otpCtrl,
                      focusNode: _otpFocus,
                      keyboardType: TextInputType.number,
                      enabled: !_otpVerifying && !_otpSuccess,
                      onChanged: _onOtpChanged,
                      showCursor: false,
                      cursorWidth: 0,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(otpLen),
                      ],
                      decoration: const InputDecoration(
                          counterText: '', border: InputBorder.none),
                    ),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _otpStatusLine(),
            if (_otpError != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline_rounded,
                      color: Color(0xFFDC2626), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_otpError!,
                      style: const TextStyle(color: Color(0xFFDC2626),
                          fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _otpBox(int i, String text, bool focused, double boxW, double fontSz) {
    final filled   = i < text.length;
    final isActive = focused && i == text.length &&
        !_otpVerifying && !_otpSuccess && _otpError == null;
    final hasError = _otpError != null;

    Color borderColor, bgColor, textColor;
    if (_otpSuccess) {
      borderColor = _otpGreen; bgColor = const Color(0xFFE9FBF3); textColor = _otpGreen;
    } else if (hasError) {
      borderColor = _otpRed; bgColor = const Color(0xFFFFF3F4); textColor = _otpRed;
    } else if (isActive) {
      borderColor = _otpAccent; bgColor = Colors.white; textColor = _otpAccent;
    } else if (filled) {
      borderColor = _otpAccent; bgColor = _otpTint; textColor = _otpAccentDk;
    } else {
      borderColor = _otpBorder; bgColor = const Color(0xFFFBFCFE); textColor = _otpInk;
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOut,
      width: boxW, height: 64,
      alignment: Alignment.center,
      transform: isActive
          ? (Matrix4.identity()..translate(0.0, -2.0))
          : Matrix4.identity(),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: borderColor, width: 1.6),
        boxShadow: isActive
            ? [
                BoxShadow(color: _otpAccent.withValues(alpha: 0.18),
                    blurRadius: 18, offset: const Offset(0, 8)),
                BoxShadow(color: _otpAccent.withValues(alpha: 0.14),
                    blurRadius: 0, spreadRadius: 3),
              ]
            : const [],
      ),
      child: filled
          ? TweenAnimationBuilder<double>(
              key: ValueKey('otp_${i}_${text[i]}'),
              tween: Tween(begin: 0.6, end: 1.0),
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              builder: (_, v, child) => Transform.scale(scale: v, child: child),
              child: Text(text[i],
                  style: TextStyle(fontSize: fontSz,
                      fontWeight: FontWeight.w900, color: textColor)),
            )
          : (isActive
              ? FadeTransition(
                  opacity: _caretCtrl,
                  child: Container(
                    width: 2, height: 28,
                    decoration: BoxDecoration(
                      color: _otpAccent, borderRadius: BorderRadius.circular(2)),
                  ),
                )
              : const SizedBox.shrink()),
    );
  }

  Widget _liveDot() {
    return SizedBox(
      width: 9, height: 9,
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          final t = _pulseCtrl.value;
          return Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
            Opacity(
              opacity: (1 - t) * 0.6,
              child: Transform.scale(
                scale: 1 + t * 1.8,
                child: Container(
                  width: 9, height: 9,
                  decoration: const BoxDecoration(
                      color: Color(0xFF22C55E), shape: BoxShape.circle)),
              ),
            ),
            Container(
              width: 7, height: 7,
              decoration: const BoxDecoration(
                  color: Color(0xFF22C55E), shape: BoxShape.circle)),
          ]);
        },
      ),
    );
  }

  Widget _otpStatusLine() {
    if (_otpSuccess) {
      return const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.check_circle_rounded, color: _otpGreen, size: 16),
        SizedBox(width: 7),
        Text('Verified — work has started',
            style: TextStyle(fontSize: 12, color: _otpGreen, fontWeight: FontWeight.w700)),
      ]);
    }
    if (_otpVerifying) {
      return const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: _otpAccent)),
        SizedBox(width: 9),
        Text('Verifying code…',
            style: TextStyle(fontSize: 12, color: _otpAccent, fontWeight: FontWeight.w600)),
      ]);
    }
    return const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
      SizedBox(width: 5, height: 5,
          child: DecoratedBox(decoration: BoxDecoration(
              color: _otpAccent, shape: BoxShape.circle))),
      SizedBox(width: 8),
      Text('Work starts automatically once the code is verified',
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
    ]);
  }
}