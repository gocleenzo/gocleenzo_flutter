import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import '../../services/supabase_service.dart';
import '../../services/cart_service.dart';
import 'booking_detail_screen.dart';
import 'package:razorpay_flutter/razorpay_flutter.dart';

/// Small plain wrapper (avoids relying on Dart 3 record-type syntax, for
/// broader SDK compatibility) holding date-specific worker schedule data
/// fetched in one query. See _fetchWorkerScheduleDates.
class _WorkerScheduleLookup {
  final Map<String, Map<String, Map<String, dynamic>>> byWorkerDate;
  final Set<String> hasAny;
  _WorkerScheduleLookup(this.byWorkerDate, this.hasAny);
}

class BookingFlowScreen extends StatefulWidget {
  final String  mode;
  final String? serviceId;
  final List<Map<String, dynamic>>? cartItems;
  final int?    overridePrice;
  final int?    overrideDuration;
  final int?    rawDurationMins;
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
    this.rawDurationMins,
    this.selectedBhk,
    this.quantity,
    this.isFirstBooking = false,
  });

  @override
  State<BookingFlowScreen> createState() => _BookingFlowScreenState();
}

class _BookingFlowScreenState extends State<BookingFlowScreen> {
  final _supabase = Supabase.instance.client;

  static const _cyan     = Color(0xFF06B6D4);
  static const _cyanDk   = Color(0xFF0891B2);
  static const _cyanDeep = Color(0xFF0E7490);
  static const _cyanBg   = Color(0xFFECFEFF);
  static const _cyanBg2  = Color(0xFFD6F6FB);
  static const _border   = Color(0xFFE8EDF2);
  static const _line     = Color(0xFFF1F5F9);
  static const _ink      = Color(0xFF0F172A);
  static const _muted    = Color(0xFF64748B);
  static const _faint    = Color(0xFF94A3B8);
  static const _bg       = Color(0xFFF8FAFC);
  static const _green    = Color(0xFF10B981);
  static const _greenDk  = Color(0xFF059669);

  static const _instantStartHour = 7;
  static const _instantEndHour   = 19;
  static const _minNoticeMins = 30;
  static const _travelBufferMins = 30;

  int  _step    = 1;
  bool _loading = false;
  bool _checkingInstant = false;
  bool _initializing = true;

  late Razorpay _razorpay;
  static const _razorpayKey = 'rzp_live_TJIl6FAZg8I1ru';

  DateTime _selectedDate = DateTime.now();
  String   _selectedTime = '';

  List<Map<String, dynamic>> _addresses         = [];
  String                     _selectedAddressId = '';

  List<Map<String, dynamic>> _promos      = [];
  List<Map<String, dynamic>> _usedPromos  = [];
  Set<String>                _usedPromoIds = {};
  bool   _promosLoading    = false;
  String _appliedPromoId   = '';
  String _appliedPromoCode = '';
  int    _discount         = 0;

  int  _platformFee       = 5;
  int  _searchFee         = 19;
  bool _searchFeeEnabled  = true;
  bool _settingsLoading   = true;

  final _notesCtrl = TextEditingController();

  Map<String, dynamic>? _service;

  Map<String, bool> _slotAvailability = {};
  bool _slotsLoading = false;

  bool get _isSchedule => widget.mode == 'schedule';
  bool get _isInstant  => widget.mode == 'instant';
  int  get _totalSteps => _isSchedule ? 3 : 2;
  int  get _addressStep => _isSchedule ? 2 : 1;

  List<String> get _stepLabels => _isSchedule
      ? ['Date & Time', 'Address', 'Confirm']
      : ['Address', 'Confirm'];

  static const List<IconData> _stepIcons = [
    Icons.event_rounded, Icons.location_on_rounded, Icons.task_alt_rounded,
  ];

  static const _timeSlots = [
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

  List<DateTime> get _dates =>
      List.generate(7, (i) => DateTime.now().add(Duration(days: i)));

  int get _baseAmount {
    if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
      return widget.cartItems!.fold(0, (s, c) => s + (c['price'] as num).toInt());
    }
    if (widget.overridePrice != null) return widget.overridePrice!;
    return (_service?['base_price'] as num?)?.toInt() ?? 0;
  }

  int get _feesTotal =>
      _platformFee + (_searchFeeEnabled ? _searchFee : 0);

  int get _finalAmount =>
      (_baseAmount - _discount + _feesTotal).clamp(0, 999999);

  static int _roundUpToHour(int mins) =>
      mins <= 0 ? 30 : ((mins / 30).ceil()) * 30;

  int get _serviceDurationMins {
    if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
      int total = 0;
      for (final item in widget.cartItems!) {
        total += (item['duration_minutes'] as num?)?.toInt() ?? 60;
      }
      return total > 0 ? total : 60;
    }
    if (widget.overrideDuration != null) return widget.overrideDuration!;
    return (_service?['duration_minutes'] as num?)?.toInt() ?? 60;
  }

  int get _slotsBlocked => (_serviceDurationMins / 60).ceil();

  int get _rawServiceDurationMins {
    if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
      int total = 0;
      for (final item in widget.cartItems!) {
        total += (item['duration_minutes'] as num?)?.toInt() ?? 60;
      }
      return total > 0 ? total : 60;
    }
    if (widget.rawDurationMins != null) return widget.rawDurationMins!;
    final dbRaw = (_service?['duration_minutes'] as num?)?.toInt();
    return dbRaw ?? _serviceDurationMins;
  }

  String? _userId;
  String? _pendingAttemptRef;
  String? _pendingBookingOtp;
  String? _userPhone;
  String? _userEmail;

  String get _serviceLabel {
    if (widget.cartItems != null) {
      return '${widget.cartItems!.length} service'
          '${widget.cartItems!.length > 1 ? 's' : ''}';
    }
    final name = _service?['name'] as String? ?? '—';
    if (widget.selectedBhk != null) return '$name · ${widget.selectedBhk}';
    if (widget.quantity != null && widget.quantity! > 1) {
      return '$name · ×${widget.quantity}';
    }
    return name;
  }

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR,   _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _loadData();
    if (_isInstant) _step = 1;
  }

  @override
  void dispose() {
    _razorpay.clear();
    _notesCtrl.dispose();
    super.dispose();
  }

  // ── Load data ────────────────────────────────────────────────
  Future<void> _loadData() async {
    _userId = await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (_userId == null) { if (mounted) context.go('/login'); return; }
    final userId = _userId!;

    final futures = <Future>[
      _supabase.from('addresses').select('*')
          .eq('user_id', userId)
          .eq('is_deleted', false),
      _supabase.from('users').select('phone, email')
          .eq('id', userId).maybeSingle(),
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
      final userRow = results[1] as Map<String, dynamic>?;
      _userPhone = userRow?['phone'] as String?;
      _userEmail = userRow?['email'] as String?;
      if (widget.serviceId != null && results.length > 2) {
        _service = results[2] as Map<String, dynamic>;
      }
    });

    if (_addresses.isNotEmpty && !await _isSelectedAddressServiceable()) {
      if (!mounted) return;
      _showAreaNotServiceableDialog(onDismiss: () {
        if (mounted && Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      });
      return;
    }

    if (!widget.isFirstBooking) _loadPromos();
    if (_isSchedule) _loadSlotAvailability(_selectedDate);
    _loadAppSettings();

    if (mounted) setState(() => _initializing = false);
  }

  Future<void> _loadAppSettings() async {
    try {
      final data = await _supabase
          .from('app_settings')
          .select('platform_fee, search_fee, search_fee_enabled')
          .eq('id', 'global')
          .single();
      if (mounted) {
        setState(() {
        _platformFee      = (data['platform_fee'] as num?)?.toInt() ?? 5;
        _searchFee        = (data['search_fee'] as num?)?.toInt() ?? 19;
        _searchFeeEnabled = data['search_fee_enabled'] as bool? ?? true;
        _settingsLoading  = false;
      });
      }
    } catch (e) {
      debugPrint('app_settings load error: $e');
      if (mounted) setState(() => _settingsLoading = false);
    }
  }

  Future<Set<String>?> _resolveZoneRestrictedWorkerIds() async {
    try {
      final addr = _addresses.firstWhere(
          (a) => a['id'] == _selectedAddressId, orElse: () => {});
      final pincode = (addr['pincode'] as String?)?.trim();
      if (pincode == null || pincode.isEmpty) return null;

      final assignments = await _supabase
          .from('worker_pincodes')
          .select('worker_id')
          .eq('pincode', pincode);
      final ids = (assignments as List)
          .map((r) => r['worker_id'] as String)
          .toSet();
      return ids.isEmpty ? null : ids;
    } catch (e) {
      debugPrint('Pincode eligibility check failed (failing open): $e');
      return null;
    }
  }

  Future<_WorkerScheduleLookup> _fetchWorkerScheduleDates(
      List<String> workerIds) async {
    if (workerIds.isEmpty) return _WorkerScheduleLookup({}, {});
    final rows = await _supabase
        .from('worker_schedule_dates')
        .select('worker_id, date, enabled, start_time, end_time, breaks')
        .inFilter('worker_id', workerIds);
    final byWorkerDate = <String, Map<String, Map<String, dynamic>>>{};
    final hasAny = <String>{};
    for (final row in (rows as List).cast<Map<String, dynamic>>()) {
      final wId = row['worker_id'] as String;
      hasAny.add(wId);
      byWorkerDate.putIfAbsent(wId, () => {});
      byWorkerDate[wId]![row['date'].toString()] = {
        'enabled': row['enabled'] == true,
        'start': row['start_time']?.toString() ?? '09:00',
        'end': row['end_time']?.toString() ?? '17:00',
        'breaks': List<Map<String, dynamic>>.from((row['breaks'] as List?) ?? const []),
      };
    }
    return _WorkerScheduleLookup(byWorkerDate, hasAny);
  }

  bool _isWorkerScheduledForDate(
    String workerId, DateTime slotDt, int durationMins,
    _WorkerScheduleLookup lookup,
  ) {
    final dateStr = '${slotDt.year.toString().padLeft(4, '0')}-'
        '${slotDt.month.toString().padLeft(2, '0')}-'
        '${slotDt.day.toString().padLeft(2, '0')}';
    final slotMins    = slotDt.hour * 60 + slotDt.minute;
    final slotEndMins = slotMins + durationMins;

    final entry = lookup.byWorkerDate[workerId]?[dateStr];
    if (entry == null) {
      if (lookup.hasAny.contains(workerId)) return false;
      return slotMins >= 420 && slotEndMins <= 1140;
    }
    if (entry['enabled'] != true) return false;
    final startMins = _timeToMins(entry['start'] as String);
    final endMins   = _timeToMins(entry['end'] as String);
    if (slotMins < startMins || slotEndMins > endMins) return false;
    for (final b in (entry['breaks'] as List)) {
      final bStart = _timeToMins(b['from'] as String);
      final bEnd   = _timeToMins(b['to'] as String);
      if (bStart < slotEndMins && bEnd > slotMins) return false;
    }
    return true;
  }


  Future<String?> _checkInstantAvailabilityReason() async {
    final now          = DateTime.now();
    final hour         = now.hour;
    final durationMins = _serviceDurationMins;


    if (hour < _instantStartHour || hour >= _instantEndHour) {
      return 'time_window';
    }

    final serviceEndMins = (now.hour * 60 + now.minute) + durationMins;
    if (serviceEndMins > _instantEndHour * 60) {
      return 'time_window';
    }

    try {
      final workersData = await _supabase
          .from('workers')
          .select('user_id, is_available')
          .eq('is_available', true);
      var workers = (workersData as List).cast<Map<String, dynamic>>();

      final eligibleIds = await _resolveZoneRestrictedWorkerIds();
      if (eligibleIds != null) {
        workers = workers
            .where((w) => eligibleIds.contains(w['user_id']))
            .toList();
      }

      if (workers.isEmpty) return 'no_workers';

      final activeBookingsData = await _supabase
          .from('bookings')
          .select('worker_id, scheduled_at, work_started_at, extra_time_mins, booking_duration_minutes, address_id, services(duration_minutes)')
          .inFilter('status', ['accepted', 'in_progress'])
          .inFilter('payment_status', ['cod', 'paid']);
      final activeBookings = (activeBookingsData as List).cast<Map<String, dynamic>>();

      final workerIds = workers.map((w) => w['user_id'] as String).toList();
      final scheduleLookup = await _fetchWorkerScheduleDates(workerIds);

      for (final worker in workers) {
        final workerId = worker['user_id'] as String;

        if (!_isWorkerScheduledForDate(workerId, now, durationMins, scheduleLookup)) {
          continue;
        }

        if (!_isWorkerFreeAtSlot(workerId, now, durationMins,
            activeBookings, newAddressId: _selectedAddressId)) {
          continue;
        }

        return null;
      }

      return 'no_workers';
    } catch (e) {
      debugPrint('Instant availability check error: $e');
      return null;
    }
  }

  Future<void> _checkInstantAndProceed() async {
    setState(() => _checkingInstant = true);
    final reason = await _checkInstantAvailabilityReason();
    if (!mounted) return;
    setState(() => _checkingInstant = false);

    if (reason == null) {
      setState(() => _step++);
      return;
    }

    if (reason == 'time_window') {
      _showInstantTimeWindowDialog();
    } else {
      _showNoWorkersDialog();
    }
  }

  void _showInstantTimeWindowDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 64, height: 64,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF7ED),
                shape: BoxShape.circle),
              child: const Center(
                  child: Text('🕐', style: TextStyle(fontSize: 32)))),
            const SizedBox(height: 18),
            const Text('Instant Booking\nNot Available Now',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18,
                    fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 10),
            const Text(
              'Instant bookings are available between\n7:00 AM – 7:00 PM only.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _cyanBg,
                borderRadius: BorderRadius.circular(12)),
              child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                Icon(Icons.wb_sunny_rounded,
                    color: _cyanDk, size: 16),
                SizedBox(width: 8),
                Text('Available: 7:00 AM – 7:00 PM',
                    style: TextStyle(color: _cyanDeep,
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ])),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(ctx),
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _bg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border)),
                    child: const Text('OK',
                        style: TextStyle(color: _muted,
                            fontSize: 15, fontWeight: FontWeight.w800)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(ctx);
                    Navigator.pushReplacement(context, MaterialPageRoute(
                      builder: (_) => BookingFlowScreen(
                        mode:             'schedule',
                        serviceId:        widget.serviceId,
                        cartItems:        widget.cartItems,
                        overridePrice:    widget.overridePrice,
                        overrideDuration: widget.overrideDuration,
                        selectedBhk:      widget.selectedBhk,
                        quantity:         widget.quantity,
                        isFirstBooking:   widget.isFirstBooking,
                      ),
                    ));
                  },
                  child: Container(
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_cyan, _cyanDeep]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                          color: _cyan.withValues(alpha: 0.32),
                          blurRadius: 10, offset: const Offset(0, 4))]),
                    child: const Text('Schedule Instead',
                        style: TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );
  }

  void _showNoWorkersDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED),
                  shape: BoxShape.circle),
                child: const Center(
                    child: Text('👷', style: TextStyle(fontSize: 32)))),
              const SizedBox(height: 18),
              const Text('All Pros Are Busy\nRight Now',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w900, color: _ink)),
              const SizedBox(height: 10),
              const Text(
                'All our professionals are currently occupied.\nSchedule a time that works for you instead.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: _cyanBg,
                  borderRadius: BorderRadius.circular(12)),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.calendar_month_rounded,
                      color: _cyanDk, size: 16),
                  SizedBox(width: 8),
                  Text('Pick a slot that suits you',
                      style: TextStyle(color: _cyanDeep,
                          fontSize: 13, fontWeight: FontWeight.w800)),
                ])),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  Navigator.pushReplacement(context, MaterialPageRoute(
                    builder: (_) => BookingFlowScreen(
                      mode:             'schedule',
                      serviceId:        widget.serviceId,
                      cartItems:        widget.cartItems,
                      overridePrice:    widget.overridePrice,
                      overrideDuration: widget.overrideDuration,
                      selectedBhk:      widget.selectedBhk,
                      quantity:         widget.quantity,
                      isFirstBooking:   widget.isFirstBooking,
                    ),
                  ));
                },
                child: Container(
                  width: double.infinity,
                  height: 52,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_cyan, _cyanDeep]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: _cyan.withValues(alpha: 0.32),
                        blurRadius: 10, offset: const Offset(0, 4))]),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.calendar_month_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Schedule Instead',
                        style: TextStyle(color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity,
                  height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                  child: const Text('Try Again Later',
                      style: TextStyle(color: _muted,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
    );
  }

  Future<void> _loadSlotAvailability(DateTime date) async {
    setState(() { _slotsLoading = true; _slotAvailability = {}; });
    try {
      final workersData = await _supabase
          .from('workers')
          .select('user_id, is_available')
          .eq('is_available', true);
      var workers = (workersData as List).cast<Map<String, dynamic>>();

      final eligibleIds = await _resolveZoneRestrictedWorkerIds();
      if (eligibleIds != null) {
        workers = workers
            .where((w) => eligibleIds.contains(w['user_id']))
            .toList();
      }

      final dateStr = '${date.year}-'
          '${date.month.toString().padLeft(2, '0')}-'
          '${date.day.toString().padLeft(2, '0')}';
      final holidaysData = await _supabase
          .from('worker_holidays')
          .select('worker_id')
          .eq('holiday_date', dateStr);
      final holidayWorkerIds = (holidaysData as List)
          .map((h) => h['worker_id'].toString()).toSet();

      final dayStartUtc =
          DateTime(date.year, date.month, date.day, 0, 0, 0).toUtc();
      final dayEndUtc =
          DateTime(date.year, date.month, date.day, 23, 59, 59).toUtc();

      final bookingsData = await _supabase
          .from('bookings')
          .select('worker_id, scheduled_at, work_started_at, extra_time_mins, booking_duration_minutes, address_id, services(duration_minutes)')
          .inFilter('status', ['accepted', 'in_progress', 'pending'])
          .inFilter('payment_status', ['cod', 'paid'])
          .gte('scheduled_at', dayStartUtc.subtract(const Duration(hours: 6)).toIso8601String())
          .lte('scheduled_at', dayEndUtc.toIso8601String());
      final bookings = (bookingsData as List).cast<Map<String, dynamic>>();

      final now      = DateTime.now();
      final cutoff   = now.add(const Duration(minutes: _minNoticeMins));
      final durationMins = _serviceDurationMins;
      debugPrint('SLOT DEBUG (schedule): durationMins=$durationMins, cartItems=${widget.cartItems}, overrideDuration=${widget.overrideDuration}');

      final workerIds = workers.map((w) => w['user_id'] as String).toList();
      final scheduleLookup = await _fetchWorkerScheduleDates(workerIds);

      final Map<String, bool> availability = {};

      for (final slot in _timeSlots) {
        final slotDt = _slotToDateTime(date, slot);
        if (slotDt.isBefore(cutoff)) { availability[slot] = false; continue; }

        bool anyWorkerFree = false;
        for (final worker in workers) {
          final workerId = worker['user_id'] as String;
          if (holidayWorkerIds.contains(workerId)) continue;
          if (!_isWorkerScheduledForDate(workerId, slotDt, durationMins, scheduleLookup)) {
            continue;
          }
          if (!_isWorkerFreeAtSlot(workerId, slotDt, durationMins, bookings, newAddressId: _selectedAddressId)) continue;
          anyWorkerFree = true;
          break;
        }
        availability[slot] = anyWorkerFree;
      }

      if (mounted) {
        setState(() {
        _slotAvailability = availability;
        _slotsLoading     = false;
        if (_selectedTime.isNotEmpty &&
            availability[_selectedTime] == false) {
          _selectedTime = '';
        }
      });
      }
    } catch (e) {
      debugPrint('slot availability error: $e');
      if (mounted) {
        setState(() {
        _slotAvailability = {for (final s in _timeSlots) s: true};
        _slotsLoading = false;
      });
      }
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

  int _timeToMins(String t) {
    final parts = t.split(':');
    return int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }

  bool _isWorkerFreeAtSlot(String workerId, DateTime slotDt,
      int durationMins, List<Map<String, dynamic>> bookings,
      {String? newAddressId}) {
    final slotEnd = slotDt.add(Duration(minutes: durationMins));

    for (final booking in bookings) {
      if (booking['worker_id'] != workerId) continue;

      final workStartedAt = DateTime.tryParse(
          booking['work_started_at']?.toString() ?? '')?.toLocal();
      final scheduledAt = DateTime.tryParse(
          booking['scheduled_at']?.toString() ?? '')?.toLocal();
      final bStart = workStartedAt ?? scheduledAt;
      if (bStart == null) continue;

      final bDur = (booking['booking_duration_minutes'] as num?)?.toInt()
          ?? (booking['services']?['duration_minutes'] as num?)?.toInt()
          ?? durationMins;
      final bDurRounded = (bDur / 30).ceil() * 30;
      final extraMins = (booking['extra_time_mins'] as num?)?.toInt() ?? 0;

      final bEnd = bStart.add(Duration(minutes: bDurRounded + extraMins));

      final sameAddress = newAddressId != null &&
          newAddressId.isNotEmpty &&
          booking['address_id'] != null &&
          booking['address_id'].toString() == newAddressId;

      final bufferMins = sameAddress
          ? 0
          : (extraMins > 0 ? 10 : _travelBufferMins);

      final bEndWithBuffer   = bEnd.add(Duration(minutes: bufferMins));
      final bStartWithBuffer = bStart.subtract(Duration(minutes: bufferMins));

      if (slotDt.isBefore(bEndWithBuffer) && slotEnd.isAfter(bStartWithBuffer)) {
        return false;
      }
    }
    return true;
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
      final usedIds =
          (usageData as List).map((r) => r['promo_id'].toString()).toSet();

      List<Map<String, dynamic>> usedPromos = [];
      if (usedIds.isNotEmpty) {
        final ud = await _supabase.from('promo_codes')
            .select('*').inFilter('id', usedIds.toList());
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
              (limit as num).toInt()) {
            return false;
          }
        }
        return true;
      }).toList();

      if (mounted) {
        setState(() {
        _promos        = available;
        _usedPromos    = usedPromos;
        _usedPromoIds  = usedIds;
        _promosLoading = false;
      });
      }
    } catch (_) {
      if (mounted) setState(() => _promosLoading = false);
    }
  }

  void _applyPromo(Map<String, dynamic> promo) {
    if (widget.isFirstBooking) return;
    if (_appliedPromoId.isNotEmpty &&
        _appliedPromoId != promo['id'].toString()) {
      _showSnack('Remove current promo first before applying another',
          isError: true);
      return;
    }
    final type  = promo['discount_type'] as String? ?? 'percent';
    final value = (promo['discount_value'] as num? ?? 0).toDouble();
    final max   = promo['max_discount_amount'] != null
        ? (promo['max_discount_amount'] as num).toInt() : 9999;
    final min   = promo['min_order_amount'] != null
        ? (promo['min_order_amount'] as num).toInt() : 0;
    if (_baseAmount < min) {
      _showSnack('Min order ₹$min required', isError: true); return;
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

  Future<bool> _isInExcludedZone() async {
    final addr = _addresses.firstWhere(
        (a) => a['id'] == _selectedAddressId, orElse: () => {});
    final lat = (addr['latitude'] as num?)?.toDouble();
    final lng = (addr['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return false;

    try {
      final zoneId = await _supabase.rpc('find_zone_for_point', params: {
        'p_lat': lat,
        'p_lng': lng,
      });
      if (zoneId == null) return false;

      final row = await _supabase
          .from('service_zones')
          .select('is_exclusion')
          .eq('id', zoneId)
          .eq('is_active', true)
          .maybeSingle();
      return row != null && row['is_exclusion'] == true;
    } catch (e) {
      debugPrint('Exclusion zone check error: $e');
      return false;
    }
  }

  Future<bool> _isSelectedAddressServiceable() async {
    if (await _isInExcludedZone()) return false;

    final addr = _addresses.firstWhere(
        (a) => a['id'] == _selectedAddressId, orElse: () => {});
    final pincode = (addr['pincode'] as String?)?.trim() ?? '';
    if (pincode.isEmpty) return true;

    try {
      final rows = await _supabase
          .from('service_areas')
          .select('pincode')
          .eq('is_active', true)
          .eq('pincode', pincode);
      return (rows as List).isNotEmpty;
    } catch (e) {
      debugPrint('Service area check error: $e');
      return true;
    }
  }

  void _showAreaNotServiceableDialog({VoidCallback? onDismiss}) {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24)),
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 72, height: 72,
                decoration: const BoxDecoration(
                    color: Color(0xFFFEF2F2), shape: BoxShape.circle),
                child: const Center(
                    child: Text('😔', style: TextStyle(fontSize: 36))),
              ),
              const SizedBox(height: 20),
              const Text('Not Available in This Area Yet',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                      color: _ink)),
              const SizedBox(height: 10),
              const Text(
                'We don\'t serve this address yet. You can still browse '
                'services, but booking isn\'t available for this location. '
                'We\'re expanding soon!',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity, height: 48,
                  decoration: BoxDecoration(
                      color: _bg, borderRadius: BorderRadius.circular(14)),
                  child: const Center(
                    child: Text('Got it',
                        style: TextStyle(fontWeight: FontWeight.w800,
                            color: _muted, fontSize: 14)),
                  ),
                ),
              ),
            ]),
          ),
          Positioned(
            top: 12, right: 12,
            child: GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                    color: _bg, shape: BoxShape.circle),
                child: const Icon(Icons.close_rounded,
                    color: _muted, size: 18),
              ),
            ),
          ),
        ]),
      ),
    ).then((_) => onDismiss?.call());
  }

  Future<bool> _checkSlotStillAvailable() async {
    try {
      final scheduledAt = _isInstant ? DateTime.now().toUtc() : _buildScheduledAt();
      final result = await _supabase.rpc('check_slot_availability', params: {
        'p_address_id':    _selectedAddressId,
        'p_scheduled_at':  scheduledAt.toIso8601String(),
        'p_duration_mins': _serviceDurationMins,
      });
      final res = result as Map<String, dynamic>;
      return res['available'] == true;
    } catch (e) {
      debugPrint('check_slot_availability error: $e');
      return true;
    }
  }

  // ── Confirmation dialog ───────────────────────────────────────
  Future<void> _askConfirm() async {
    if (!await _isSelectedAddressServiceable()) {
      _showAreaNotServiceableDialog();
      return;
    }

    if (_isSchedule) {
      final stillAvailable = await _checkSlotStillAvailable();
      if (!mounted) return;
      if (!stillAvailable) {
        _showSlotFullDialog();
        return;
      }
    }

    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 40),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Confirm booking?',
                style: TextStyle(fontSize: 17,
                    fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 8),
            Text(
              _isInstant
                  ? 'A verified pro will be dispatched to your address. '
                    'They will arrive in approximately 10–15 minutes after assignment. '
                    'Pay ₹$_finalAmount cash after the service.'
                  : 'Your slot will be booked. Pay ₹$_finalAmount cash '
                    'after the service is done.',
              style: const TextStyle(
                  fontSize: 13.5, height: 1.45, color: _muted)),
            if (_isInstant) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _cyanBg,
                  borderRadius: BorderRadius.circular(10)),
                child: const Row(children: [
                  Icon(Icons.bolt_rounded, color: _cyanDk, size: 16),
                  SizedBox(width: 6),
                  Text('Est. arrival: 10–15 min after assignment',
                      style: TextStyle(color: _cyanDeep,
                          fontSize: 12, fontWeight: FontWeight.w700)),
                ]),
              ),
            ],
            const SizedBox(height: 22),
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
                            fontSize: 15, fontWeight: FontWeight.w800)),
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
                    child: const Text('Confirm',
                        style: TextStyle(color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ]),
          ]),
        ),
      ),
    );

    if (confirmed == true) _confirmBookingWithPayment('online');
  }

  // ── Ask payment method ────────────────────────────────────────
  Future<void> _askPaymentMethod() async {
    final method = await showDialog<String>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.45),
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Choose Payment Method',
                style: TextStyle(fontSize: 17,
                    fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const SizedBox(height: 6),
            const Text('How would you like to pay?',
                style: TextStyle(color: Color(0xFF64748B), fontSize: 13)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () => Navigator.pop(ctx, 'online'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                      color: const Color(0xFF06B6D4).withValues(alpha: 0.35),
                      blurRadius: 10, offset: const Offset(0, 4))]),
                child: Row(children: [
                  const Icon(Icons.payment_rounded,
                      color: Colors.white, size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Pay Online',
                        style: TextStyle(color: Colors.white,
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    Text('UPI, Card, Netbanking · ₹$_finalAmount',
                        style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.8),
                            fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: Colors.white70, size: 14),
                ]),
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.pop(ctx, 'cod'),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(children: [
                  const Icon(Icons.money_rounded,
                      color: Color(0xFF059669), size: 24),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Cash on Delivery',
                        style: TextStyle(color: Color(0xFF0F172A),
                            fontWeight: FontWeight.w900, fontSize: 15)),
                    Text('Pay ₹$_finalAmount cash to professional',
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12)),
                  ])),
                  const Icon(Icons.arrow_forward_ios_rounded,
                      color: Color(0xFF94A3B8), size: 14),
                ]),
              ),
            ),
            const SizedBox(height: 8),
            Center(child: TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Cancel',
                  style: TextStyle(color: Color(0xFF94A3B8))))),
          ]),
        ),
      ),
    );

    if (method == 'online') {
      _confirmBookingWithPayment('online');
    }
  }

  Future<void> _confirmBookingWithPayment(String paymentMethod) async {
    if (_selectedAddressId.isEmpty) {
      _showSnack('Please select an address', isError: true); return;
    }
    setState(() => _loading = true);

    final userId = _userId ?? await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    _userId = userId;

    final attemptRef = 'attempt_${DateTime.now().millisecondsSinceEpoch}';
    _pendingAttemptRef = attemptRef;

    String orderId;
    try {
      final orderResp = await http.post(
        Uri.parse('$_apiBaseUrl/api/payments/order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount':   _finalAmount * 100,
          'currency': 'INR',
          'receipt':  attemptRef,
        }),
      ).timeout(const Duration(seconds: 15));

      if (orderResp.statusCode != 200) {
        throw 'Order creation failed (${orderResp.statusCode})';
      }
      final orderData = jsonDecode(orderResp.body) as Map<String, dynamic>;
      final id = orderData['order_id'] as String?;
      if (id == null) throw 'Order response missing order_id';
      orderId = id;
    } catch (e) {
      debugPrint('Create order error: $e');
      if (mounted) {
        setState(() => _loading = false);
        _showSnack('Could not start payment. Please try again.', isError: true);
      }
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    final scheduledAtForDraft = _isInstant
        ? DateTime.now().toUtc()
        : _buildScheduledAt();
    final otpForDraft =
        (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();
    _pendingBookingOtp = otpForDraft;
    try {
      await _supabase.rpc('create_pending_payment_booking', params: {
        'p_attempt_ref':                attemptRef,
        'p_customer_id':                userId,
        'p_address_id':                 _selectedAddressId,
        'p_scheduled_at':                scheduledAtForDraft.toIso8601String(),
        'p_booking_type':                _isInstant ? 'instant' : 'schedule',
        'p_service_id':                  widget.serviceId,
        'p_cart_items': widget.cartItems != null && widget.cartItems!.isNotEmpty
            ? widget.cartItems!.map((c) => {
                'service_id': c['service_id'],
                'name':       c['name'],
                'quantity':   c['quantity'],
                'price':      c['price'],
              }).toList()
            : null,
        'p_base_price':                  _baseAmount,
        'p_discount_amount':             _discount,
        'p_final_amount':                _finalAmount,
        'p_otp':                         otpForDraft,
        'p_promo_code':      _appliedPromoCode.isNotEmpty ? _appliedPromoCode : null,
        'p_selected_bhk':                widget.selectedBhk,
        'p_quantity':                    widget.quantity,
        'p_is_first_booking':            widget.isFirstBooking,
        'p_estimated_arrival_minutes':   _isInstant ? 15 : null,
        'p_booking_duration_minutes':    _serviceDurationMins,
        'p_special_instructions': _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
      });
    } catch (e) {
      debugPrint('create_pending_payment_booking failed (non-fatal): $e');
    }

    final options = {
      'key':          _razorpayKey,
      'order_id':     orderId,
      'amount':       _finalAmount * 100,
      'name':         'Cleenzo',
      'description':  (_service?['name'] as String? ?? 'Home Cleaning Service'),
      'prefill': {
        'contact': _userPhone ?? '',
        'email':   _userEmail ?? '',
      },
      'notes': {
        'attempt_ref': attemptRef,
        'customer_id': userId,
      },
      'theme': {
        'color': '#06B6D4',
      },
            'method': {
        'upi':          true,
        'netbanking':   true,
        'card':         true,
        'wallet':       true,
        'emi':          false,
        'cardless_emi': false,
        'paylater':     false,
      },
    };

    try {
      _razorpay.open(options);
    } catch (e) {
      setState(() => _loading = false);
      _showSnack('Could not open payment. Please try again.', isError: true);
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() => _loading = true);

    final paymentId = response.paymentId;
    if (paymentId == null) {
      if (mounted) {
        setState(() => _loading = false);
        _showSnack(
            'Payment confirmation was incomplete. If you were charged, '
            'please contact support.',
            isError: true);
      }
      return;
    }

    try {
      final verifyResp = await http.post(
        Uri.parse('$_apiBaseUrl/api/payments/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_order_id':   response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature':  response.signature,
        }),
      ).timeout(const Duration(seconds: 15));

      final verifyData = jsonDecode(verifyResp.body) as Map<String, dynamic>;
      final verified = verifyData['verified'] as bool? ?? false;

      if (!verified) {
        debugPrint('Payment signature verification failed: ${verifyData['error']}');
        await _refundPayment(paymentId, reason: 'signature_verification_failed');
        if (mounted) {
          setState(() => _loading = false);
          _showSnack(
              'We could not verify this payment. It has been refunded — '
              'please try again.',
              isError: true);
        }
        return;
      }
    } catch (e) {
      debugPrint('Verify request error: $e');
      await _refundPayment(paymentId, reason: 'verification_request_failed');
      if (mounted) {
        setState(() => _loading = false);
        _showSnack(
            'We could not confirm this payment. It has been refunded — '
            'please try again.',
            isError: true);
      }
      return;
    }

    final userId = _userId;
    if (userId == null) {
      await _refundPayment(paymentId, reason: 'missing_user');
      if (mounted) {
        setState(() => _loading = false);
        _showSnack(
            'Something went wrong. Your payment has been refunded.',
            isError: true);
      }
      return;
    }

    final scheduledAt = _isInstant
        ? DateTime.now().toUtc()
        : _buildScheduledAt();
    final otp = _pendingBookingOtp ??
        (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();

    try {
      final recovery = await _supabase.rpc('complete_payment_booking_recovery', params: {
        'p_attempt_ref': _pendingAttemptRef,
        'p_payment_id':  paymentId,
      });
      final recoveryResult = recovery as Map<String, dynamic>;
      final action = recoveryResult['action'] as String?;

      String? bookingId;

      if (action == 'booking_created' || action == 'already_completed') {
        bookingId = recoveryResult['booking_id'] as String?;
      } else if (action == 'needs_refund') {
        await _refundPayment(paymentId, reason: recoveryResult['reason']?.toString() ?? 'slot_full');
        if (!mounted) return;
        setState(() => _loading = false);
        _showSnack('Payment refunded ✅ — the slot was just taken', isError: false);
        final reason = recoveryResult['reason']?.toString();
        if (reason == 'slot_full' || reason == 'no_workers') {
          _isInstant ? _showNoWorkersDialog() : _showSlotFullDialog();
        } else {
          _showSnack('Booking failed: ${recoveryResult['message'] ?? reason}', isError: true);
        }
        return;
      } else if (action == 'no_draft_found') {
        final result = await _supabase.rpc('try_claim_slot', params: {
          'p_customer_id':          userId,
          'p_address_id':           _selectedAddressId,
          'p_scheduled_at':         scheduledAt.toIso8601String(),
          'p_duration_mins':        _serviceDurationMins,
          'p_base_price':           _baseAmount,
          'p_discount_amount':      _discount,
          'p_final_amount':         _finalAmount,
          'p_otp':                  otp,
          'p_booking_type':         _isInstant ? 'instant' : 'schedule',
          'p_payment_status':       'paid',
          'p_payment_method':       'online',
          'p_service_id':           widget.serviceId,
          'p_special_instructions': _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
          'p_promo_code':           _appliedPromoCode.isNotEmpty ? _appliedPromoCode : null,
          'p_selected_bhk':         widget.selectedBhk,
          'p_quantity':             widget.quantity,
          'p_is_first_booking':     widget.isFirstBooking,
          'p_estimated_arrival':    _isInstant ? 15 : null,
          'p_booking_duration_minutes': _serviceDurationMins,
        });
        if (!mounted) return;
        final res = result as Map<String, dynamic>;
        if (res['success'] != true) {
          final reason = res['reason'] as String? ?? 'error';
          await _refundPayment(paymentId, reason: reason);
          if (!mounted) return;
          setState(() => _loading = false);
          _showSnack('Payment refunded ✅ — the slot was just taken', isError: false);
          if (reason == 'slot_full' || reason == 'no_workers') {
            _isInstant ? _showNoWorkersDialog() : _showSlotFullDialog();
          } else {
            _showSnack('Booking failed: ${res['message'] ?? reason}', isError: true);
          }
          return;
        }
        bookingId = res['booking_id'] as String;
        if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
          try {
            await _supabase.from('booking_items').insert(
              widget.cartItems!.map((c) => {
                'booking_id':   bookingId,
                'service_id':   c['service_id'] as String,
                'service_name': (c['name'] as String?) ?? 'Service',
                'quantity':     (c['quantity'] as num).toInt(),
                'unit_price':   (c['price'] as num).toInt(),
                'total_price':  (c['price'] as num).toInt() *
                    (c['quantity'] as num).toInt(),
              }).toList(),
            );
          } catch (e) { debugPrint('booking_items skipped: $e'); }
        }
      } else {
        throw Exception('Recovery RPC returned unexpected action: $action');
      }

      if (bookingId == null) {
        throw Exception('No booking_id returned after successful recovery');
      }

      if (!mounted) return;

      try {
        await _supabase.from('bookings').update({
          'payment_id':               paymentId,
          'service_duration_minutes': _rawServiceDurationMins,
        }).eq('id', bookingId);
      } catch (e) { debugPrint('post-booking update skipped: $e'); }

      setState(() => _loading = false);
      CartService.instance.clear();
      Navigator.pushReplacement(context, MaterialPageRoute(
        builder: (_) => BookingDetailScreen(bookingId: bookingId!, isNew: true),
      ));
    } catch (e) {
      debugPrint('Post-payment booking creation error: $e');
      await _refundPayment(paymentId, reason: 'booking_creation_error');
      if (!mounted) return;
      setState(() => _loading = false);
      _showSnack(
          'Something went wrong creating your booking. Your payment has '
          'been refunded — please try again.',
          isError: true);
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) setState(() => _loading = false);
    _showSnack('Payment failed: ${response.message ?? "Please try again"}',
        isError: true);
  }

  void _onExternalWallet(ExternalWalletResponse response) {
    _showSnack('External wallet: ${response.walletName}');
  }

  static const _apiBaseUrl = 'https://gocleenzo-admin.vercel.app';

  Future<void> _refundPayment(String paymentId, {required String reason}) async {
    try {
      final resp = await http.post(
        Uri.parse('$_apiBaseUrl/api/payments/refund'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'payment_id': paymentId,
          'reason':     reason,
        }),
      ).timeout(const Duration(seconds: 15));

      if (resp.statusCode != 200) {
        debugPrint('Refund API error (${resp.statusCode}): ${resp.body}');
        if (mounted) {
          _showSnack(
              'Could not auto-refund. Please contact support with '
              'payment ID: $paymentId',
              isError: true);
        }
      }
    } catch (e) {
      debugPrint('Refund request failed: $e');
      if (mounted) {
        _showSnack(
            'Could not auto-refund. Please contact support with '
            'payment ID: $paymentId',
            isError: true);
      }
    }
  }

  Future<void> _confirmBooking() async {
    if (_selectedAddressId.isEmpty) {
      _showSnack('Please select an address', isError: true); return;
    }
    if (_isSchedule && _selectedTime.isEmpty) {
      _showSnack('Please select a time slot', isError: true); return;
    }

    setState(() => _loading = true);
    final userId = _userId ?? await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    _userId = userId;

    final scheduledAt = _isInstant
        ? DateTime.now().toUtc()
        : _buildScheduledAt();

    final otp =
        (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();

    try {
      final result = await _supabase.rpc('try_claim_slot', params: {
        'p_customer_id':          userId,
        'p_address_id':           _selectedAddressId,
        'p_scheduled_at':         scheduledAt.toIso8601String(),
        'p_duration_mins':        _serviceDurationMins,
        'p_base_price':           _baseAmount,
        'p_discount_amount':      _discount,
        'p_final_amount':         _finalAmount,
        'p_otp':                  otp,
        'p_booking_type':         _isInstant ? 'instant' : 'schedule',
        'p_payment_status':       'cod',
        'p_payment_method':       'cod',
        'p_service_id':           widget.serviceId,
        'p_special_instructions': _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        'p_promo_code':           _appliedPromoCode.isNotEmpty
                                      ? _appliedPromoCode : null,
        'p_selected_bhk':         widget.selectedBhk,
        'p_quantity':             widget.quantity,
        'p_is_first_booking':     widget.isFirstBooking,
        'p_estimated_arrival':    _isInstant ? 15 : null,
        'p_booking_duration_minutes': _serviceDurationMins,
      });

      if (!mounted) return;

      final res = result as Map<String, dynamic>;
      final success = res['success'] as bool? ?? false;

      if (!success) {
        setState(() => _loading = false);
        final reason = res['reason'] as String? ?? 'error';
        if (reason == 'slot_full') {
          if (_isInstant) {
            _showNoWorkersDialog();
          } else {
            _showSlotFullDialog();
          }
        } else if (reason == 'no_workers') {
          _showNoWorkersDialog();
        } else {
          _showSnack('Booking failed: ${res['message'] ?? reason}',
              isError: true);
        }
        return;
      }

      final bookingId = res['booking_id'] as String;

      try {
        await _supabase.from('bookings').update({
          'service_duration_minutes': _rawServiceDurationMins,
        }).eq('id', bookingId);
      } catch (e) { debugPrint('service_duration_minutes skipped: $e'); }

      if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
        try {
          await _supabase.from('booking_items').insert(
            widget.cartItems!.map((c) => {
              'booking_id':   bookingId,
              'service_id':   c['service_id'] as String,
              'service_name': (c['name'] as String?) ?? 'Service',
              'quantity':     (c['quantity'] as num).toInt(),
              'unit_price':   (c['price'] as num).toInt(),
              'total_price':  (c['price'] as num).toInt() *
                  (c['quantity'] as num).toInt(),
            }).toList(),
          );
        } catch (e) { debugPrint('booking_items skipped: $e'); }
      }

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
        CartService.instance.clear();
        Navigator.pushReplacement(context, MaterialPageRoute(
          builder: (_) => BookingDetailScreen(
              bookingId: bookingId, isNew: true),
        ));
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
      _showSnack(
          'Could not confirm booking: ${e.toString().split('\n').first}',
          isError: true);
    }
  }

  void _showSlotFullDialog() {
    HapticFeedback.heavyImpact();
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => Dialog(
          backgroundColor: Colors.white,
          elevation: 0,
          insetPadding: const EdgeInsets.symmetric(horizontal: 32),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24)),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 64, height: 64,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED),
                  shape: BoxShape.circle),
                child: const Center(
                    child: Text('⏱️', style: TextStyle(fontSize: 32)))),
              const SizedBox(height: 18),
              const Text('Slot Just Filled Up!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 18,
                      fontWeight: FontWeight.w900, color: _ink)),
              const SizedBox(height: 10),
              const Text(
                'Someone else just booked this time slot.\nPlease choose a different time.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
              const SizedBox(height: 20),
              GestureDetector(
                onTap: () {
                  Navigator.pop(ctx);
                  setState(() { _step = 1; _selectedTime = ''; });
                  _loadSlotAvailability(_selectedDate);
                },
                child: Container(
                  width: double.infinity, height: 50,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_cyan, _cyanDeep]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: _cyan.withValues(alpha: 0.32),
                        blurRadius: 10, offset: const Offset(0, 4))]),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.calendar_month_rounded,
                        color: Colors.white, size: 18),
                    SizedBox(width: 8),
                    Text('Choose Another Time',
                        style: TextStyle(color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.w900)),
                  ]),
                ),
              ),
              const SizedBox(height: 10),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(
                  width: double.infinity, height: 44,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                  child: const Text('Cancel',
                      style: TextStyle(color: _muted,
                          fontSize: 14, fontWeight: FontWeight.w700)),
                ),
              ),
            ]),
          ),
        ),
    );
  }

  DateTime _buildScheduledAt() {
    final parts = _selectedTime.split(' ');
    final hm    = parts[0].split(':');
    int hh      = int.parse(hm[0]);
    final mm    = int.parse(hm[1]);
    final pm    = parts[1] == 'PM';
    if (pm && hh != 12) hh += 12;
    if (!pm && hh == 12) hh = 0;
    return DateTime(
        _selectedDate.year, _selectedDate.month,
        _selectedDate.day, hh, mm).toUtc();
  }

  void _showSnack(String msg, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? Colors.red : _green,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ));
  }

  // ── BUILD ────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    if (_initializing) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(
          child: CircularProgressIndicator(color: _cyan, strokeWidth: 2.5),
        ),
      );
    }

    return PopScope(
      canPop: _step <= 1,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_step > 1) {
          setState(() => _step--);
        } else if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        Column(children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
              child: _buildStepContent(),
            ),
          ),
        ]),
        Positioned(
            left: 0, right: 0, bottom: 0,
            child: _buildBottomBar()),
      ]),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border)),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            Row(children: [
              GestureDetector(
                onTap: () {
                  if (_step > 1) {
                    setState(() => _step--);
                  } else {
                    Navigator.pop(context);
                  }
                },
                child: Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: _cyanBg,
                    borderRadius: BorderRadius.circular(12)),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: _cyanDk, size: 16)),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Icon(_isInstant
                          ? Icons.bolt_rounded
                          : Icons.calendar_month_rounded,
                      color: _cyanDk, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    _isInstant ? 'Instant Booking' : 'Schedule Booking',
                    style: const TextStyle(color: _ink,
                        fontSize: 17, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 1),
                Text(
                  _isInstant
                      ? 'Pro arrives in ~10–15 min after assignment'
                      : 'Choose your date & time',
                  style: const TextStyle(color: _faint, fontSize: 11.5)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: _cyanBg,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cyanBg2)),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                  Text('₹$_finalAmount',
                      style: const TextStyle(color: _cyanDeep,
                          fontSize: 18, fontWeight: FontWeight.w900)),
                  Text(
                    widget.isFirstBooking
                        ? 'First booking!'
                        : _discount > 0
                            ? '-₹$_discount saved'
                            : 'Pay online',
                    style: const TextStyle(
                        color: _cyanDk,
                        fontSize: 9.5, fontWeight: FontWeight.w700)),
                ]),
              ),
            ]),
            const SizedBox(height: 18),
            Row(children: List.generate(_stepLabels.length, (i) {
              final s = i + 1; final active = _step == s; final done = _step > s;
              return Expanded(child: Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 30, height: 30,
                  decoration: BoxDecoration(
                    gradient: (done || active)
                        ? const LinearGradient(colors: [_cyan, _cyanDk])
                        : null,
                    color: (done || active) ? null : _bg,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: (done || active) ? _cyan : _border),
                    boxShadow: active ? [BoxShadow(
                        color: _cyan.withValues(alpha: 0.32),
                        blurRadius: 8, offset: const Offset(0, 3))] : []),
                  child: Center(child: done
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 15)
                      : Icon(_stepIcons[i < _stepIcons.length ? i : 0],
                          color: active ? Colors.white : _faint,
                          size: 14)),
                ),
                const SizedBox(width: 6),
                Flexible(child: Text(_stepLabels[i],
                    style: TextStyle(
                      color: active ? _ink : _faint,
                      fontSize: 11,
                      fontWeight: active ? FontWeight.w800 : FontWeight.w600),
                    overflow: TextOverflow.ellipsis)),
                if (i < _stepLabels.length - 1)
                  Expanded(child: Container(
                    height: 2,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: done ? _cyan : _border,
                      borderRadius: BorderRadius.circular(2)))),
              ]));
            })),
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
                    color: active ? null : _bg,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: active ? _cyan : _border),
                    boxShadow: active
                        ? [BoxShadow(
                            color: _cyan.withValues(alpha: 0.36),
                            blurRadius: 12, offset: const Offset(0, 4))]
                        : []),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(
                      ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d.weekday-1],
                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                          color: active ? const Color(0xFFDFFAFE) : _faint)),
                    Text('${d.day}',
                        style: TextStyle(fontSize: 22,
                            fontWeight: FontWeight.w900,
                            color: active ? Colors.white : _ink)),
                    Text(i == 0 ? 'TODAY' : '·',
                        style: TextStyle(fontSize: 8,
                            fontWeight: FontWeight.w900,
                            color: active
                                ? Colors.white
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
            : '$availableCount slots available · ${_minNoticeMins}min advance · '
              '${_slotsBlocked}hr${_slotsBlocked > 1 ? 's' : ''} blocked',
        child: _slotsLoading
            ? const Center(child: Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  CircularProgressIndicator(color: _cyan),
                  SizedBox(height: 12),
                  Text('Checking worker availability…',
                      style: TextStyle(color: _faint, fontSize: 12)),
                ])))
            : Column(children: [
                Row(children: [
                  _legendDot(_cyan), const SizedBox(width: 4),
                  const Text('Available',
                      style: TextStyle(color: _muted, fontSize: 11)),
                  const SizedBox(width: 16),
                  _legendDot(const Color(0xFFE2E8F0)), const SizedBox(width: 4),
                  const Text('Full / Not available',
                      style: TextStyle(color: _muted, fontSize: 11)),
                ]),
                const SizedBox(height: 12),
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 3,
                  childAspectRatio: 2.0,
                  crossAxisSpacing: 10, mainAxisSpacing: 10,
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
                          color: isFull ? _bg : active ? null : Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: isFull ? _border : active ? _cyan : _border),
                          boxShadow: active && !isFull
                              ? [BoxShadow(
                                  color: _cyan.withValues(alpha: 0.34),
                                  blurRadius: 10, offset: const Offset(0, 3))]
                              : []),
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
                if (availableCount == 0 && !_slotsLoading) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFED7AA))),
                    child: const Row(children: [
                      Icon(Icons.event_busy_rounded,
                          color: Color(0xFFEA580C), size: 24),
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

  Widget _buildFirstBookingBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF6EE7B7))),
      child: Row(children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
              color: _green, borderRadius: BorderRadius.circular(12)),
          child: const Icon(Icons.celebration_rounded,
              color: Colors.white, size: 24)),
        const SizedBox(width: 12),
        const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('First Booking — Just ₹25!',
              style: TextStyle(color: Color(0xFF065F46),
                  fontWeight: FontWeight.w900, fontSize: 14)),
          SizedBox(height: 2),
          Text('Promo codes cannot be stacked with this offer.',
              style: TextStyle(color: Color(0xFF047857), fontSize: 11)),
        ])),
        const Text('₹25', style: TextStyle(color: _greenDk,
            fontSize: 24, fontWeight: FontWeight.w900)),
      ]),
    );
  }

  Widget _buildAddressStep() {
    return Column(children: [
      if (_isInstant)
        Container(
          margin: const EdgeInsets.only(bottom: 14),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _cyanBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cyanBg2)),
          child: Column(children: [
            Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                  borderRadius: BorderRadius.circular(12)),
                child: const Icon(Icons.bolt_rounded,
                    color: Colors.white, size: 24)),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Instant Booking!',
                    style: TextStyle(color: _cyanDeep,
                        fontWeight: FontWeight.w900, fontSize: 14)),
                SizedBox(height: 2),
                Text('Available 7:00 AM – 7:00 PM',
                    style: TextStyle(color: _cyanDk, fontSize: 12)),
              ])),
            ]),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _border)),
              child: const Row(children: [
                Icon(Icons.schedule_rounded, color: _cyanDk, size: 16),
                SizedBox(width: 8),
                Expanded(child: Text(
                  'A professional will be assigned and arrive in approximately 10–15 minutes.',
                  style: TextStyle(color: _muted,
                      fontSize: 12, height: 1.4))),
              ]),
            ),
          ]),
        ),

      if (widget.isFirstBooking) ...[
        _buildFirstBookingBanner(), const SizedBox(height: 14),
      ],

      _card(
        icon: Icons.location_on_rounded,
        title: 'Service Address',
        sub: 'Where should we come?',
        trailing: GestureDetector(
          onTap: () => context.go('/account'),
          child: Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: _cyanBg,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: _cyanBg2)),
            child: const Text('+ Add',
                style: TextStyle(color: _cyanDk,
                    fontSize: 12, fontWeight: FontWeight.w800))),
        ),
        child: _addresses.isEmpty
            ? const Padding(
                padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  Icon(Icons.location_off_rounded, size: 34, color: _faint),
                  SizedBox(height: 10),
                  Text('No saved addresses',
                      style: TextStyle(fontWeight: FontWeight.bold,
                          color: Color(0xFF374151))),
                  SizedBox(height: 4),
                  Text('Add an address to continue',
                      style: TextStyle(color: _faint, fontSize: 13)),
                ]))
            : Column(
                children: _addresses.map((addr) {
                  final active = _selectedAddressId == addr['id'];
                  final lbl    = addr['label'] ?? 'Address';
                  final aIcon  = lbl == 'Home'
                      ? Icons.home_rounded
                      : lbl == 'Office'
                          ? Icons.business_rounded
                          : Icons.location_on_rounded;
                  return GestureDetector(
                    onTap: () {
                      setState(() => _selectedAddressId = addr['id']);
                      if (_isSchedule) {
                        _loadSlotAvailability(_selectedDate);
                      }
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: active ? _cyanBg : _bg,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                            color: active ? _cyan : _border,
                            width: active ? 1.6 : 1)),
                      child: Row(children: [
                        Container(
                          width: 38, height: 38,
                          decoration: BoxDecoration(
                            color: active ? Colors.white : _cyanBg,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: _border)),
                          child: Icon(aIcon, color: _cyanDk, size: 19)),
                        const SizedBox(width: 12),
                        Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          Row(children: [
                            Text(lbl, style: const TextStyle(
                                fontWeight: FontWeight.w800, fontSize: 14,
                                color: _ink)),
                            if (addr['is_default'] == true) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                    color: _cyanBg2,
                                    borderRadius: BorderRadius.circular(20)),
                                child: const Text('Default',
                                    style: TextStyle(color: _cyanDk,
                                        fontSize: 9,
                                        fontWeight: FontWeight.w800))),
                            ],
                          ]),
                          const SizedBox(height: 2),
                          Text(
                            [if (addr['flat_no'] != null) addr['flat_no'],
                              if (addr['building'] != null) addr['building'],
                              addr['area'], addr['city']]
                                .where((e) => e != null).join(', '),
                            style: const TextStyle(color: _faint, fontSize: 12),
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        ])),
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          width: 22, height: 22,
                          decoration: BoxDecoration(
                            color: active ? _cyan : Colors.transparent,
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: active
                                    ? _cyan : const Color(0xFFD1D5DB),
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
          style: const TextStyle(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            hintText: 'e.g. Ring bell twice, pet at home...',
            hintStyle: const TextStyle(color: _faint, fontSize: 13),
            filled: true, fillColor: _bg,
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

  Widget _buildConfirmStep() {
    final addr = _addresses.firstWhere(
        (a) => a['id'] == _selectedAddressId, orElse: () => {});
    final hasCart = widget.cartItems != null && widget.cartItems!.isNotEmpty;

    final rows = <Map<String, dynamic>>[
            if (hasCart)
        for (int i = 0; i < widget.cartItems!.length; i++)
          () {
            final item = widget.cartItems![i];
            final qty  = (item['quantity'] as num?)?.toInt() ?? 1;
            final price = (item['price'] as num).toInt();
            final name  = (item['name'] as String?) ?? 'Service';
            final serviceId = item['service_id'] as String?;
            final eligible = widget.isFirstBooking &&
                serviceId != null &&
                CartService.instance.firstBookingClaimServiceId == serviceId;
            return {
              'icon': Icons.cleaning_services_rounded,
              'label': name,
              'value': eligible
                  ? '×$qty  ·  ₹$price 🎉'
                  : '×$qty  ·  ₹$price',
            };
          }()
      else
        {'icon': Icons.cleaning_services_rounded, 'label': 'Service',  'value': _serviceLabel},
      if (widget.isFirstBooking)
        {'icon': Icons.celebration_rounded, 'label': 'Offer',
          'value': hasCart
              ? 'First unit of each eligible service at ₹25!'
              : 'First booking at ₹25!'},
      if (_isInstant) ...[
        {'icon': Icons.bolt_rounded, 'label': 'Type', 'value': 'Instant Booking'},
        {'icon': Icons.schedule_rounded, 'label': 'Est. Arrival',
          'value': '~10–15 min after assignment'},
        {'icon': Icons.access_time_rounded, 'label': 'Window',
          'value': 'Available 7:00 AM – 7:00 PM'},
      ],
      if (_isSchedule) ...[
        {'icon': Icons.calendar_month_rounded, 'label': 'Date',
          'value': '${_selectedDate.day}/'
              '${_selectedDate.month}/${_selectedDate.year}'},
        {'icon': Icons.access_time_rounded, 'label': 'Time', 'value': _selectedTime},
        {'icon': Icons.timelapse_rounded, 'label': 'Duration',
          'value': '~$_rawServiceDurationMins min'},
      ],
      {'icon': Icons.location_on_rounded, 'label': 'Address',
        'value': addr.isNotEmpty
            ? '${addr['area']}, ${addr['city']}' : '—'},
      {'icon': Icons.payments_rounded, 'label': 'Payment',  'value': 'Online Payment (UPI / Netbanking)'},
      if (_notesCtrl.text.isNotEmpty)
        {'icon': Icons.chat_bubble_rounded, 'label': 'Notes', 'value': _notesCtrl.text},
    ];

    return Column(children: [
      Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFED7AA))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: const Color(0xFFFFEDD5),
              borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.info_rounded,
                color: Color(0xFFEA580C), size: 20)),
          const SizedBox(width: 12),
          const Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Please note',
                style: TextStyle(color: Color(0xFF9A3412),
                    fontSize: 13, fontWeight: FontWeight.w900)),
            SizedBox(height: 3),
            Text(
              'Our professionals do not carry any cleaning equipment or '
              'supplies. Please make sure the required equipment is '
              'available at your address.',
              style: TextStyle(color: Color(0xFFB45309),
                  fontSize: 12, height: 1.45)),
          ])),
        ]),
      ),

      _card(
        icon: Icons.receipt_long_rounded,
        title: 'Booking Summary',
        sub: 'Review before confirming',
        child: Column(children: [
          for (int i = 0; i < rows.length; i++) ...[
            Row(children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                    color: _cyanBg,
                    borderRadius: BorderRadius.circular(11),
                    border: Border.all(color: _cyanBg2)),
                child: Icon(rows[i]['icon'] as IconData,
                    color: _cyanDk, size: 19)),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(rows[i]['label'] as String,
                    style: const TextStyle(
                        color: _faint, fontSize: 10.5,
                        fontWeight: FontWeight.w700, letterSpacing: 0.4)),
                const SizedBox(height: 1),
                Text(rows[i]['value'] as String,
                    style: const TextStyle(fontSize: 14.5,
                        fontWeight: FontWeight.w700, color: _ink)),
              ])),
            ]),
            if (i < rows.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1, color: _line)),
          ],
        ]),
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
                width: _appliedPromoCode.isNotEmpty ? 1.5 : 1)),
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                child: Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: _appliedPromoCode.isNotEmpty
                          ? const Color(0xFFECFDF5) : _cyanBg,
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(
                          color: _appliedPromoCode.isNotEmpty
                              ? const Color(0xFFA7F3D0) : _cyanBg2)),
                    child: Icon(
                        _appliedPromoCode.isNotEmpty
                            ? Icons.check_circle_rounded
                            : Icons.local_offer_rounded,
                        color: _appliedPromoCode.isNotEmpty
                            ? _green : _cyanDk,
                        size: 19)),
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
                              ? _greenDk : _ink)),
                    Text(
                      _appliedPromoCode.isNotEmpty
                          ? '$_appliedPromoCode  •  Saving ₹$_discount'
                          : _promos.isEmpty && !_promosLoading
                              ? 'No offers available right now'
                              : 'Tap to see ${_promos.length} '
                                'offer${_promos.length == 1 ? '' : 's'}',
                      style: TextStyle(
                          color: _appliedPromoCode.isNotEmpty
                              ? _green : _faint,
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
                        color: _promos.isEmpty ? _border : _faint),
                ]),
              ),
              if (_appliedPromoCode.isNotEmpty) ...[
                const Divider(height: 1, color: Color(0xFFF0FDF4)),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: const BoxDecoration(
                    color: Color(0xFFF0FDF4),
                    borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(20),
                        bottomRight: Radius.circular(20))),
                  child: Row(children: [
                    const Icon(Icons.check_circle_rounded,
                        color: _green, size: 16),
                    const SizedBox(width: 8),
                    Text('₹$_discount discount applied to your order',
                        style: const TextStyle(color: _greenDk,
                            fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ],
            ]),
          ),
        ),

      if (!widget.isFirstBooking) const SizedBox(height: 14),

      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: _border)),
        child: Column(children: [
                    if (hasCart) ...[
            for (final item in widget.cartItems!)
              () {
                final qty   = (item['quantity'] as num?)?.toInt() ?? 1;
                final name  = (item['name'] as String?) ?? 'Service';
                final price = (item['price'] as num).toInt();
                final serviceId = item['service_id'] as String?;
                final eligible = widget.isFirstBooking &&
                    serviceId != null &&
                    CartService.instance.firstBookingClaimServiceId == serviceId;
                return _priceRow(
                  '$name${qty > 1 ? ' ×$qty' : ''}${eligible ? ' 🎉' : ''}',
                  '₹$price',
                  _muted, eligible ? _greenDk : _ink);
              }(),
            if (_discount > 0)
              _priceRow('Promo ($_appliedPromoCode)', '− ₹$_discount',
                  _muted, _greenDk),
          ] else ...[
            _priceRow('Service total', '₹$_baseAmount', _muted, _ink),
            if (_discount > 0)
              _priceRow('Promo ($_appliedPromoCode)', '− ₹$_discount',
                  _muted, _greenDk),
          ],
          _priceRow('Platform fee', '₹$_platformFee', _muted, _ink),
          if (_searchFeeEnabled)
            _priceRow('Search fee', '₹$_searchFee', _muted, _ink),
          const Divider(color: _line, height: 20),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            const Text('Pay to Worker',
                style: TextStyle(color: _ink,
                    fontSize: 16, fontWeight: FontWeight.w900)),
            Text('₹$_finalAmount',
                style: TextStyle(
                    color: widget.isFirstBooking ? _greenDk : _cyanDeep,
                    fontSize: 28, fontWeight: FontWeight.w900)),
          ]),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: _cyanBg,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cyanBg2)),
            child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Icon(Icons.payments_rounded,
                  color: _cyanDk, size: 20),
              SizedBox(width: 10),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text('Online Payment',
                    style: TextStyle(color: _ink,
                        fontSize: 13, fontWeight: FontWeight.w800)),
                Text('Pay via UPI or Netbanking',
                    style: TextStyle(color: _muted, fontSize: 10.5)),
              ])),
            ]),
          ),
        ]),
      ),
    ]);
  }

  Widget _priceRow(String l, String v, Color lc, Color vc,
          {bool strike = false}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
          Text(l, style: TextStyle(color: lc, fontSize: 13)),
          Text(v, style: TextStyle(
              color: vc, fontSize: 13, fontWeight: FontWeight.bold,
              decoration: strike ? TextDecoration.lineThrough : null)),
        ]));

  Widget _card({
    required IconData icon, required String title,
    required String sub, required Widget child, Widget? trailing,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14, offset: const Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start,
          children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Row(children: [
            Container(
              width: 38, height: 38,
              decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [BoxShadow(
                      color: _cyan.withValues(alpha: 0.28),
                      blurRadius: 8, offset: const Offset(0, 3))]),
              child: Icon(icon, color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
              Text(sub, style: const TextStyle(color: _faint, fontSize: 11)),
            ])),
            if (trailing != null) trailing,
          ]),
        ),
        const Divider(height: 1, color: _line),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final canProceed = _canProceed();
    final isLast     = _step == _totalSteps;
    final bottom     = MediaQuery.of(context).padding.bottom;

    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 22, offset: const Offset(0, -6))]),
      child: Row(children: [
        if (_step > 1) ...[
          GestureDetector(
            onTap: () => setState(() => _step--),
            child: Container(
              width: 52, height: 52,
              decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border)),
              child: const Icon(Icons.arrow_back_ios_new_rounded,
                  color: _muted, size: 18))),
          const SizedBox(width: 12),
        ],
        Expanded(
          child: GestureDetector(
            onTap: (canProceed && !_loading && !_checkingInstant)
                ? () {
                    if (_isInstant && _step == 1 && !isLast) {
                      _checkInstantAndProceed();
                    } else if (isLast) {
                      _askConfirm();
                    } else {
                      setState(() => _step++);
                    }
                  }
                : null,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              decoration: BoxDecoration(
                gradient: canProceed && !_checkingInstant
                    ? const LinearGradient(colors: [_cyan, _cyanDeep]) : null,
                color: (canProceed && !_checkingInstant)
                    ? null : const Color(0xFFE2E8F0),
                borderRadius: BorderRadius.circular(16),
                boxShadow: canProceed && !_checkingInstant
                    ? [BoxShadow(
                        color: _cyan.withValues(alpha: 0.40),
                        blurRadius: 16, offset: const Offset(0, 5))]
                    : []),
              child: Center(
                child: (_loading || _checkingInstant)
                    ? const SizedBox(width: 22, height: 22,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2.5))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                        if (isLast)
                          const Icon(Icons.payments_rounded,
                              color: Colors.white, size: 18),
                        if (isLast) const SizedBox(width: 8),
                        Text(
                          _isInstant && _step == 1 && !isLast
                              ? 'Check Availability'
                              : isLast
                                  ? 'Choose Payment & Confirm'
                                  : 'Continue',
                          style: TextStyle(
                            color: canProceed ? Colors.white : _faint,
                            fontSize: 15,
                            fontWeight: FontWeight.w900)),
                        const SizedBox(width: 8),
                        Icon(Icons.arrow_forward_rounded,
                            color: canProceed ? Colors.white : _faint,
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

// ── Promo Sheet (unchanged) ───────────────────────────────────────
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
          margin: const EdgeInsets.only(top: 10),
          width: 40, height: 4,
          decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(2))),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
          child: Row(children: [
            Container(
              width: 40, height: 40,
              decoration: BoxDecoration(
                  color: const Color(0xFFECFEFF),
                  borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.local_offer_rounded,
                  color: _cyanDk, size: 20)),
            const SizedBox(width: 12),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Text('Choose Promo Code',
                  style: TextStyle(fontSize: 16,
                      fontWeight: FontWeight.w900,
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
                        Icon(Icons.local_offer_outlined,
                            size: 40, color: Color(0xFFCBD5E1)),
                        SizedBox(height: 12),
                        Text('No offers available',
                            style: TextStyle(fontWeight: FontWeight.bold,
                                color: Color(0xFF374151))),
                        SizedBox(height: 4),
                        Text('Check back soon!',
                            style: TextStyle(color: Color(0xFF9CA3AF),
                                fontSize: 13)),
                      ]))
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 30),
                      children: [
                        if (promos.isNotEmpty) ...[
                          const Padding(
                            padding: EdgeInsets.only(bottom: 10, left: 4),
                            child: Text('AVAILABLE OFFERS',
                                style: TextStyle(
                                    color: Color(0xFF9CA3AF),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 1.5))),
                          ...promos.map((p) {
                            final isApplied = appliedId == p['id'].toString();
                            final minOrder  = p['min_order_amount'] != null
                                ? (p['min_order_amount'] as num).toInt() : 0;
                            final otherApplied = appliedId.isNotEmpty && !isApplied;
                            final canApply  = baseAmount >= minOrder && !otherApplied;
                            return GestureDetector(
                              onTap: canApply ? () => onApply(p) : null,
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 180),
                                margin: const EdgeInsets.only(bottom: 10),
                                padding: const EdgeInsets.all(14),
                                decoration: BoxDecoration(
                                  color: isApplied
                                      ? const Color(0xFFECFDF5)
                                      : canApply ? Colors.white
                                          : const Color(0xFFF8FAFC),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                      color: isApplied
                                          ? const Color(0xFF6EE7B7)
                                          : canApply
                                              ? const Color(0xFFE8EDF2)
                                              : const Color(0xFFF1F5F9),
                                      width: isApplied ? 1.5 : 1)),
                                child: Row(children: [
                                  Container(
                                    width: 52, height: 52,
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                          colors: isApplied
                                              ? [const Color(0xFF10B981), const Color(0xFF059669)]
                                              : canApply
                                                  ? [_cyan, _cyanDk]
                                                  : [const Color(0xFFCBD5E1), const Color(0xFF94A3B8)]),
                                      borderRadius: BorderRadius.circular(14)),
                                    child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
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
                                          style: TextStyle(
                                              fontWeight: FontWeight.w900,
                                              fontSize: 14, letterSpacing: 1,
                                              color: isApplied
                                                  ? const Color(0xFF059669)
                                                  : canApply
                                                      ? const Color(0xFF0F172A)
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
                                                  fontSize: 9, fontWeight: FontWeight.w800))),
                                      ],
                                    ]),
                                    const SizedBox(height: 2),
                                    if ((p['description'] as String? ?? '').isNotEmpty)
                                      Text(p['description'] as String,
                                          style: TextStyle(
                                              color: canApply
                                                  ? const Color(0xFF6B7280)
                                                  : const Color(0xFFD1D5DB),
                                              fontSize: 11),
                                          maxLines: 1, overflow: TextOverflow.ellipsis),
                                    const SizedBox(height: 4),
                                    Text(_calcDiscount(p),
                                        style: TextStyle(
                                            color: isApplied
                                                ? const Color(0xFF10B981)
                                                : canApply ? _cyanDk
                                                : const Color(0xFFD1D5DB),
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700)),
                                    if (!canApply && !otherApplied)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 3),
                                        child: Text('Min order ₹$minOrder required',
                                            style: const TextStyle(
                                                color: Color(0xFFEF4444),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w600))),
                                    if (otherApplied)
                                      const Padding(
                                        padding: EdgeInsets.only(top: 3),
                                        child: Text('Remove active promo first',
                                            style: TextStyle(
                                                color: Color(0xFF94A3B8),
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
                                                fontSize: 11, fontWeight: FontWeight.w700))))
                                  else if (canApply)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFECFEFF),
                                          borderRadius: BorderRadius.circular(10)),
                                      child: const Text('Apply',
                                          style: TextStyle(color: _cyanDk,
                                              fontSize: 11, fontWeight: FontWeight.w800)))
                                  else if (otherApplied)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 6),
                                      decoration: BoxDecoration(
                                          color: const Color(0xFFF1F5F9),
                                          borderRadius: BorderRadius.circular(10)),
                                      child: const Text('Remove active promo first',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(color: Color(0xFF94A3B8),
                                              fontSize: 9, fontWeight: FontWeight.w600))),
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
                            child: const Row(children: [
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