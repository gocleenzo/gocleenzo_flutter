import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';
import 'booking_detail_screen.dart';

class BookingFlowScreen extends StatefulWidget {
  final String mode;
  final String? serviceId;
  final List<Map<String, dynamic>>? cartItems;

  const BookingFlowScreen({
    super.key,
    required this.mode,
    this.serviceId,
    this.cartItems,
  });

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  final _supabase = Supabase.instance.client;
  late Razorpay _razorpay;

  int  _step    = 1;
  bool _loading = false;

  // DateTime
  DateTime _selectedDate = DateTime.now();
  String   _selectedTime = '';

  // Address
  List<Map<String, dynamic>> _addresses         = [];
  String                     _selectedAddressId = '';

  // Promo
  List<Map<String, dynamic>> _promos       = [];
  List<Map<String, dynamic>> _usedPromos   = [];
  Set<String>                _usedPromoIds = {};
  bool   _promosLoading    = false;
  String _appliedPromoId   = '';
  String _appliedPromoCode = '';
  int    _discount         = 0;

  // Notes
  final _notesCtrl = TextEditingController();

  // Service
  Map<String, dynamic>? _service;

  // Payment — pending booking created before payment
  String _pendingBookingId = '';

  bool get _isSchedule  => widget.mode == 'schedule';
  bool get _isInstant   => widget.mode == 'instant';
  int  get _totalSteps  => _isSchedule ? 3 : 2;
  int  get _addressStep => _isSchedule ? 2 : 1;
  int  get _confirmStep => _isSchedule ? 3 : 2;

  List<String> get _stepLabels => _isSchedule
      ? ['Date & Time', 'Address', 'Confirm']
      : ['Address', 'Confirm'];

  static const _timeSlots = [
    '07:00 AM','08:00 AM','09:00 AM','10:00 AM','11:00 AM',
    '12:00 PM','01:00 PM','02:00 PM','03:00 PM',
    '04:00 PM','05:00 PM','06:00 PM','07:00 PM',
  ];

  List<DateTime> get _dates =>
      List.generate(7, (i) => DateTime.now().add(Duration(days: i)));

  int get _baseAmount {
    if (widget.cartItems != null) {
      return widget.cartItems!.fold(
          0, (s, c) => s + (c['price'] as num).toInt() * (c['quantity'] as num).toInt());
    }
    return (_service?['base_price'] as num?)?.toInt() ?? 0;
  }

  int get _finalAmount => (_baseAmount - _discount).clamp(0, 999999);

  String? get _userId => _supabase.auth.currentUser?.id;

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

  // ── Razorpay setup ───────────────────────────────────────────
  void _initRazorpay() {
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,   _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
  }

  void _onPaymentSuccess(PaymentSuccessResponse response) async {
    setState(() => _loading = true);
    try {
      // 1. Update booking → payment_status = paid
      await _supabase.from('bookings').update({
        'payment_status':        'paid',
        'payment_id':            response.paymentId,
        'razorpay_order_id':     response.orderId,
        'payment_method':        'razorpay',
        'payment_captured_at':   DateTime.now().toIso8601String(),
        'status':                'pending', // booking confirmed, waiting for worker
      }).eq('id', _pendingBookingId);

      // 2. Record promo usage
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
          builder: (_) => BookingDetailScreen(bookingId: _pendingBookingId, isNew: true),
        ));
      }
    } catch (e) {
      setState(() => _loading = false);
      _showSnack('Payment captured but booking update failed. Contact support.', isError: true);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    setState(() => _loading = false);
    // Delete the pending booking since payment failed
    if (_pendingBookingId.isNotEmpty) {
      _supabase.from('bookings').delete().eq('id', _pendingBookingId).then((_) {
        _pendingBookingId = '';
      });
    }
    _showSnack('Payment failed: ${response.message ?? 'Try again'}', isError: true);
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

    _loadPromos();
  }

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
      final usedIds = (usageData as List).map((r) => r['promo_id'].toString()).toSet();

      List<Map<String, dynamic>> usedPromos = [];
      if (usedIds.isNotEmpty) {
        final ud = await _supabase.from('promo_codes').select('*').inFilter('id', usedIds.toList());
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
          if ((p['used_count'] as num? ?? 0).toInt() >= (limit as num).toInt()) return false;
        }
        return true;
      }).toList();

      if (mounted) setState(() {
        _promos       = available;
        _usedPromos   = usedPromos;
        _usedPromoIds = usedIds;
        _promosLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _promosLoading = false);
    }
  }

  void _applyPromo(Map<String, dynamic> promo) {
    final type  = promo['discount_type'] as String? ?? 'percent';
    final value = (promo['discount_value'] as num? ?? 0).toDouble();
    final max   = promo['max_discount_amount'] != null ? (promo['max_discount_amount'] as num).toInt() : 9999;
    final min   = promo['min_order_amount']    != null ? (promo['min_order_amount']    as num).toInt() : 0;

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

  // ── Create booking then launch Razorpay ──────────────────────
  Future<void> _proceedToPayment() async {
    if (_selectedAddressId.isEmpty) { _showSnack('Please select an address', isError: true); return; }
    if (_isSchedule && _selectedTime.isEmpty) { _showSnack('Please select a time slot', isError: true); return; }

    setState(() => _loading = true);
    final user = _supabase.auth.currentUser;
    if (user == null) { if (mounted) context.go('/login'); return; }

    final scheduledAt = _isInstant
        ? DateTime.now().add(const Duration(hours: 1))
        : _buildScheduledAt();

    final otp = (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();

    try {
      // Create booking with payment_status = 'unpaid' first
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
      };

      if (widget.serviceId != null) bookingPayload['service_id'] = widget.serviceId;

      final booking = await _supabase.from('bookings').insert(bookingPayload).select().single();
      _pendingBookingId = booking['id'] as String;

      // Insert cart items if multi-service
      if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
        try {
          await _supabase.from('booking_items').insert(
            widget.cartItems!.map((c) => {
              'booking_id':  _pendingBookingId,
              'service_id':  c['service_id'] as String,
              'quantity':    (c['quantity'] as num).toInt(),
              'unit_price':  (c['price'] as num).toInt(),
              'total_price': (c['price'] as num).toInt() * (c['quantity'] as num).toInt(),
            }).toList(),
          );
        } catch (e) { debugPrint('booking_items skipped: $e'); }
      }

      setState(() => _loading = false);

      // Launch Razorpay
      _launchRazorpay(user);

    } catch (e) {
      setState(() => _loading = false);
      _showSnack('Could not create booking: ${e.toString().split('\n').first}', isError: true);
    }
  }

  void _launchRazorpay(user) {
    // Fetch user name & phone from users table or fallback
    _supabase.from('users').select('full_name,phone').eq('id', user.id).maybeSingle().then((profile) {
      final name  = profile?['full_name'] as String? ?? 'Customer';
      final phone = profile?['phone']     as String? ?? '';

      final options = {
        'key':         'rzp_test_Si33xml9Pvmuqb', // 🔑 Replace with your key
        'amount':      _finalAmount * 100,      // Razorpay uses paise
        'name':        'Cleenzo',
        'description': _service?['name'] ?? 'Cleaning Service',
        'prefill': {
          'name':    name,
          'contact': phone.startsWith('+91') ? phone : '+91$phone',
        },
        'theme': {'color': '#06B6D4'},
        'notes': {
          'booking_id': _pendingBookingId,
        },
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
    return DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day, hh, mm);
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
    final c1 = _isInstant ? const Color(0xFF10B981) : AppTheme.primary;
    final c2 = _isInstant ? const Color(0xFF059669) : const Color(0xFF0891B2);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(children: [
        _buildHeader(c1, c2),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
            child: _buildStepContent(),
          ),
        ),
      ]),
      bottomNavigationBar: _buildBottomBar(c1, c2),
    );
  }

  Widget _buildHeader(Color c1, Color c2) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [c1, c2]),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              GestureDetector(
                onTap: () { if (_step > 1) setState(() => _step--); else Navigator.pop(context); },
                child: Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.22), borderRadius: BorderRadius.circular(11)),
                  child: const Icon(Icons.arrow_back_ios_new_rounded, color: Colors.white, size: 16),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  Text(_isInstant ? '⚡' : '📅', style: const TextStyle(fontSize: 16)),
                  const SizedBox(width: 6),
                  Text(_isInstant ? 'Instant Booking' : 'Schedule Booking',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
                ]),
                Text(_isInstant ? 'Pro arrives within 2 hours' : 'Choose your date & time',
                  style: TextStyle(color: Colors.white.withOpacity(0.80), fontSize: 11)),
              ])),
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text('₹$_finalAmount',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
                Text(_discount > 0 ? '-₹$_discount saved' : 'Total',
                  style: TextStyle(color: Colors.white.withOpacity(0.75), fontSize: 10)),
              ]),
            ]),
            const SizedBox(height: 18),
            Row(children: List.generate(_stepLabels.length, (i) {
              final s = i + 1; final active = _step == s; final done = _step > s;
              return Expanded(child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 26, height: 26,
                  decoration: BoxDecoration(
                    color: done || active ? Colors.white : Colors.white.withOpacity(0.25),
                    shape: BoxShape.circle),
                  child: Center(child: done
                    ? Icon(Icons.check_rounded, color: c1, size: 14)
                    : Text('$s', style: TextStyle(
                        color: done || active ? c1 : Colors.white.withOpacity(0.7),
                        fontSize: 11, fontWeight: FontWeight.w900))),
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(_stepLabels[i],
                  style: TextStyle(
                    color: active ? Colors.white : Colors.white.withOpacity(done ? 0.8 : 0.5),
                    fontSize: 11, fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis)),
                if (i < _stepLabels.length - 1)
                  Expanded(child: Container(height: 1,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    color: Colors.white.withOpacity(done ? 0.6 : 0.25))),
              ]));
            })),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _step / _totalSteps,
                backgroundColor: Colors.white.withOpacity(0.22),
                valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                minHeight: 5),
            ),
          ]),
        ),
      ),
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

  Widget _buildDateTimeStep() {
    return Column(children: [
      _card(icon: Icons.calendar_month_rounded, title: 'Choose Date', sub: 'Select your preferred date',
        child: SizedBox(height: 90, child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: _dates.length,
          separatorBuilder: (_, __) => const SizedBox(width: 10),
          itemBuilder: (_, i) {
            final d = _dates[i]; final active = d.day == _selectedDate.day && d.month == _selectedDate.month;
            return GestureDetector(
              onTap: () { setState(() => _selectedDate = d); HapticFeedback.selectionClick(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180), width: 56,
                decoration: BoxDecoration(
                  color: active ? AppTheme.primary : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: active ? AppTheme.primary : const Color(0xFFE8EDF2)),
                  boxShadow: active ? [BoxShadow(color: AppTheme.primary.withOpacity(0.40), blurRadius: 12, offset: const Offset(0,4))] : []),
                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d.weekday-1],
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                      color: active ? const Color(0xFFBAE6FD) : const Color(0xFF94A3B8))),
                  Text('${d.day}', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                    color: active ? Colors.white : const Color(0xFF0F172A))),
                  Text(i==0?'TODAY':'·', style: TextStyle(fontSize: 8, fontWeight: FontWeight.w900,
                    color: active ? Colors.white : (i==0 ? AppTheme.primary : Colors.transparent))),
                ]),
              ),
            );
          },
        )),
      ),
      const SizedBox(height: 14),
      _card(icon: Icons.access_time_rounded, title: 'Choose Time', sub: 'Pick a convenient slot',
        child: GridView.count(
          shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 3, childAspectRatio: 2.2, crossAxisSpacing: 10, mainAxisSpacing: 10,
          children: _timeSlots.map((slot) {
            final active = _selectedTime == slot;
            return GestureDetector(
              onTap: () { setState(() => _selectedTime = slot); HapticFeedback.selectionClick(); },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                decoration: BoxDecoration(
                  color: active ? AppTheme.primary : const Color(0xFFF9FAFB),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? AppTheme.primary : const Color(0xFFE8EDF2)),
                  boxShadow: active ? [BoxShadow(color: AppTheme.primary.withOpacity(0.38), blurRadius: 10, offset: const Offset(0,3))] : []),
                child: Center(child: Text(slot, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800,
                  color: active ? Colors.white : const Color(0xFF334155)))),
              ),
            );
          }).toList(),
        ),
      ),
    ]);
  }

  Widget _buildAddressStep() {
    return Column(children: [
      if (_isInstant)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFFECFDF5), Color(0xFFD1FAE5)]),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF6EE7B7))),
          child: const Row(children: [
            Text('⚡', style: TextStyle(fontSize: 28)),
            SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Instant Booking!', style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w900, fontSize: 14)),
              SizedBox(height: 2),
              Text('A verified pro will be dispatched within 2 hours.', style: TextStyle(color: Color(0xFF047857), fontSize: 12)),
            ])),
          ]),
        ),

      _card(
        icon: Icons.location_on_rounded, title: 'Service Address', sub: 'Where should we come?',
        trailing: GestureDetector(
          onTap: () => context.go('/account'),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFECFEFF), borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFA5F3FC))),
            child: const Text('+ Add', style: TextStyle(color: AppTheme.primary, fontSize: 12, fontWeight: FontWeight.w800)),
          ),
        ),
        child: _addresses.isEmpty
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Column(children: [
                Text('📍', style: TextStyle(fontSize: 38)),
                SizedBox(height: 10),
                Text('No saved addresses', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151))),
                SizedBox(height: 4),
                Text('Add an address to continue', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
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
                    color: active ? const Color(0xFFECFEFF) : const Color(0xFFF9FAFB),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: active ? AppTheme.primary : const Color(0xFFE8EDF2), width: active ? 2 : 1)),
                  child: Row(children: [
                    Container(width: 38, height: 38,
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFE8EDF2))),
                      child: Center(child: Text(icon, style: const TextStyle(fontSize: 18)))),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Row(children: [
                        Text(lbl, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14)),
                        if (addr['is_default'] == true) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                            decoration: BoxDecoration(color: const Color(0xFFECFEFF), borderRadius: BorderRadius.circular(20)),
                            child: const Text('Default', style: TextStyle(color: AppTheme.primary, fontSize: 9, fontWeight: FontWeight.w800))),
                        ],
                      ]),
                      const SizedBox(height: 2),
                      Text(
                        [if (addr['flat_no'] != null) addr['flat_no'], if (addr['building'] != null) addr['building'], addr['area'], addr['city']].where((e) => e != null).join(', '),
                        style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                    ])),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 22, height: 22,
                      decoration: BoxDecoration(
                        color: active ? AppTheme.primary : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(color: active ? AppTheme.primary : const Color(0xFFD1D5DB), width: 2)),
                      child: active ? const Icon(Icons.check_rounded, color: Colors.white, size: 12) : null),
                  ]),
                ),
              );
            }).toList()),
      ),
      const SizedBox(height: 14),
      _card(icon: Icons.chat_bubble_outline_rounded, title: 'Special Instructions', sub: 'Optional notes for the cleaner',
        child: TextField(
          controller: _notesCtrl, maxLines: 3,
          decoration: InputDecoration(
            hintText: 'e.g. Ring bell twice, pet at home...',
            hintStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
            filled: true, fillColor: const Color(0xFFF9FAFB),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE8EDF2))),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: Color(0xFFE8EDF2))),
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: AppTheme.primary))),
        ),
      ),
    ]);
  }

  Widget _buildConfirmStep() {
    final addr = _addresses.firstWhere((a) => a['id'] == _selectedAddressId, orElse: () => {});
    final rows = [
      {'icon': '🧹', 'label': 'Services', 'value': widget.cartItems != null ? '${widget.cartItems!.length} service${widget.cartItems!.length>1?'s':''}' : (_service?['name'] ?? '—')},
      if (_isSchedule) ...[
        {'icon': '📅', 'label': 'Date', 'value': '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'},
        {'icon': '⏰', 'label': 'Time', 'value': _selectedTime},
      ],
      if (_isInstant) {'icon': '⚡', 'label': 'Arrival', 'value': 'Within 2 hours'},
      {'icon': '📍', 'label': 'Address', 'value': addr.isNotEmpty ? '${addr['area']}, ${addr['city']}' : '—'},
      if (_notesCtrl.text.isNotEmpty) {'icon': '💬', 'label': 'Notes', 'value': _notesCtrl.text},
    ];

    return Column(children: [
      // Summary
      _card(icon: Icons.receipt_long_rounded, title: 'Booking Summary', sub: 'Review before confirming',
        child: Column(children: rows.map((r) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: const Color(0xFFF3F4F6), borderRadius: BorderRadius.circular(10)),
              child: Center(child: Text(r['icon']!, style: const TextStyle(fontSize: 16)))),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r['label']!, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              Text(r['value']!, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
            ])),
          ]),
        )).toList()),
      ),
      const SizedBox(height: 14),

      // ── Promo Selector ────────────────────────────────────────
      GestureDetector(
        onTap: _showPromoSheet,
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: _appliedPromoCode.isNotEmpty ? const Color(0xFF6EE7B7) : const Color(0xFFE8EDF2),
              width: _appliedPromoCode.isNotEmpty ? 1.5 : 1),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0,3))]),
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              child: Row(children: [
                Container(
                  width: 36, height: 36,
                  decoration: BoxDecoration(
                    color: _appliedPromoCode.isNotEmpty ? const Color(0xFFECFDF5) : const Color(0xFFF5F3FF),
                    borderRadius: BorderRadius.circular(11)),
                  child: Center(child: Text(_appliedPromoCode.isNotEmpty ? '🎉' : '🎟',
                    style: const TextStyle(fontSize: 18)))),
                const SizedBox(width: 12),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(
                    _appliedPromoCode.isNotEmpty ? 'Promo Applied!' : 'Apply Promo Code',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14,
                      color: _appliedPromoCode.isNotEmpty ? const Color(0xFF059669) : const Color(0xFF0F172A))),
                  Text(
                    _appliedPromoCode.isNotEmpty
                      ? '$_appliedPromoCode  •  Saving ₹$_discount'
                      : _promos.isEmpty && !_promosLoading
                          ? 'No offers available right now'
                          : 'Tap to see ${_promos.length} available offer${_promos.length==1?'':'s'}',
                    style: TextStyle(
                      color: _appliedPromoCode.isNotEmpty ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                      fontSize: 11)),
                ])),
                if (_appliedPromoCode.isNotEmpty)
                  GestureDetector(
                    onTap: _removePromo,
                    child: Container(
                      width: 28, height: 28,
                      decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(8)),
                      child: const Icon(Icons.close_rounded, size: 14, color: Color(0xFFDC2626))))
                else
                  Icon(Icons.chevron_right_rounded,
                    color: _promos.isEmpty ? const Color(0xFFD1D5DB) : const Color(0xFF94A3B8)),
              ]),
            ),
            if (_appliedPromoCode.isNotEmpty) ...[
              const Divider(height: 1, color: Color(0xFFF0FDF4)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: const BoxDecoration(
                  color: Color(0xFFF0FDF4),
                  borderRadius: BorderRadius.only(bottomLeft: Radius.circular(20), bottomRight: Radius.circular(20))),
                child: Row(children: [
                  const Icon(Icons.check_circle_rounded, color: Color(0xFF10B981), size: 16),
                  const SizedBox(width: 8),
                  Text('₹$_discount discount applied to your order',
                    style: const TextStyle(color: Color(0xFF059669), fontSize: 12, fontWeight: FontWeight.w600)),
                ]),
              ),
            ],
          ]),
        ),
      ),
      const SizedBox(height: 14),

      // ── Price breakdown ───────────────────────────────────────
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: AppTheme.primary.withOpacity(0.30), blurRadius: 16, offset: const Offset(0,4))]),
        child: Column(children: [
          _priceRow('Service total', '₹$_baseAmount', Colors.white.withOpacity(0.85), Colors.white),
          if (_discount > 0)
            _priceRow('Promo ($_appliedPromoCode)', '− ₹$_discount', Colors.white.withOpacity(0.85), const Color(0xFF86EFAC)),
          _priceRow('Platform fee', 'FREE', Colors.white.withOpacity(0.85), const Color(0xFF86EFAC)),
          const Divider(color: Colors.white24, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total Payable', style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            Text('₹$_finalAmount', style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 8),
          // Payment methods row
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
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: TextStyle(color: lc, fontSize: 13)),
      Text(v, style: TextStyle(color: vc, fontSize: 13, fontWeight: FontWeight.bold)),
    ]));

  Widget _card({required IconData icon, required String title, required String sub, required Widget child, Widget? trailing}) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 12, offset: const Offset(0,3))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Row(children: [
            Container(width: 36, height: 36,
              decoration: BoxDecoration(color: AppTheme.primary, borderRadius: BorderRadius.circular(11)),
              child: Icon(icon, color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Color(0xFF0F172A))),
              Text(sub, style: const TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
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
      padding: EdgeInsets.fromLTRB(16, 12, 16, 12 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 16, offset: const Offset(0,-4))]),
      child: Row(children: [
        if (_step > 1) ...[
          GestureDetector(
            onTap: () => setState(() => _step--),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(16)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF64748B), size: 18))),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: GestureDetector(
            onTap: canProceed && !_loading ? () {
              if (isLast) _proceedToPayment();
              else setState(() => _step++);
            } : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              decoration: BoxDecoration(
                gradient: canProceed ? LinearGradient(colors: [c1, c2]) : null,
                color: canProceed ? null : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(16),
                boxShadow: canProceed ? [BoxShadow(color: c1.withOpacity(0.42), blurRadius: 16, offset: const Offset(0,5))] : []),
              child: Center(
                child: _loading
                  ? const SizedBox(width: 22, height: 22,
                      child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                  : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                      if (isLast) const Text('💳  ', style: TextStyle(fontSize: 16)),
                      Text(
                        isLast ? 'Pay ₹$_finalAmount' : 'Continue',
                        style: TextStyle(
                          color: canProceed ? Colors.white : const Color(0xFF94A3B8),
                          fontSize: 15, fontWeight: FontWeight.w900)),
                      const SizedBox(width: 8),
                      Icon(
                        isLast ? Icons.arrow_forward_rounded : Icons.arrow_forward_rounded,
                        color: canProceed ? Colors.white : const Color(0xFF94A3B8), size: 18),
                    ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }

  bool _canProceed() {
    if (_isSchedule && _step == 1) return _selectedTime.isNotEmpty;
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

  const _PromoSheet({
    required this.promos, required this.usedPromos,
    required this.appliedId, required this.baseAmount,
    required this.loading, required this.onApply, required this.onRemove,
  });

  String _calcDiscount(Map<String, dynamic> p) {
    final type  = p['discount_type'] as String? ?? 'percent';
    final value = (p['discount_value'] as num? ?? 0).toDouble();
    final max   = p['max_discount_amount'] != null ? (p['max_discount_amount'] as num).toInt() : 9999;
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
        Container(margin: const EdgeInsets.only(top: 10), width: 40, height: 4,
          decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            const Text('🎟', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Choose Promo Code', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
              Text('Select an offer to apply on your booking', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11)),
            ])),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFF64748B)))),
          ]),
        ),
        const Divider(height: 1),
        Expanded(
          child: loading
            ? const Center(child: CircularProgressIndicator(color: AppTheme.primary))
            : (promos.isEmpty && usedPromos.isEmpty)
              ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text('🎟', style: TextStyle(fontSize: 40)),
                  SizedBox(height: 12),
                  Text('No offers available', style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151))),
                  SizedBox(height: 4),
                  Text('Check back soon!', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                ]))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                  children: [
                    if (promos.isNotEmpty) ...[
                      const Padding(
                        padding: EdgeInsets.only(bottom: 10, left: 4),
                        child: Text('AVAILABLE OFFERS', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5))),
                      ...promos.map((p) {
                        final isApplied = appliedId == p['id'].toString();
                        final minOrder  = p['min_order_amount'] != null ? (p['min_order_amount'] as num).toInt() : 0;
                        final canApply  = baseAmount >= minOrder;

                        return GestureDetector(
                          onTap: canApply ? () => onApply(p) : null,
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isApplied ? const Color(0xFFECFDF5) : canApply ? Colors.white : const Color(0xFFF8FAFC),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isApplied ? const Color(0xFF6EE7B7) : canApply ? const Color(0xFFE8EDF2) : const Color(0xFFF1F5F9),
                                width: isApplied ? 1.5 : 1)),
                            child: Row(children: [
                              Container(
                                width: 52, height: 52,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(colors: isApplied
                                    ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                    : canApply
                                      ? [const Color(0xFF6366F1), const Color(0xFF4F46E5)]
                                      : [const Color(0xFFCBD5E1), const Color(0xFF94A3B8)]),
                                  borderRadius: BorderRadius.circular(14)),
                                child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                  Text(
                                    (p['discount_type'] as String?) == 'percent'
                                      ? '${(p['discount_value'] as num).toInt()}%'
                                      : '₹${(p['discount_value'] as num).toInt()}',
                                    style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w900)),
                                  const Text('OFF', style: TextStyle(color: Colors.white70, fontSize: 8, fontWeight: FontWeight.bold)),
                                ]),
                              ),
                              const SizedBox(width: 12),
                              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Row(children: [
                                  Text(p['code'] as String,
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, letterSpacing: 1,
                                      color: isApplied ? const Color(0xFF059669) : canApply ? const Color(0xFF0F172A) : const Color(0xFF94A3B8))),
                                  if (isApplied) ...[
                                    const SizedBox(width: 6),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(6)),
                                      child: const Text('Applied', style: TextStyle(color: Color(0xFF16A34A), fontSize: 9, fontWeight: FontWeight.w800))),
                                  ],
                                ]),
                                const SizedBox(height: 2),
                                if ((p['description'] as String? ?? '').isNotEmpty)
                                  Text(p['description'] as String,
                                    style: TextStyle(color: canApply ? const Color(0xFF6B7280) : const Color(0xFFD1D5DB), fontSize: 11),
                                    maxLines: 1, overflow: TextOverflow.ellipsis),
                                const SizedBox(height: 4),
                                Text(_calcDiscount(p),
                                  style: TextStyle(
                                    color: isApplied ? const Color(0xFF10B981) : canApply ? const Color(0xFF6366F1) : const Color(0xFFD1D5DB),
                                    fontSize: 11, fontWeight: FontWeight.w700)),
                                if (!canApply)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 3),
                                    child: Text('Min order ₹$minOrder required',
                                      style: const TextStyle(color: Color(0xFFEF4444), fontSize: 10, fontWeight: FontWeight.w600))),
                              ])),
                              if (isApplied)
                                GestureDetector(
                                  onTap: () { onRemove(); Navigator.pop(context); },
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(10)),
                                    child: const Text('Remove', style: TextStyle(color: Color(0xFFDC2626), fontSize: 11, fontWeight: FontWeight.w700))))
                              else if (canApply)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                  decoration: BoxDecoration(color: const Color(0xFFEEF2FF), borderRadius: BorderRadius.circular(10)),
                                  child: const Text('Apply', style: TextStyle(color: Color(0xFF6366F1), fontSize: 11, fontWeight: FontWeight.w800))),
                            ]),
                          ),
                        );
                      }),
                    ],

                    if (usedPromos.isNotEmpty) ...[
                      Padding(
                        padding: EdgeInsets.only(top: promos.isNotEmpty ? 8 : 0, bottom: 10, left: 4),
                        child: Row(children: const [
                          Text('ALREADY USED', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                          SizedBox(width: 8),
                          Text('• One use per account', style: TextStyle(color: Color(0xFFD1D5DB), fontSize: 10)),
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
                              decoration: BoxDecoration(color: const Color(0xFFE2E8F0), borderRadius: BorderRadius.circular(14)),
                              child: const Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                                Icon(Icons.check_circle_rounded, color: Color(0xFF94A3B8), size: 22),
                                Text('USED', style: TextStyle(color: Color(0xFFCBD5E1), fontSize: 8, fontWeight: FontWeight.bold)),
                              ])),
                            const SizedBox(width: 12),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(p['code'] as String,
                                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: Color(0xFF94A3B8),
                                  letterSpacing: 1, decoration: TextDecoration.lineThrough)),
                              const SizedBox(height: 2),
                              if ((p['description'] as String? ?? '').isNotEmpty)
                                Text(p['description'] as String,
                                  style: const TextStyle(color: Color(0xFFCBD5E1), fontSize: 11),
                                  maxLines: 1, overflow: TextOverflow.ellipsis),
                            ])),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(10)),
                              child: const Text('Used', style: TextStyle(color: Color(0xFF94A3B8), fontSize: 11, fontWeight: FontWeight.w700))),
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