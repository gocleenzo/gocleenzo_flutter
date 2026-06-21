import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';
import 'booking_detail_screen.dart';

class BookingFlowScreen extends StatefulWidget {
  final String  mode;
  final String? serviceId;
  final List<Map<String, dynamic>>? cartItems;

  final int?    overridePrice;
  final int?    overrideDuration;
  final String? selectedBhk;
  final int?    quantity;
  final bool    isFirstBooking;

  const BookingFlowScreen({
    super.key,
    required this.mode,
    this.serviceId,
    this.cartItems,
    this.overridePrice,
    this.overrideDuration,
    this.selectedBhk,
    this.quantity,
    this.isFirstBooking = false,
  });

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  final _supabase = Supabase.instance.client;
  late Razorpay _razorpay;

  // ── Cyan / white palette (matches BookingDetailScreen) ────────
  static const _cyan     = Color(0xFF06B6D4);
  static const _cyanDk   = Color(0xFF0891B2);
  static const _cyanDeep = Color(0xFF0E7490);
  static const _tint     = Color(0xFFEAFBFE);
  static const _tint2    = Color(0xFFD6F6FB);
  static const _border   = Color(0xFFDDF1F5);
  static const _ink      = Color(0xFF0E2A33);
  static const _inkSoft  = Color(0xFF5B7480);
  static const _instant1 = Color(0xFF10B981);
  static const _instant2 = Color(0xFF059669);

  int  _step    = 1;
  bool _loading = false;

  DateTime _selectedDate = DateTime.now();
  String   _selectedTime = '';

  List<Map<String, dynamic>> _addresses         = [];
  String                     _selectedAddressId = '';

  List<Map<String, dynamic>> _promos       = [];
  List<Map<String, dynamic>> _usedPromos   = [];
  Set<String>                _usedPromoIds = {};
  bool   _promosLoading    = false;
  String _appliedPromoId   = '';
  String _appliedPromoCode = '';
  int    _discount         = 0;

  final _notesCtrl = TextEditingController();

  Map<String, dynamic>? _service;

  String _pendingBookingId = '';

  Map<String, bool> _slotAvailability = {};
  bool _slotsLoading = false;

  bool get _isSchedule  => widget.mode == 'schedule';
  bool get _isInstant   => widget.mode == 'instant';
  int  get _totalSteps  => _isSchedule ? 3 : 2;
  int  get _addressStep => _isSchedule ? 2 : 1;
  int  get _confirmStep => _isSchedule ? 3 : 2;

  List<String> get _stepLabels => _isSchedule
      ? ['Date & Time', 'Address', 'Confirm']
      : ['Address', 'Confirm'];

  static const List<IconData> _stepIcons = [
    Icons.event_rounded, Icons.location_on_rounded, Icons.task_alt_rounded
  ];

  static const _timeSlots = [
    '07:00 AM','08:00 AM','09:00 AM','10:00 AM','11:00 AM',
    '12:00 PM','01:00 PM','02:00 PM','03:00 PM',
    '04:00 PM','05:00 PM','06:00 PM','07:00 PM',
  ];

  List<DateTime> get _dates =>
      List.generate(7, (i) => DateTime.now().add(Duration(days: i)));

  int get _baseAmount {
    if (widget.isFirstBooking) return 25;
    if (widget.overridePrice != null) return widget.overridePrice!;
    if (widget.cartItems != null) {
      return widget.cartItems!.fold(
          0, (s, c) => s + (c['price'] as num).toInt() * (c['quantity'] as num).toInt());
    }
    return (_service?['base_price'] as num?)?.toInt() ?? 0;
  }

  int get _finalAmount => (_baseAmount - _discount).clamp(0, 999999);

  int get _serviceDurationMins {
    if (widget.overrideDuration != null) return widget.overrideDuration!;
    final raw = (_service?['duration_minutes'] as num?)?.toInt() ?? 60;
    return (raw / 60).ceil() * 60;
  }

  int get _slotsBlocked => (_serviceDurationMins / 60).ceil();

  String? get _userId => _supabase.auth.currentUser?.id;

  String get _serviceLabel {
    if (widget.cartItems != null) {
      return '${widget.cartItems!.length} service${widget.cartItems!.length > 1 ? 's' : ''}';
    }
    final name = _service?['name'] as String? ?? '—';
    if (widget.selectedBhk != null) return '$name · ${widget.selectedBhk}';
    if (widget.quantity != null && widget.quantity! > 1) return '$name · ×${widget.quantity}';
    return name;
  }

  @override
  void initState() {
    super.initState();
    _initRazorpay();
    _loadData();
    if (_isInstant) _step = 1;
  }

  @override
  void dispose() {
    _razorpay.clear();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Razorpay ─────────────────────────────────────────────────
  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,   _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _loading = true);
    try {
      await _supabase.from('bookings').update({
        'payment_status':      'paid',
        'payment_id':          response.paymentId,
        'razorpay_order_id':   response.orderId,
        'payment_method':      'razorpay',
        'payment_captured_at': DateTime.now().toIso8601String(),
        'status':              'pending',
      }).eq('id', _pendingBookingId);

      if (_appliedPromoId.isNotEmpty && _userId != null) {
        try {
          await _supabase.from('promo_usage').insert({
            'promo_id': _appliedPromoId,
            'user_id':  _userId!,
          });
          final p = _promos.firstWhere(
              (p) => p['id'].toString() == _appliedPromoId,
              orElse: () => {'used_count': 0});
          await _supabase.from('promo_codes').update({
            'used_count': ((p['used_count'] as num? ?? 0).toInt() + 1),
          }).eq('id', _appliedPromoId);
        } catch (e) { debugPrint('promo usage skipped: $e'); }
      }

      if (mounted) {
        setState(() => _loading = false);
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => BookingDetailScreen(
              bookingId: _pendingBookingId, isNew: true),
        ));
      }
    } catch (e) {
      setState(() => _loading = false);
      _showSnack('Payment captured but booking update failed. Contact support.',
          isError: true);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _loading = false);
    if (_pendingBookingId.isNotEmpty) {
      _supabase.from('bookings').delete().eq('id', _pendingBookingId).then((_) {
        _pendingBookingId = '';
      });
    }
    _showSnack('Payment failed: ${response.message ?? 'Try again'}',
        isError: true);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _showSnack('External wallet: ${response.walletName}');
  }

  // ── Load data ────────────────────────────────────────────────
  Future<void> _loadData() async {
    final user = _supabase.auth.currentUser;
    if (user == null) { if (mounted) context.go('/login'); return; }

    final futures = <Future>[
      _supabase.from('addresses').select('*').eq('user_id', user.id),
    ];
    if (widget.serviceId != null) {
      futures.add(_supabase.from('services')
          .select('id,name,base_price,duration_minutes')
          .eq('id', widget.serviceId!).single());
    }

    final results = await Future.wait(futures);
    if (!mounted) return;

    setState(() {
      _addresses = (results[0] as List).cast<Map<String, dynamic>>();
      if (_addresses.isNotEmpty) {
        final def = _addresses.firstWhere(
            (a) => a['is_default'] == true, orElse: () => _addresses.first);
        _selectedAddressId = def['id'];
      }
      if (widget.serviceId != null && results.length > 1) {
        _service = results[1] as Map<String, dynamic>;
      }
    });

    if (!widget.isFirstBooking) _loadPromos();
    if (_isSchedule) _loadSlotAvailability(_selectedDate);
  }

  // ── Slot Availability ────────────────────────────────────────
  Future<void> _loadSlotAvailability(DateTime date) async {
    setState(() { _slotsLoading = true; _slotAvailability = {}; });

    try {
      final workersData = await _supabase
          .from('workers')
          .select('user_id, schedule, is_available')
          .eq('is_available', true);
      final workers = (workersData as List).cast<Map<String, dynamic>>();

      final dayStartLocal = DateTime(date.year, date.month, date.day, 0, 0, 0);
      final dayEndLocal   = DateTime(date.year, date.month, date.day, 23, 59, 59);

      final bookingsData = await _supabase
          .from('bookings')
          .select('worker_id, scheduled_at, services(duration_minutes)')
          .inFilter('status', ['accepted', 'in_progress', 'pending'])
          .eq('payment_status', 'paid')
          .gte('scheduled_at', dayStartLocal.toUtc().toIso8601String())
          .lte('scheduled_at', dayEndLocal.toUtc().toIso8601String());
      final bookings = (bookingsData as List).cast<Map<String, dynamic>>();

      final now          = DateTime.now();
      final cutoff       = now.add(const Duration(hours: 2));
      final dayName      = _dayName(date.weekday);
      final durationMins = _serviceDurationMins;

      final Map<String, bool> availability = {};

      for (final slot in _timeSlots) {
        final slotDt = _slotToDateTime(date, slot);

        if (slotDt.isBefore(cutoff)) {
          availability[slot] = false;
          continue;
        }

        bool anyWorkerFree = false;
        for (final worker in workers) {
          final schedule = worker['schedule'] as Map<String, dynamic>?;
          if (!_isWorkerInShift(schedule, dayName, slotDt)) continue;
          if (!_isWorkerFreeAtSlot(
              worker['user_id'] as String, slotDt, durationMins, bookings)) {
            continue;
          }
          anyWorkerFree = true;
          break;
        }

        availability[slot] = anyWorkerFree;
      }

      if (mounted) setState(() {
        _slotAvailability = availability;
        _slotsLoading     = false;
        if (_selectedTime.isNotEmpty &&
            availability[_selectedTime] == false) {
          _selectedTime = '';
        }
      });
    } catch (e) {
      debugPrint('slot availability error: $e');
      if (mounted) setState(() {
        _slotAvailability = { for (final s in _timeSlots) s: true };
        _slotsLoading = false;
      });
    }
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

  String _dayName(int weekday) {
    const names = ['', 'monday', 'tuesday', 'wednesday',
        'thursday', 'friday', 'saturday', 'sunday'];
    return names[weekday];
  }

  bool _isWorkerInShift(
      Map<String, dynamic>? schedule, String dayName, DateTime slotDt) {
    if (schedule == null) return true;
    final day = schedule[dayName] as Map<String, dynamic>?;
    if (day == null || day['enabled'] != true) return false;
    final start     = day['start'] as String? ?? '09:00';
    final end       = day['end']   as String? ?? '17:00';
    final startMins = _timeToMins(start);
    final endMins   = _timeToMins(end);
    final slotMins  = slotDt.hour * 60 + slotDt.minute;
    if (slotMins < startMins || slotMins >= endMins) return false;
    final breaks = day['breaks'] as List? ?? [];
    for (final b in breaks) {
      final bStart = _timeToMins(b['from'] as String? ?? '00:00');
      final bEnd   = _timeToMins(b['to']   as String? ?? '00:00');
      if (slotMins >= bStart && slotMins < bEnd) return false;
    }
    return true;
  }

  int _timeToMins(String t) {
    final parts = t.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  bool _isWorkerFreeAtSlot(String workerId, DateTime slotDt,
      int durationMins, List<Map<String, dynamic>> bookings) {
    final slotEnd = slotDt.add(Duration(minutes: durationMins));
    for (final booking in bookings) {
      if (booking['worker_id'] != workerId) continue;
      final bDt = DateTime.tryParse(booking['scheduled_at'].toString());
      if (bDt == null) continue;
      final bDur = (booking['services']?['duration_minutes'] as num?)?.toInt()
          ?? durationMins;
      final bDurRounded = (bDur / 60).ceil() * 60;
      final bEnd = bDt.add(Duration(minutes: bDurRounded));
      if (slotDt.isBefore(bEnd) && slotEnd.isAfter(bDt)) return false;
    }
    return true;
  }

  // ── Promos ───────────────────────────────────────────────────
  Future<void> _loadPromos() async {
    if (_userId == null) return;
    setState(() => _promosLoading = true);
    try {
      final promoData = await _supabase
          .from('promo_codes').select('*').eq('is_active', true)
          .order('created_at', ascending: false);
      final allActive = (promoData as List).cast<Map<String, dynamic>>();

      final usageData = await _supabase.from('promo_usage')
          .select('promo_id').eq('user_id', _userId!);
      final usedIds =
          (usageData as List).map((r) => r['promo_id'].toString()).toSet();

      List<Map<String, dynamic>> usedPromos = [];
      if (usedIds.isNotEmpty) {
        final ud = await _supabase
            .from('promo_codes').select('*').inFilter('id', usedIds.toList());
        usedPromos = (ud as List).cast<Map<String, dynamic>>();
      }

      final now = DateTime.now();
      final available = allActive.where((p) {
        if (usedIds.contains(p['id'].toString())) return false;
        if (p['valid_until'] != null) {
          final exp = DateTime.tryParse(p['valid_until'].toString());
          if (exp != null && exp.isBefore(now)) return false;
        }
        final limit = p['usage_limit'] ?? p['max_uses'];
        if (limit != null) {
          if ((p['used_count'] as num? ?? 0).toInt() >=
              (limit as num).toInt()) return false;
        }
        return true;
      }).toList();

      if (mounted) setState(() {
        _promos        = available;
        _usedPromos    = usedPromos;
        _usedPromoIds  = usedIds;
        _promosLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _promosLoading = false);
    }
  }

  void _applyPromo(Map<String, dynamic> promo) {
    if (widget.isFirstBooking) return;
    final type  = promo['discount_type'] as String? ?? 'percent';
    final value = (promo['discount_value'] as num? ?? 0).toDouble();
    final max   = promo['max_discount_amount'] != null
        ? (promo['max_discount_amount'] as num).toInt() : 9999;
    final min   = promo['min_order_amount'] != null
        ? (promo['min_order_amount'] as num).toInt() : 0;
    if (_baseAmount < min) {
      _showSnack('Min order ₹$min required for this code', isError: true);
      return;
    }
    int disc = type == 'flat'
        ? value.toInt()
        : ((_baseAmount * value) / 100).floor().clamp(0, max);
    setState(() {
      _appliedPromoId   = promo['id'].toString();
      _appliedPromoCode = promo['code'] as String;
      _discount         = disc;
    });
    HapticFeedback.mediumImpact();
    Navigator.pop(context);
  }

  void _removePromo() {
    setState(() { _appliedPromoId = ''; _appliedPromoCode = ''; _discount = 0; });
  }

  void _showPromoSheet() {
    if (widget.isFirstBooking) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PromoSheet(
        promos: _promos, usedPromos: _usedPromos,
        appliedId: _appliedPromoId, baseAmount: _baseAmount,
        loading: _promosLoading, onApply: _applyPromo, onRemove: _removePromo,
      ),
    );
  }

  // ── Payment ──────────────────────────────────────────────────
  Future<void> _proceedToPayment() async {
    if (_selectedAddressId.isEmpty) {
      _showSnack('Please select an address', isError: true); return;
    }
    if (_isSchedule && _selectedTime.isEmpty) {
      _showSnack('Please select a time slot', isError: true); return;
    }

    setState(() => _loading = true);
    final user = _supabase.auth.currentUser;
    if (user == null) { if (mounted) context.go('/login'); return; }

    final scheduledAt = _isInstant
        ? DateTime.now().add(const Duration(hours: 1)).toUtc()
        : _buildScheduledAt();

    final otp =
        (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();

    try {
      Map<String, dynamic> bookingPayload = {
        'customer_id':          user.id,
        'address_id':           _selectedAddressId,
        'scheduled_at':         scheduledAt.toIso8601String(),
        'status':               'pending',
        'base_price':           _baseAmount,
        'discount_amount':      _discount,
        'final_amount':         _finalAmount,
        'special_instructions': _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        'payment_status':       'unpaid',
        'otp':                  otp,
        if (_appliedPromoCode.isNotEmpty) 'promo_code': _appliedPromoCode,
        if (widget.selectedBhk != null) 'selected_bhk': widget.selectedBhk,
        if (widget.quantity != null)    'quantity':      widget.quantity,
        if (widget.isFirstBooking)      'is_first_booking': true,
      };
      if (widget.serviceId != null) bookingPayload['service_id'] = widget.serviceId;

      final booking = await _supabase.from('bookings')
          .insert(bookingPayload).select().single();
      _pendingBookingId = booking['id'] as String;

      if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
        try {
          await _supabase.from('booking_items').insert(
            widget.cartItems!.map((c) => {
              'booking_id':  _pendingBookingId,
              'service_id':  c['service_id'] as String,
              'quantity':    (c['quantity'] as num).toInt(),
              'unit_price':  (c['price'] as num).toInt(),
              'total_price': (c['price'] as num).toInt() *
                  (c['quantity'] as num).toInt(),
            }).toList(),
          );
        } catch (e) { debugPrint('booking_items skipped: $e'); }
      }

      setState(() => _loading = false);
      _launchRazorpay(user);
    } catch (e) {
      setState(() => _loading = false);
      _showSnack(
          'Could not create booking: ${e.toString().split('\n').first}',
          isError: true);
    }
  }

  void _launchRazorpay(user) {
    _supabase.from('users').select('full_name,phone').eq('id', user.id)
        .maybeSingle().then((profile) {
      final name  = profile?['full_name'] as String? ?? 'Customer';
      final phone = profile?['phone']     as String? ?? '';
      final options = {
        'key':         'rzp_test_Si33xml9Pvmuqb',
        'amount':      _finalAmount * 100,
        'name':        'Cleenzo',
        'description': _service?['name'] ?? 'Cleaning Service',
        'prefill': {
          'name':    name,
          'contact': phone.startsWith('+91') ? phone : '+91$phone',
        },
        'theme': {'color': '#06B6D4'},
        'notes': {'booking_id': _pendingBookingId},
      };
      try {
        _razorpay.open(options);
      } catch (e) {
        _showSnack('Could not open payment: $e', isError: true);
        setState(() => _loading = false);
      }
    });
  }

  DateTime _buildScheduledAt() {
    final parts = _selectedTime.split(' ');
    final hm    = parts[0].split(':');
    int hh      = int.parse(hm[0]);
    final mm    = int.parse(hm[1]);
    final pm    = parts[1] == 'PM';
    if (pm && hh != 12) hh += 12;
    if (!pm && hh == 12) hh = 0;
    final local = DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, hh, mm);
    return local.toUtc();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : const Color(0xFF10B981),
    ));
  }

  // ── BUILD ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final c1 = _isInstant ? _instant1 : _cyan;
    final c2 = _isInstant ? _instant2 : _cyanDeep;

    return Scaffold(
      backgroundColor: _tint,
      body: Stack(children: [
        Column(children: [
          _buildHeader(c1, c2),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
              child: _buildStepContent(),
            ),
          ),
        ]),
        Positioned(left: 0, right: 0, bottom: 0, child: _buildBottomBar(c1, c2)),
      ]),
    );
  }

  Widget _buildHeader(Color c1, Color c2) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [c1, c2]),
      ),
      child: Stack(children: [
        Positioned(
          top: -36, right: -24,
          child: Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.white.withValues(alpha: 0.08)),
          ),
        ),
        SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                GestureDetector(
                  onTap: () {
                    if (_step > 1) setState(() => _step--);
                    else Navigator.pop(context);
                  },
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.20),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                    ),
                    child: const Icon(Icons.arrow_back_ios_new_rounded,
                        color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Text(_isInstant ? '⚡' : '📅',
                        style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 6),
                    Text(_isInstant ? 'Instant Booking' : 'Schedule Booking',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 16, fontWeight: FontWeight.w900)),
                  ]),
                  Text(_isInstant
                      ? 'Pro arrives within 2 hours'
                      : 'Choose your date & time',
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.80),
                          fontSize: 11)),
                ])),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.95),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text('₹$_finalAmount',
                        style: TextStyle(color: c2,
                            fontSize: 18, fontWeight: FontWeight.w900)),
                    Text(
                      widget.isFirstBooking
                          ? '🎉 First booking!'
                          : _discount > 0 ? '-₹$_discount saved' : 'Total',
                      style: TextStyle(
                          color: c2.withValues(alpha: 0.7),
                          fontSize: 9.5, fontWeight: FontWeight.w700)),
                  ]),
                ),
              ]),
              const SizedBox(height: 20),
              Row(children: List.generate(_stepLabels.length, (i) {
                final s = i + 1; final active = _step == s; final done = _step > s;
                return Expanded(child: Row(children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 30, height: 30,
                    decoration: BoxDecoration(
                      color: done || active
                          ? Colors.white
                          : Colors.white.withValues(alpha: 0.22),
                      shape: BoxShape.circle,
                      boxShadow: active ? [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.12),
                          blurRadius: 8, offset: const Offset(0, 3))] : [],
                    ),
                    child: Center(child: done
                      ? Icon(Icons.check_rounded, color: c1, size: 15)
                      : Icon(_stepIcons[i < _stepIcons.length ? i : 0],
                          color: active ? c1 : Colors.white.withValues(alpha: 0.7),
                          size: 14)),
                  ),
                  const SizedBox(width: 6),
                  Flexible(child: Text(_stepLabels[i],
                    style: TextStyle(
                      color: active
                          ? Colors.white
                          : Colors.white.withValues(alpha: done ? 0.85 : 0.55),
                      fontSize: 11, fontWeight: active ? FontWeight.w800 : FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                  if (i < _stepLabels.length - 1)
                    Expanded(child: Container(
                      height: 1.4,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: Colors.white.withValues(alpha: done ? 0.65 : 0.25))),
                ]));
              })),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _buildStepContent() {
    if (_isSchedule) {
      if (_step == 1) return _buildDateTimeStep();
      if (_step == 2) return _buildAddressStep();
      return _buildConfirmStep();
    } else {
      if (_step == 1) return _buildAddressStep();
      return _buildConfirmStep();
    }
  }

  // ── Date & Time step ─────────────────────────────────────────
  Widget _buildDateTimeStep() {
    final availableCount =
        _slotAvailability.values.where((v) => v == true).length;

    return Column(children: [
      if (widget.isFirstBooking) _buildFirstBookingBanner(),
      if (widget.isFirstBooking) const SizedBox(height: 14),

      _card(
        icon: Icons.calendar_month_rounded,
        title: 'Choose Date',
        sub: 'Select your preferred date',
        child: SizedBox(
          height: 92,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _dates.length,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final d      = _dates[i];
              final active = d.day == _selectedDate.day &&
                  d.month == _selectedDate.month;
              return GestureDetector(
                onTap: () {
                  setState(() { _selectedDate = d; _selectedTime = ''; });
                  HapticFeedback.selectionClick();
                  _loadSlotAvailability(d);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: 58,
                  decoration: BoxDecoration(
                    gradient: active
                        ? const LinearGradient(colors: [_cyan, _cyanDk])
                        : null,
                    color: active ? null : _tint,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                        color: active ? _cyan : _border),
                    boxShadow: active
                        ? [BoxShadow(
                            color: _cyan.withValues(alpha: 0.40),
                            blurRadius: 12, offset: const Offset(0, 4))]
                        : []),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d.weekday-1],
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                            color: active
                                ? const Color(0xFFDFFAFE)
                                : const Color(0xFF94A3B8))),
                    Text('${d.day}',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                            color: active ? Colors.white : _ink)),
                    Text(i == 0 ? 'TODAY' : '·',
                        style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900,
                            color: active ? Colors.white
                                : (i == 0 ? _cyan : Colors.transparent))),
                  ]),
                ),
              );
            },
          ),
        ),
      ),

      const SizedBox(height: 14),

      _card(
        icon: Icons.access_time_rounded,
        title: 'Choose Time',
        sub: _slotsLoading
            ? 'Checking availability…'
            : '$availableCount slots available · 2hr advance · '
              '${_slotsBlocked}hr${_slotsBlocked > 1 ? 's' : ''} blocked per booking',
        child: _slotsLoading
            ? const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  CircularProgressIndicator(color: _cyan),
                  SizedBox(height: 12),
                  Text('Checking worker availability…',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
                ])))
            : Column(children: [
                Row(children: [
                  _legendDot(_cyan),
                  const SizedBox(width: 4),
                  const Text('Available',
                      style: TextStyle(color: _inkSoft, fontSize: 11)),
                  const SizedBox(width: 16),
                  _legendDot(const Color(0xFFE2E8F0)),
                  const SizedBox(width: 4),
                  const Text('Full / Not available',
                      style: TextStyle(color: _inkSoft, fontSize: 11)),
                ]),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  childAspectRatio: 2.0,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                  children: _timeSlots.map((slot) {
                    final active  = _selectedTime == slot;
                    final isAvail = _slotAvailability[slot] ?? true;
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
                          color: isFull
                              ? const Color(0xFFF8FAFC)
                              : active ? null : _tint,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isFull
                                  ? const Color(0xFFE8EDF2)
                                  : active ? _cyan : _border),
                          boxShadow: active && !isFull
                              ? [BoxShadow(
                                  color: _cyan.withValues(alpha: 0.38),
                                  blurRadius: 10, offset: const Offset(0, 3))]
                              : []),
                        child: Column(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          Text(slot, style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w800,
                              color: isFull
                                  ? const Color(0xFFCBD5E1)
                                  : active ? Colors.white : const Color(0xFF334155))),
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
                if (availableCount == 0 && !_slotsLoading) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFED7AA))),
                    child: const Row(children: [
                      Text('😔', style: TextStyle(fontSize: 22)),
                      SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Text('No slots available today',
                            style: TextStyle(fontWeight: FontWeight.w800,
                                color: Color(0xFF92400E))),
                        SizedBox(height: 2),
                        Text('Try selecting a different date',
                            style: TextStyle(color: Color(0xFFB45309),
                                fontSize: 12)),
                      ])),
                    ]),
                  ),
                ],
              ]),
      ),
    ]);
  }

  Widget _legendDot(Color color) => Container(
        width: 10, height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle));

  // ── First booking banner ─────────────────────────────────────
  Widget _buildFirstBookingBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
            colors: [_instant1, _instant2]),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(
            color: _instant1.withValues(alpha: 0.3),
            blurRadius: 14, offset: const Offset(0, 5))]),
      child: const Row(children: [
        Text('🎉', style: TextStyle(fontSize: 28)),
        SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('First Booking — Just ₹25!',
              style: TextStyle(color: Colors.white,
                  fontWeight: FontWeight.w900, fontSize: 14)),
          SizedBox(height: 2),
          Text('Promo codes cannot be stacked with this offer.',
              style: TextStyle(color: Color(0xFFD1FAE5), fontSize: 11)),
        ])),
        Text('₹25', style: TextStyle(color: Colors.white,
            fontSize: 24, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  // ── Address step ─────────────────────────────────────────────
  Widget _buildAddressStep() {
    return Column(children: [
      if (_isInstant)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFF6EE7B7))),
          child: const Row(children: [
            Text('⚡', style: TextStyle(fontSize: 28)),
            SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Instant Booking!',
                  style: TextStyle(color: Color(0xFF065F46),
                      fontWeight: FontWeight.w900, fontSize: 14)),
              SizedBox(height: 2),
              Text('A verified pro will be dispatched within 2 hours.',
                  style: TextStyle(color: Color(0xFF047857), fontSize: 12)),
            ])),
          ]),
        ),

      if (widget.isFirstBooking) ...[
        _buildFirstBookingBanner(),
        const SizedBox(height: 14),
      ],

      _card(
        icon: Icons.location_on_rounded,
        title: 'Service Address',
        sub: 'Where should we come?',
        trailing: GestureDetector(
          onTap: () => context.go('/account'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _tint2,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFFA5F3FC))),
            child: const Text('+ Add',
                style: TextStyle(color: _cyanDk,
                    fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ),
        child: _addresses.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  Text('📍', style: TextStyle(fontSize: 38)),
                  SizedBox(height: 10),
                  Text('No saved addresses',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          color: Color(0xFF374151))),
                  SizedBox(height: 4),
                  Text('Add an address to continue',
                      style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
                ]))
            : Column(children: _addresses.map((addr) {
                final active = _selectedAddressId == addr['id'];
                final lbl    = addr['label'] ?? 'Address';
                final icon   = lbl == 'Home' ? '🏠' : lbl == 'Office' ? '🏢' : '📍';
                return GestureDetector(
                  onTap: () => setState(() => _selectedAddressId = addr['id']),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active ? _tint2 : _tint,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: active ? _cyan : _border,
                          width: active ? 1.6 : 1)),
                    child: Row(children: [
                      Container(
                        width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _border)),
                        child: Center(child: Text(icon,
                            style: const TextStyle(fontSize: 18)))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        Row(children: [
                          Text(lbl, style: const TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                          if (addr['is_default'] == true) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                  color: _tint2,
                                  borderRadius: BorderRadius.circular(20)),
                              child: const Text('Default',
                                  style: TextStyle(color: _cyanDk,
                                      fontSize: 9, fontWeight: FontWeight.w800))),
                          ],
                        ]),
                        const SizedBox(height: 2),
                        Text(
                          [if (addr['flat_no'] != null) addr['flat_no'],
                            if (addr['building'] != null) addr['building'],
                            addr['area'], addr['city']]
                              .where((e) => e != null).join(', '),
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 12),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                      ])),
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 22, height: 22,
                        decoration: BoxDecoration(
                          color: active ? _cyan : Colors.transparent,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: active ? _cyan : const Color(0xFFD1D5DB),
                              width: 2)),
                        child: active
                            ? const Icon(Icons.check_rounded,
                                color: Colors.white, size: 12)
                            : null),
                    ]),
                  ),
                );
              }).toList()),
      ),
      const SizedBox(height: 14),
      _card(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Special Instructions',
        sub: 'Optional notes for the cleaner',
        child: TextField(
          controller: _notesCtrl, maxLines: 3,
          decoration: InputDecoration(
            hintText: 'e.g. Ring bell twice, pet at home...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            filled: true, fillColor: _tint,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _cyan, width: 1.6))),
        ),
      ),
    ]);
  }

  // ── Confirm step ─────────────────────────────────────────────
  Widget _buildConfirmStep() {
    final addr = _addresses.firstWhere(
        (a) => a['id'] == _selectedAddressId, orElse: () => {});
    final rows = [
      {'icon': '🧹', 'label': 'Service',  'value': _serviceLabel},
      if (widget.isFirstBooking)
        {'icon': '🎉', 'label': 'Offer',   'value': 'First booking at ₹25!'},
      if (_isSchedule) ...[
        {'icon': '📅', 'label': 'Date',
          'value': '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'},
        {'icon': '⏰', 'label': 'Time',    'value': _selectedTime},
        {'icon': '⏱', 'label': 'Duration',
          'value': '~${_serviceDurationMins} min · $_slotsBlocked slot${_slotsBlocked > 1 ? 's' : ''} blocked'},
      ],
      if (_isInstant)
        {'icon': '⚡', 'label': 'Arrival', 'value': 'Within 2 hours'},
      {'icon': '📍', 'label': 'Address',
        'value': addr.isNotEmpty ? '${addr['area']}, ${addr['city']}' : '—'},
      if (_notesCtrl.text.isNotEmpty)
        {'icon': '💬', 'label': 'Notes',   'value': _notesCtrl.text},
    ];

    return Column(children: [
      _card(
        icon: Icons.receipt_long_rounded,
        title: 'Booking Summary',
        sub: 'Review before confirming',
        child: Column(children: rows.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                  color: _tint,
                  borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(r['icon']!,
                  style: const TextStyle(fontSize: 16)))),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['label']!,
                  style: const TextStyle(color: Color(0xFF94A3B8),
                      fontSize: 10, fontWeight: FontWeight.w700,
                      letterSpacing: 0.4)),
              Text(r['value']!,
                  style: const TextStyle(fontSize: 14,
                      fontWeight: FontWeight.w700, color: _ink)),
            ])),
          ]),
        )).toList()),
      ),
      const SizedBox(height: 14),

      if (!widget.isFirstBooking)
        GestureDetector(
          onTap: _showPromoSheet,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: _appliedPromoCode.isNotEmpty
                    ? const Color(0xFF6EE7B7) : _border,
                width: _appliedPromoCode.isNotEmpty ? 1.5 : 1),
              boxShadow: [BoxShadow(
                  color: _cyan.withValues(alpha: 0.06),
                  blurRadius: 12, offset: const Offset(0, 4))]),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(children: [
                  Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: _appliedPromoCode.isNotEmpty
                          ? const Color(0xFFECFDF5) : const Color(0xFFF5F3FF),
                      borderRadius: BorderRadius.circular(11)),
                    child: Center(child: Text(
                        _appliedPromoCode.isNotEmpty ? '🎉' : '🎟',
                        style: const TextStyle(fontSize: 18)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      _appliedPromoCode.isNotEmpty
                          ? 'Promo Applied!'
                          : 'Apply Promo Code',
                      style: TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 14,
                          color: _appliedPromoCode.isNotEmpty
                              ? const Color(0xFF059669)
                              : _ink)),
                    Text(
                      _appliedPromoCode.isNotEmpty
                          ? '$_appliedPromoCode  •  Saving ₹$_discount'
                          : _promos.isEmpty && !_promosLoading
                              ? 'No offers available right now'
                              : 'Tap to see ${_promos.length} offer${_promos.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: _appliedPromoCode.isNotEmpty
                              ? const Color(0xFF10B981)
                              : const Color(0xFF94A3B8),
                          fontSize: 11)),
                  ])),
                  if (_appliedPromoCode.isNotEmpty)
                    GestureDetector(
                      onTap: _removePromo,
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                            color: const Color(0xFFFEF2F2),
                            borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.close_rounded,
                            size: 14, color: Color(0xFFDC2626))))
                  else
                    Icon(Icons.chevron_right_rounded,
                      color: _promos.isEmpty
                          ? const Color(0xFFD1D5DB) : const Color(0xFF94A3B8)),
                ]),
              ),
              if (_appliedPromoCode.isNotEmpty) ...[
                const Divider(height: 1, color: Color(0xFFF0FDF4)),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20))),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: Color(0xFF10B981), size: 16),
                    const SizedBox(width: 8),
                    Text('₹$_discount discount applied to your order',
                        style: const TextStyle(color: Color(0xFF059669),
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
        ),

      if (!widget.isFirstBooking) const SizedBox(height: 14),

      // Price card
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: widget.isFirstBooking
              ? [_instant1, _instant2]
              : [_cyan, _cyanDeep]),
          borderRadius: BorderRadius.circular(22),
          boxShadow: [BoxShadow(
              color: (widget.isFirstBooking ? _instant1 : _cyan)
                  .withValues(alpha: 0.30),
              blurRadius: 18, offset: const Offset(0, 6))]),
        child: Column(children: [
          if (widget.isFirstBooking)
            _priceRow('Original price', '₹${widget.overridePrice ?? _baseAmount}',
                Colors.white.withValues(alpha: 0.7),
                Colors.white.withValues(alpha: 0.7)),
          if (widget.isFirstBooking)
            _priceRow('First booking discount',
                '-₹${(widget.overridePrice ?? _baseAmount) - 25}',
                Colors.white.withValues(alpha: 0.85),
                const Color(0xFFBBF7D0)),
          if (!widget.isFirstBooking)
            _priceRow('Service total', '₹$_baseAmount',
                Colors.white.withValues(alpha: 0.85), Colors.white),
          if (!widget.isFirstBooking && _discount > 0)
            _priceRow('Promo ($_appliedPromoCode)', '− ₹$_discount',
                Colors.white.withValues(alpha: 0.85),
                const Color(0xFF86EFAC)),
          _priceRow('Platform fee', 'FREE',
              Colors.white.withValues(alpha: 0.85),
              const Color(0xFF86EFAC)),
          const Divider(color: Colors.white24, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total Payable',
                style: TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w900)),
            Text('₹$_finalAmount',
                style: const TextStyle(color: Colors.white,
                    fontSize: 28, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            _payIcon('💳'), _payIcon('🏦'), _payIcon('📱'), _payIcon('💰'),
            const SizedBox(width: 8),
            const Text('UPI · Cards · NetBanking · Wallets',
                style: TextStyle(color: Colors.white60, fontSize: 10)),
          ]),
        ]),
      ),
    ]);
  }

  Widget _payIcon(String e) => Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Text(e, style: const TextStyle(fontSize: 14)));

  Widget _priceRow(String l, String v, Color lc, Color vc) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
        Text(l, style: TextStyle(color: lc, fontSize: 13)),
        Text(v, style: TextStyle(color: vc, fontSize: 13,
            fontWeight: FontWeight.bold)),
      ]));

  Widget _card({required IconData icon, required String title,
      required String sub, required Widget child, Widget? trailing}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [BoxShadow(
            color: _cyan.withValues(alpha: 0.07),
            blurRadius: 16, offset: const Offset(0, 5))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                      color: _cyan.withValues(alpha: 0.30),
                      blurRadius: 8, offset: const Offset(0, 3))]),
              child: Icon(icon, color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800,
                  fontSize: 14, color: _ink)),
              Text(sub, style: const TextStyle(
                  color: Color(0xFF94A3B8), fontSize: 11)),
            ])),
            if (trailing != null) trailing,
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF3F4F6)),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }

  Widget _buildBottomBar(Color c1, Color c2) {
    final canProceed = _canProceed();
    final isLast     = _step == _totalSteps;
    final bottom     = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 22, offset: const Offset(0, -6))],
      ),
      child: Row(children: [
        if (_step > 1) ...[
          GestureDetector(
            onTap: () => setState(() => _step--),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                  color: _tint,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border)),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _inkSoft, size: 18))),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: GestureDetector(
            onTap: canProceed && !_loading
                ? () {
                    if (isLast) _proceedToPayment();
                    else setState(() => _step++);
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              decoration: BoxDecoration(
                gradient: canProceed ? LinearGradient(colors: [c1, c2]) : null,
                color: canProceed ? null : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(16),
                boxShadow: canProceed
                    ? [BoxShadow(color: c1.withValues(alpha: 0.42),
                        blurRadius: 16, offset: const Offset(0, 5))]
                    : []),
              child: Center(
                child: _loading
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        if (isLast) const Text('💳  ',
                            style: TextStyle(fontSize: 16)),
                        Text(
                          isLast ? 'Pay ₹$_finalAmount' : 'Continue',
                          style: TextStyle(
                            color: canProceed ? Colors.white : const Color(0xFF94A3B8),
                            fontSize: 15, fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                          color: canProceed ? Colors.white : const Color(0xFF94A3B8),
                          size: 18),
                      ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  bool _canProceed() {
    if (_isSchedule && _step == 1) {
      return _selectedTime.isNotEmpty &&
          (_slotAvailability[_selectedTime] ?? false);
    }
    if (_step == _addressStep) return _selectedAddressId.isNotEmpty;
    return true;
  }
}

// ── Promo Sheet ──────────────────────────────────────────────────
class _PromoSheet extends StatelessWidget {
  final List<Map<String, dynamic>> promos;
  final List<Map<String, dynamic>> usedPromos;
  final String    appliedId;
  final int       baseAmount;
  final bool      loading;
  final void Function(Map<String, dynamic>) onApply;
  final VoidCallback onRemove;

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);

  const _PromoSheet({
    required this.promos, required this.usedPromos,
    required this.appliedId, required this.baseAmount,
    required this.loading, required this.onApply, required this.onRemove,
  });

  String _calcDiscount(Map<String, dynamic> p) {
    final type  = p['discount_type'] as String? ?? 'percent';
    final value = (p['discount_value'] as num? ?? 0).toDouble();
    final max   = p['max_discount_amount'] != null
        ? (p['max_discount_amount'] as num).toInt() : 9999;
    if (type == 'flat') return '₹${value.toInt()} off';
    final disc = ((baseAmount * value) / 100).floor().clamp(0, max);
    return '${value.toStringAsFixed(0)}% off  •  save ₹$disc';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      child: Column(children: [
        Container(
          margin: const EdgeInsets.only(top: 10), width: 40, height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            const Text('🎟', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Choose Promo Code',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A))),
              Text('Select an offer to apply on your booking',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
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
          child: loading
              ? const Center(child: CircularProgressIndicator(color: _cyan))
              : (promos.isEmpty && usedPromos.isEmpty)
                  ? const Center(child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text('🎟', style: TextStyle(fontSize: 40)),
                        SizedBox(height: 12),
                        Text('No offers available', style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF374151))),
                        SizedBox(height: 4),
                        Text('Check back soon!', style: TextStyle(
                            color: Color(0xFF9CA3AF), fontSize: 13)),
                      ]))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                      children: [
                        if (promos.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10, left: 4),
                            child: Text('AVAILABLE OFFERS',
                                style: TextStyle(color: Color(0xFF9CA3AF),
                                    fontSize: 10, fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5))),
                          ...promos.map((p) {
                            final isApplied = appliedId == p['id'].toString();
                            final minOrder  = p['min_order_amount'] != null
                                ? (p['min_order_amount'] as num).toInt() : 0;
                            final canApply  = baseAmount >= minOrder;
                            return GestureDetector(
                              onTap: canApply ? () => onApply(p) : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isApplied ? const Color(0xFFECFDF5)
                                      : canApply ? Colors.white : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: isApplied ? const Color(0xFF6EE7B7)
                                          : canApply ? const Color(0xFFE8EDF2)
                                          : const Color(0xFFF1F5F9),
                                      width: isApplied ? 1.5 : 1)),
                                child: Row(children: [
                                  Container(
                                    width: 52, height: 52,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: isApplied
                                          ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                          : canApply
                                              ? [_cyan, _cyanDk]
                                              : [const Color(0xFFCBD5E1), const Color(0xFF94A3B8)]),
                                      borderRadius: BorderRadius.circular(14)),
                                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                      Text(
                                        (p['discount_type'] as String?) == 'percent'
                                            ? '${(p['discount_value'] as num).toInt()}%'
                                            : '₹${(p['discount_value'] as num).toInt()}',
                                        style: const TextStyle(color: Colors.white,
                                            fontSize: 14, fontWeight: FontWeight.w900)),
                                      const Text('OFF', style: TextStyle(
                                          color: Colors.white70, fontSize: 8,
                                          fontWeight: FontWeight.bold)),
                                    ])),
                                  const SizedBox(width: 12),
                                  Expanded(child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                    Row(children: [
                                      Text(p['code'] as String,
                                          style: TextStyle(fontWeight: FontWeight.w900,
                                              fontSize: 14, letterSpacing: 1,
                                              color: isApplied ? const Color(0xFF059669)
                                                  : canApply ? const Color(0xFF0F172A)
                                                  : const Color(0xFF94A3B8))),
                                      if (isApplied) ...[
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                              color: const Color(0xFFDCFCE7),
                                              borderRadius: BorderRadius.circular(6)),
                                          child: const Text('Applied',
                                              style: TextStyle(color: Color(0xFF16A34A),
                                                  fontSize: 9,
                                                  fontWeight: FontWeight.w800))),
                                      ],
                                    ]),
                                    const SizedBox(height: 2),
                                    if ((p['description'] as String? ?? '').isNotEmpty)
                                      Text(p['description'] as String,
                                          style: TextStyle(
                                              color: canApply ? const Color(0xFF6B7280)
                                                  : const Color(0xFFD1D5DB),
                                              fontSize: 11),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text(_calcDiscount(p), style: TextStyle(
                                        color: isApplied ? const Color(0xFF10B981)
                                            : canApply ? _cyanDk
                                            : const Color(0xFFD1D5DB),
                                        fontSize: 11, fontWeight: FontWeight.w700)),
                                    if (!canApply)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text('Min order ₹$minOrder required',
                                            style: const TextStyle(
                                                color: Color(0xFFEF4444),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600))),
                                  ])),
                                  if (isApplied)
                                    GestureDetector(
                                      onTap: () { onRemove(); Navigator.pop(context); },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10, vertical: 6),
                                        decoration: BoxDecoration(
                                            color: const Color(0xFFFEF2F2),
                                            borderRadius: BorderRadius.circular(10)),
                                        child: const Text('Remove',
                                            style: TextStyle(color: Color(0xFFDC2626),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700))))
                                  else if (canApply)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFEEF2FF),
                                          borderRadius: BorderRadius.circular(10)),
                                      child: const Text('Apply',
                                          style: TextStyle(color: Color(0xFF6366F1),
                                              fontSize: 11,
                                              fontWeight: FontWeight.w800))),
                                ]),
                              ),
                            );
                          }),
                        ],
                        if (usedPromos.isNotEmpty) ...[
                          Padding(
                            padding: EdgeInsets.only(
                                top: promos.isNotEmpty ? 8 : 0,
                                bottom: 10, left: 4),
                            child: Row(children: const [
                              Text('ALREADY USED',
                                  style: TextStyle(color: Color(0xFF9CA3AF),
                                      fontSize: 10, fontWeight: FontWeight.w800,
                                      letterSpacing: 1.5)),
                              SizedBox(width: 8),
                              Text('• One use per account',
                                  style: TextStyle(color: Color(0xFFD1D5DB),
                                      fontSize: 10)),
                            ])),
                          ...usedPromos.map((p) => Opacity(
                            opacity: 0.55,
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: const Color(0xFFF1F5F9))),
                              child: Row(children: [
                                Container(
                                  width: 52, height: 52,
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFE2E8F0),
                                      borderRadius: BorderRadius.circular(14)),
                                  child: const Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                    Icon(Icons.check_circle_rounded,
                                        color: Color(0xFF94A3B8), size: 22),
                                    Text('USED', style: TextStyle(
                                        color: Color(0xFFCBD5E1), fontSize: 8,
                                        fontWeight: FontWeight.bold)),
                                  ])),
                                const SizedBox(width: 12),
                                Expanded(child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                  Text(p['code'] as String,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w900, fontSize: 14,
                                          color: Color(0xFF94A3B8), letterSpacing: 1,
                                          decoration: TextDecoration.lineThrough)),
                                  const SizedBox(height: 2),
                                  if ((p['description'] as String? ?? '').isNotEmpty)
                                    Text(p['description'] as String,
                                        style: const TextStyle(
                                            color: Color(0xFFCBD5E1), fontSize: 11),
                                        maxLines: 1, overflow: TextOverflow.ellipsis),
                                ])),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 6),
                                  decoration: BoxDecoration(
                                      color: const Color(0xFFF1F5F9),
                                      borderRadius: BorderRadius.circular(10)),
                                  child: const Text('Used',
                                      style: TextStyle(color: Color(0xFF94A3B8),
                                          fontSize: 11, fontWeight: FontWeight.w700))),
                              ]),
                            ),
                          )),
                        ],
                      ],
                    ),
        ),
      ]),
    );
  }
}