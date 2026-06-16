import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';

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

  // OTP
  final _otpCtrl = TextEditingController();
  final _otpFocus = FocusNode();
  bool _otpVerifying = false;
  bool _otpSuccess = false; // brief "verified" state before reload
  String? _otpError;
  String? _workerOtp; // cached worker OTP

  // OTP animations
  late final AnimationController _caretCtrl; // blinking cursor in active box
  late final AnimationController _pulseCtrl; // "live" dot in OTP header

  // ── OTP section palette — CYAN to match the app theme ──
  static const _otpAccent   = Color(0xFF06B6D4); // primary accent
  static const _otpAccentDk = Color(0xFF0891B2); // gradient end
  static const _otpTint     = Color(0xFFE0F7FB); // filled box wash
  static const _otpBorder   = Color(0xFFDDE7EC); // idle border
  static const _otpInk      = Color(0xFF0E2A33); // heading text
  static const _otpGreen    = Color(0xFF10B981); // verified
  static const _otpRed      = Color(0xFFF2545B); // error

  // Timer
  Timer? _timer;
  int _elapsedSeconds = 0;

  static const _statusColor = {
    'pending':      Color(0xFFF59E0B),
    'confirmed':    Color(0xFF06B6D4),
    'accepted':     Color(0xFF2563EB),
    'otp_verified': Color(0xFF7C3AED),
    'in_progress':  Color(0xFF3B82F6),
    'completed':    Color(0xFF10B981),
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
  }

  @override
  void dispose() {
    _timer?.cancel();
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
          .select('*, services(name, base_price), addresses(label, flat_no, building, area, city)')
          .eq('id', widget.bookingId)
          .single();
      // Preload worker OTP for accepted bookings so we know how many
      // input boxes to render (OTP length is variable).
      if (data['status'] == 'accepted' && data['worker_id'] != null) {
        await _loadWorkerOtp(data['worker_id'] as String);
      }
      if (mounted) {
        setState(() { _booking = data; _loading = false; });
        if ((data['status'] == 'in_progress') && data['work_started_at'] != null) {
          _startTimer(data['work_started_at'] as String);
        }
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _startTimer(String workStartedAt) {
    _timer?.cancel();
    final start = DateTime.parse(workStartedAt).toUtc();
    final elapsed = DateTime.now().toUtc().difference(start).inSeconds;
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

  // ── Load worker OTP once and cache ───────────────────────────
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

  // ── Auto-verify on each keystroke — no button needed ────────
  Future<void> _onOtpChanged(String value) async {
    setState(() => _otpError = null);
    final b = _booking;
    if (b == null) return;
    final workerId = b['worker_id'] as String?;
    if (workerId == null) return;

    if (_workerOtp == null) {
      await _loadWorkerOtp(workerId);
      // OTP length may now be known — refresh box count.
      if (mounted) setState(() {});
    }
    final workerOtp = _workerOtp;

    if (workerOtp == null || workerOtp.isEmpty) {
      setState(() => _otpError = 'Worker OTP not set. Contact support.');
      return;
    }

    if (value.length < workerOtp.length) return;

    if (value != workerOtp) {
      setState(() => _otpError = 'Incorrect OTP. Please check with your worker.');
      HapticFeedback.vibrate();
      return;
    }

    // ✅ Correct — auto start
    setState(() { _otpVerifying = true; _otpError = null; });
    try {
      final now = DateTime.now().toUtc().toIso8601String();
      await _supabase.from('bookings').update({
        'status':          'in_progress',
        'work_started_at': now,
        'otp_verified_at': now,
      }).eq('id', widget.bookingId);
      HapticFeedback.mediumImpact();
      // Brief success flash before the card swaps to the in-progress banner.
      if (mounted) setState(() => _otpSuccess = true);
      await Future.delayed(const Duration(milliseconds: 650));
      _otpCtrl.clear();
      await _load();
      if (mounted) setState(() { _otpVerifying = false; _otpSuccess = false; });
    } catch (e) {
      setState(() { _otpError = 'Failed to start. Try again.'; _otpVerifying = false; });
    }
  }

  String _formatDate(String? iso) {
    if (iso == null) return '—';
    try {
      final d = DateTime.parse(iso).toLocal();
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      const days   = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
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
        backgroundColor: Color(0xFFF5F5F7),
        body: Center(child: CircularProgressIndicator(color: AppTheme.primary)),
      );
    }
    if (_booking == null) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F7),
        appBar: AppBar(title: const Text('Booking Details'), backgroundColor: Colors.white, elevation: 0),
        body: const Center(child: Text('Booking not found')),
      );
    }

    final b           = _booking!;
    final svc         = b['services']  as Map<String, dynamic>?;
    final addr        = b['addresses'] as Map<String, dynamic>?;
    final scheduledAt = b['scheduled_at'] as String?;
    final status      = b['status']    as String? ?? 'pending';
    final statusColor = _statusColor[status] ?? const Color(0xFF9CA3AF);
    final statusText  = _statusLabel[status] ?? status;
    final finalAmt    = b['final_amount'] ?? b['base_price'];
    final workerId    = b['worker_id']    as String?;
    final workStarted = b['work_started_at'] as String?;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Column(children: [

        // ── Header ────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.canPop(context) ? Navigator.pop(context) : context.go('/bookings'),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(child: Text('Booking Details',
                    style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                  ),
                  child: Text(statusText,
                      style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),
          ),
        ),

        Expanded(
          child: RefreshIndicator(
            onRefresh: _load,
            color: AppTheme.primary,
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [

                // ── New booking banner ─────────────────────────
                if (widget.isNew) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF6EE7B7)),
                    ),
                    child: const Row(children: [
                      Text('🎉', style: TextStyle(fontSize: 28)),
                      SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('Booking Confirmed!',
                            style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w900, fontSize: 15)),
                        SizedBox(height: 2),
                        Text('Your booking is placed. A worker will be assigned soon.',
                            style: TextStyle(color: Color(0xFF047857), fontSize: 12)),
                      ])),
                    ]),
                  ),
                ],

                // ── Work In Progress Banner + Timer ────────────
                if (status == 'in_progress' && workStarted != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)]),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [BoxShadow(
                          color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                          blurRadius: 16, offset: const Offset(0, 4))],
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
                        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text('Work In Progress',
                              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                          SizedBox(height: 2),
                          Text('Your cleaner is working right now',
                              style: TextStyle(color: Color(0xFFBFDBFE), fontSize: 12)),
                        ])),
                        Container(width: 10, height: 10,
                            decoration: const BoxDecoration(color: Color(0xFF4ADE80), shape: BoxShape.circle)),
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
                              style: const TextStyle(color: Color(0xFFBFDBFE), fontSize: 12)),
                        ]),
                      ),
                    ]),
                  ),
                ],

                // ── OTP Entry (accepted + worker assigned) ─────
                if (status == 'accepted' && workerId != null) ...[
                  _buildOtpCard(),
                ],

                // ── Completed banner ───────────────────────────
                if (status == 'completed') ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 16),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF6EE7B7)),
                    ),
                    child: Row(children: [
                      const Text('✅', style: TextStyle(fontSize: 28)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        const Text('Work Completed!',
                            style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w900, fontSize: 15)),
                        const SizedBox(height: 2),
                        if (b['work_started_at'] != null && b['work_ended_at'] != null)
                          Text(
                            'Duration: ${_formatElapsed(DateTime.parse(b['work_ended_at']).difference(DateTime.parse(b['work_started_at'])).inSeconds)}',
                            style: const TextStyle(color: Color(0xFF047857), fontSize: 12),
                          ),
                      ])),
                    ]),
                  ),
                ],

                // ── Info cards ─────────────────────────────────
                _infoCard(icon: '🧹', label: 'Service',
                    value: svc?['name'] ?? '—', bgColor: const Color(0xFFECFEFF)),
                Row(children: [
                  Expanded(child: _infoCard(icon: '📅', label: 'Date',
                      value: _formatDate(scheduledAt), bgColor: const Color(0xFFF0F9FF))),
                  const SizedBox(width: 12),
                  Expanded(child: _infoCard(icon: '⏰', label: 'Time',
                      value: _formatTime(scheduledAt), bgColor: const Color(0xFFF5F3FF))),
                ]),
                _infoCard(icon: '📍', label: 'Address',
                    value: _formatAddress(addr), bgColor: const Color(0xFFFFF7ED)),

                // ── Price card ─────────────────────────────────
                Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Total Amount',
                          style: TextStyle(color: Color(0xFFBAE6FD), fontSize: 12, fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Inclusive of all charges',
                          style: TextStyle(color: Color(0xFF7DD3FC), fontSize: 11)),
                    ]),
                    Text('₹${finalAmt ?? '—'}',
                        style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
                  ]),
                ),

                const SizedBox(height: 8),
                GestureDetector(
                  onTap: () => context.go('/bookings'),
                  child: Container(
                    height: 54,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: [BoxShadow(
                          color: AppTheme.primary.withValues(alpha: 0.4),
                          blurRadius: 16, offset: const Offset(0, 6))],
                    ),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Icon(Icons.receipt_long_outlined, color: Colors.white, size: 20),
                      SizedBox(width: 10),
                      Text('View All Bookings',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                    ]),
                  ),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }

  // ════════════════════════════════════════════════════════════
  //  OTP CARD  (UI only — verification stays in _onOtpChanged)
  // ════════════════════════════════════════════════════════════
  Widget _buildOtpCard() {
    final otpLen = (_workerOtp != null && _workerOtp!.isNotEmpty)
        ? _workerOtp!.length.clamp(4, 6)
        : 4;
    final boxW   = otpLen <= 4 ? 60.0 : 46.0;
    final fontSz = otpLen <= 4 ? 26.0 : 22.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: _otpError != null ? const Color(0xFFFCA5A5) : const Color(0xFFEEF1F6)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 18, offset: const Offset(0, 6))],
      ),
      child: Column(children: [

        // ── Header strip ──────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFFECFEFF), Color(0xFFCFFAFE)]),
            borderRadius: BorderRadius.only(
              topLeft: Radius.circular(22), topRight: Radius.circular(22)),
          ),
          child: Row(children: [
            // Cyan gradient key icon
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
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Text('Professional has arrived',
                    style: TextStyle(
                      fontWeight: FontWeight.w900, fontSize: 16.5,
                      color: _otpInk, letterSpacing: 0.2)),
                const SizedBox(width: 9),
                _liveDot(),
              ]),
              const SizedBox(height: 4),
              Text('Enter the $otpLen-digit code your Professioanl shares',
                  style: const TextStyle(
                      color: Color(0xFF52666E), fontSize: 12.5, fontWeight: FontWeight.w500)),
            ])),
          ]),
        ),

        // ── Boxes + status ────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 18, 16, 16),
          child: Column(children: [

            // The boxes: visible row + transparent capture field
            SizedBox(
              height: 64,
              child: Stack(children: [
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: Listenable.merge([_otpCtrl, _otpFocus]),
                    builder: (context, _) {
                      final text = _otpCtrl.text;
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
                  const Icon(Icons.error_outline_rounded, color: Color(0xFFDC2626), size: 16),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_otpError!,
                      style: const TextStyle(
                        color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  // One OTP box
  Widget _otpBox(int i, String text, bool focused, double boxW, double fontSz) {
    final filled   = i < text.length;
    final isActive = focused && i == text.length && !_otpVerifying && !_otpSuccess && _otpError == null;
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
                  style: TextStyle(fontSize: fontSz, fontWeight: FontWeight.w900, color: textColor)),
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

  // Animated "live" dot — signals the worker is here right now
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

  // Status line below the boxes
  Widget _otpStatusLine() {
    if (_otpSuccess) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
        Icon(Icons.check_circle_rounded, color: _otpGreen, size: 16),
        SizedBox(width: 7),
        Text('Verified — work has started',
            style: TextStyle(fontSize: 12, color: _otpGreen, fontWeight: FontWeight.w700)),
      ]);
    }
    if (_otpVerifying) {
      return Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
        SizedBox(width: 14, height: 14,
            child: CircularProgressIndicator(strokeWidth: 2.2, color: _otpAccent)),
        SizedBox(width: 9),
        Text('Verifying code…',
            style: TextStyle(fontSize: 12, color: _otpAccent, fontWeight: FontWeight.w600)),
      ]);
    }
    return Row(mainAxisAlignment: MainAxisAlignment.center, children: const [
      SizedBox(width: 5, height: 5,
          child: DecoratedBox(decoration: BoxDecoration(color: _otpAccent, shape: BoxShape.circle))),
      SizedBox(width: 8),
      Text('Work starts automatically once the code is verified',
          style: TextStyle(fontSize: 11, color: Color(0xFF9CA3AF))),
    ]);
  }

  Widget _infoCard({required String icon, required String label,
      required String value, required Color bgColor}) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F0F0)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8)],
      ),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(13)),
          child: Center(child: Text(icon, style: const TextStyle(fontSize: 20))),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(label, style: const TextStyle(
              color: Color(0xFF9CA3AF), fontSize: 11,
              fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          const SizedBox(height: 3),
          Text(value, style: const TextStyle(
              fontWeight: FontWeight.w700, fontSize: 14, color: Color(0xFF111827))),
        ])),
      ]),
    );
  }
}