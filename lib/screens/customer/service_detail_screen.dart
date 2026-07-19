import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/cart_service.dart';
import 'booking_flow_screen.dart';

// ── Pricing config (LOCAL FALLBACK) ──────────────────────────────────────────
class _ServicePricing {
  static const Map<String, Map<String, dynamic>> config = {
    'Bathroom Cleaning': {
      'type': 'per_unit', 'unit': 'Bathroom', 'unit_plural': 'Bathrooms',
      'price_per_unit': 99, 'duration_per_unit': 45, 'min': 1, 'max': 6,
    },
    'Fan Cleaning': {
      'type': 'per_unit', 'unit': 'Fan', 'unit_plural': 'Fans',
      'price_per_unit': 49, 'duration_per_unit': 20, 'min': 1, 'max': 10,
    },
    'Balcony Cleaning': {
      'type': 'per_unit', 'unit': 'Balcony', 'unit_plural': 'Balconies',
      'price_per_unit': 79, 'duration_per_unit': 45, 'min': 1, 'max': 4,
    },
    'Dusting & Wiping': {
      'type': 'by_bhk',
      'prices':    {'1 BHK': 299, '2 BHK': 449, '3 BHK': 599},
      'durations': {'1 BHK': 30,  '2 BHK': 40,  '3 BHK': 50},
    },
    'Sweeping & Mopping': {
      'type': 'by_bhk',
      'prices':    {'1 BHK': 249, '2 BHK': 399, '3 BHK': 549},
      'durations': {'1 BHK': 30,  '2 BHK': 40,  '3 BHK': 50},
    },
    'Full House Cleaning': {
      'type': 'by_bhk',
      'prices':    {'1 BHK': 599, '2 BHK': 899,  '3 BHK': 1199},
      'durations': {'1 BHK': 240, '2 BHK': 300,  '3 BHK': 360},
    },
    'Kitchen Cleaning':            {'type': 'fixed', 'duration': 60},
    'Kitchen Cabinet Cleaning':    {'type': 'fixed', 'duration': 180},
    'Utensil Cleaning':            {'type': 'fixed', 'duration': 30},
    'Wardrobe Cleaning':           {'type': 'fixed', 'duration': 150},
    'Refrigerator Cleaning':       {'type': 'fixed', 'duration': 60},
    'Pre-Party Express Cleaning':  {'type': 'fixed', 'duration': 120},
    'After-Party Cleanup':         {'type': 'fixed', 'duration': 120},
    'Hourly Cleaning':             {'type': 'hourly', 'price_per_hour': 99,
                                    'min_hours': 1, 'max_hours': 6},
  };

  static Map<String, dynamic> get(String name) =>
      config[name] ?? {'type': 'fixed', 'duration': 60};
}

// ── Screen ────────────────────────────────────────────────────────────────────
class ServiceDetailScreen extends StatefulWidget {
  final String serviceId;
  const ServiceDetailScreen({super.key, required this.serviceId});
  @override
  State<ServiceDetailScreen> createState() => _ServiceDetailScreenState();
}

class _ServiceDetailScreenState extends State<ServiceDetailScreen>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  final _cart     = CartService.instance;

  Map<String, dynamic>? _service;
  bool   _loading = true;
  bool   _liked   = false;
  String _tab     = 'about';

  late AnimationController _entranceCtrl;
  late Animation<double>   _entranceFade;
  late Animation<Offset>   _entranceSlide;

  int    _quantity     = 1;
  int    _selectedHours = 1;
  String _selectedBhk  = '2 BHK';
  bool   _isFirstBooking = false;

  List<Map<String, dynamic>> _reviews     = [];
  Map<String, dynamic>?      _reviewStats;
  bool             _reviewsLoading = true;
  RealtimeChannel? _reviewChannel;

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _cyanLt = Color(0xFFCFFAFE);
  static const _cyanXl = Color(0xFFECFEFF);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _bg     = Color(0xFFF8FAFC);
  static const _green  = Color(0xFF10B981);
  static const _greenDk = Color(0xFF059669);

  static const _emojis = <String, String>{
    'Bathroom Cleaning':          '🚿',
    'Kitchen Cleaning':           '🍳',
    'Kitchen Cabinet Cleaning':   '🗄️',
    'Fan Cleaning':               '💨',
    'Balcony Cleaning':           '🌿',
    'Dusting & Wiping':           '🧹',
    'Sweeping & Mopping':         '🧺',
    'Utensil Cleaning':           '🍽️',
    'Wardrobe Cleaning':          '👔',
    'Refrigerator Cleaning':      '❄️',
    'Full House Cleaning':        '🏠',
    'Pre-Party Express Cleaning': '🎉',
    'After-Party Cleanup':        '🧽',
    'Hourly Cleaning':            '⏰',
  };

  static const Map<String, String> _assetMap = {
    '6f150323-d018-44c0-bfe2-2037efa1f5c0': 'assets/services/bathroom-cleaning.png',
    '6201b258-ed2c-4c83-b8e7-bd413cc5b67b': 'assets/services/wardrobe.png',
    '6678a63d-059c-4ca5-ad11-3781f8449bb0': 'assets/services/full-home-cleaning.png',
    'b7e6db9d-455d-46d5-ba4d-8e993fe1255d': 'assets/services/fan-cleaning.png',
    '42719385-f88c-41ab-9e59-6ac4856f6112': 'assets/services/dusting-wiping.png',
    '2b3bd63d-c1d5-40cf-a818-33501e9e61b4': 'assets/services/sweeping-mopping.png',
    'ab1004e9-de4e-4ab6-9d34-30d7b23913a3': 'assets/services/fridge-cleaning.png',
    '423a1354-d995-49df-ba67-effcb43befbf': 'assets/services/kitchen-cleaning.png',
    '5af62745-c480-4579-a81a-a6a267cef2c3': 'assets/services/Utensils-cleaning.png',
    '581ee014-e42b-43bf-9818-692b08a0ac53': 'assets/services/cabinet.png',
    'ae4eac44-3444-4d45-b4a3-6387c043d5cf': 'assets/services/balcony-cleaning.png',
    'c104cecf-dc59-4514-bbaa-33301da6db1e': 'assets/services/after.png',
    '44a7c787-41f1-4ed9-b8e6-5066dcc009ce': 'assets/services/pre.png',
  };

  String? _assetFor(Map<String, dynamic> svc) =>
      _assetMap[svc['id'] as String? ?? ''];

  // ── Cart helpers ──────────────────────────────────────────────
  bool get _isCartable =>
      CartService.isCartable(_service?['name'] as String? ?? '');
  bool get _inCart => _cart.quantityOf(widget.serviceId) > 0;

  CartItem _buildCartItem() {
    final name = _service?['name'] as String? ?? '';
    return CartItem(
      serviceId:       widget.serviceId,
      serviceName:     name,
      pricePerUnit:    _computedPrice,
      durationPerUnit: CartService.durationFor(name),
      emoji:           _emojis[name],
      maxQty:          CartService.maxQtyFor(name),
      type:            CartService.typeOf(name),
    );
  }

  String _pluralize(String word) {
    if (word.isEmpty) return word;
    final lower = word.toLowerCase();
    if (lower.endsWith('y') && word.length > 1 &&
        !'aeiou'.contains(lower[lower.length - 2])) {
      return '${word.substring(0, word.length - 1)}ies';
    }
    return '${word}s';
  }

  String _fallbackUnitLabel(String serviceName) {
    const suffix = ' Cleaning';
    if (serviceName.endsWith(suffix)) {
      return serviceName.substring(0, serviceName.length - suffix.length);
    }
    return serviceName;
  }

  static const _maxServiceMinutes = 180;

  Map<String, dynamic> get _pricing {
    if (_service == null) return {'type': 'fixed', 'duration': 60};
    final svc = _service!;

    final pricingType = (svc['pricing_type'] as String?)?.trim();
    if (pricingType == 'hourly') {
      return {
        'type': 'hourly',
        'price_per_hour': (svc['base_price'] as num?)?.toInt() ?? 99,
        'min_hours': 1,
        'max_hours': 6,
      };
    }

    final p1 = (svc['price_1bhk'] as num?);
    final p2 = (svc['price_2bhk'] as num?);
    final p3 = (svc['price_3bhk'] as num?);
    final hasBhkPrices = p1 != null || p2 != null || p3 != null;

    final durationPerUnit = (svc['duration_per_unit'] as num?)?.toInt();
    final hasPerUnit = durationPerUnit != null && durationPerUnit > 0;

    if (hasBhkPrices) {
      return {
        'type': 'by_bhk',
        'prices': {
          '1 BHK': (p1 ?? 0).toInt(),
          '2 BHK': (p2 ?? 0).toInt(),
          '3 BHK': (p3 ?? 0).toInt(),
        },
        'durations': {
          '1 BHK': (svc['duration_1bhk'] as num?)?.toInt() ?? 240,
          '2 BHK': (svc['duration_2bhk'] as num?)?.toInt() ?? 300,
          '3 BHK': (svc['duration_3bhk'] as num?)?.toInt() ?? 360,
        },
      };
    }

    if (hasPerUnit) {
      final rawLabel = (svc['unit_label'] as String?)?.trim();
      final label = (rawLabel != null && rawLabel.isNotEmpty)
          ? rawLabel
          : _fallbackUnitLabel(svc['name'] as String? ?? 'Unit');
      final maxByTime = (_maxServiceMinutes / durationPerUnit!).floor();
      return {
        'type': 'per_unit',
        'unit': label,
        'unit_plural': _pluralize(label),
        'price_per_unit': (svc['base_price'] as num?)?.toInt() ?? 0,
        'duration_per_unit': durationPerUnit,
        'min': 1,
        'max': maxByTime < 1 ? 1 : maxByTime,
      };
    }

    return {
      'type': 'fixed',
      'duration': (svc['duration_minutes'] as num?)?.toInt() ?? 60,
    };
  }

  int get _originalPrice {
    final p = _pricing;
    switch (p['type'] as String) {
      case 'per_unit': return (p['price_per_unit'] as int? ?? 0);
      case 'by_bhk':  return (p['prices'] as Map)[_selectedBhk] as int;
      case 'hourly':  return (p['price_per_hour'] as int? ?? 0);
      default:        return (_service?['base_price'] as num?)?.toInt() ?? 0;
    }
  }

  static const _firstBookingEligible = {
    'Bathroom Cleaning',
    'Balcony Cleaning',
    'Fan Cleaning',
    'Utensil Cleaning',
    'Kitchen Cleaning',
  };

  bool get _isFirstBookingEligible =>
      _isFirstBooking &&
      _firstBookingEligible.contains(_service?['name'] as String? ?? '');

  int get _computedPrice {
    if (!_isFirstBookingEligible) return _originalPrice;
    return 25;
  }

  static const _durationBufferMins = 10;

  int get _computedDuration {
    final p = _pricing;
    if (p['type'] == 'hourly') return 60; // base 1hr for scheduling
    int exactMins;
    switch (p['type'] as String) {
      case 'per_unit':
        exactMins = (p['duration_per_unit'] as int? ?? 30);
      case 'by_bhk':
        exactMins = (p['durations'] as Map)[_selectedBhk] as int;
      default:
        exactMins = (p['duration'] as int?) ??
            (_service?['duration_minutes'] as num?)?.toInt() ?? 60;
    }
    final withBuffer = exactMins + _durationBufferMins;
    return ((withBuffer / 60).ceil()) * 60;
  }

  int get _displayDuration {
    final p = _pricing;
    if (p['type'] == 'hourly') return 60;
    switch (p['type'] as String) {
      case 'per_unit':
        return (p['duration_per_unit'] as int? ?? 30);
      case 'by_bhk':
        return (p['durations'] as Map)[_selectedBhk] as int;
      default:
        return (p['duration'] as int?) ??
            (_service?['duration_minutes'] as num?)?.toInt() ?? 60;
    }
  }

  @override
  void initState() {
    super.initState();
    _entranceCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 550));
    _entranceFade  = CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut);
    _entranceSlide = Tween<Offset>(
        begin: const Offset(0, 0.05), end: Offset.zero)
        .animate(CurvedAnimation(parent: _entranceCtrl, curve: Curves.easeOut));
    _cart.addListener(_onCartChanged);
    _load();
    _loadReviews();
    _subscribeRealtime();
    _checkFirstBooking();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _reviewChannel?.unsubscribe();
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() { if (mounted) setState(() {}); }

  Future<void> _load() async {
    try {
      final data = await _supabase.from('services')
          .select('*').eq('id', widget.serviceId).single();
      if (mounted) {
        setState(() { _service = data; _loading = false; });
        _entranceCtrl.forward();
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _checkFirstBooking() async {
    final uid = await SupabaseService.loadCachedUserId()
        ?? SupabaseService.currentUserId
        ?? _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _supabase.from('bookings').select('id')
          .eq('customer_id', uid)
          .inFilter('status', ['completed', 'accepted', 'in_progress', 'pending'])
          .limit(1);
      if (mounted) setState(() => _isFirstBooking = (rows as List).isEmpty);
    } catch (_) {}
  }

  Future<void> _loadReviews() async {
    try {
      final results = await Future.wait([
        _supabase.from('reviews_with_user').select('*')
            .eq('service_id', widget.serviceId)
            .order('created_at', ascending: false).limit(50),
        _supabase.from('service_review_stats').select('*')
            .eq('service_id', widget.serviceId).maybeSingle(),
      ]);
      if (!mounted) return;
      setState(() {
        _reviews     = (results[0] as List).cast<Map<String, dynamic>>();
        _reviewStats = results[1] as Map<String, dynamic>?;
        _reviewsLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _reviewsLoading = false);
    }
  }

  void _subscribeRealtime() {
    _reviewChannel = _supabase
        .channel('reviews:${widget.serviceId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, schema: 'public', table: 'reviews',
          filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'service_id', value: widget.serviceId),
          callback: (_) => _loadReviews())
        .subscribe();
  }

  bool _checkingInstant = false;

  Future<void> _navigate(String mode) async {
    if (_service == null) return;
    if (mode == 'instant') {
      setState(() => _checkingInstant = true);
      final reason = await _checkInstantAvailability();
      if (!mounted) return;
      setState(() => _checkingInstant = false);
      if (reason != null) { _showInstantBusyDialog(reason); return; }
    }
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BookingFlowScreen(
        mode:             mode,
        serviceId:        _service!['id'] as String,
        overridePrice:    _computedPrice,
        overrideDuration: _computedDuration,
        selectedBhk:      _pricing['type'] == 'by_bhk' ? _selectedBhk : null,
        quantity:         null,
        isFirstBooking:   _isFirstBookingEligible,
      ),
    ));
  }

  Future<String?> _checkInstantAvailability() async {
    final supabase = Supabase.instance.client;
    final now      = DateTime.now();
    if (now.hour < 7 || now.hour >= 19) return 'time_window';
    final endMins = now.hour * 60 + now.minute + _computedDuration;
    if (endMins > 19 * 60) return 'time_window';
    try {
      final workersData = await supabase
          .from('workers').select('user_id, schedule, is_available')
          .eq('is_available', true);
      final workers = (workersData as List).cast<Map<String, dynamic>>();
      if (workers.isEmpty) return 'no_workers';
      final activeData = await supabase.from('bookings')
          .select('worker_id, scheduled_at, booking_duration_minutes, services(duration_minutes)')
          .inFilter('status', ['accepted', 'in_progress'])
          .inFilter('payment_status', ['cod', 'paid']);
      final active = (activeData as List).cast<Map<String, dynamic>>();
      final days = ['', 'monday', 'tuesday', 'wednesday',
          'thursday', 'friday', 'saturday', 'sunday'];
      final dayName = days[now.weekday];
      final slotMins    = now.hour * 60 + now.minute;
      final slotEndMins = slotMins + _computedDuration;
      for (final w in workers) {
        final schedule = w['schedule'] as Map<String, dynamic>?;
        bool inShift;
        if (schedule == null) {
          inShift = slotMins >= 420 && slotEndMins <= 1140;
        } else {
          final day = schedule[dayName] as Map<String, dynamic>?;
          if (day == null || day['enabled'] != true) continue;
          final start = _toMins(day['start'] as String? ?? '07:00');
          final end   = _toMins(day['end']   as String? ?? '19:00');
          if (slotMins < start || slotEndMins > end) continue;
          bool inBreak = false;
          for (final b in (day['breaks'] as List? ?? [])) {
            final bs = _toMins(b['from'] as String? ?? '00:00');
            final be = _toMins(b['to']   as String? ?? '00:00');
            if (bs < slotEndMins && be > slotMins) { inBreak = true; break; }
          }
          if (inBreak) continue;
          inShift = true;
        }
        if (!inShift) continue;
        final workerId = w['user_id'] as String;
        bool busy = false;
        final slotEnd = now.add(Duration(minutes: _computedDuration));
        for (final bk in active) {
          if (bk['worker_id'] != workerId) continue;
          final bDt = DateTime.tryParse(bk['scheduled_at'].toString())?.toLocal();
          if (bDt == null) continue;
          final bDur = (bk['booking_duration_minutes'] as num?)?.toInt()
              ?? (bk['services']?['duration_minutes'] as num?)?.toInt()
              ?? _computedDuration;
          final bEnd = bDt.add(Duration(minutes: bDur));
          if (now.isBefore(bEnd) && slotEnd.isAfter(bDt)) { busy = true; break; }
        }
        if (!busy) return null;
      }
      return 'no_workers';
    } catch (e) {
      debugPrint('instant check error: $e');
      return null;
    }
  }

  int _toMins(String t) {
    final p = t.split(':');
    return int.parse(p[0]) * 60 + int.parse(p[1]);
  }

  void _showInstantTimeDialog() {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white, elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64,
              decoration: const BoxDecoration(
                  color: Color(0xFFFFF7ED), shape: BoxShape.circle),
              child: const Center(child: Text('🕐', style: TextStyle(fontSize: 32)))),
            const SizedBox(height: 16),
            const Text('Instant Booking\nNot Available Now',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 10),
            const Text('Instant bookings are only available\nbetween 7:00 AM - 7:00 PM.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                  color: _cyanXl, borderRadius: BorderRadius.circular(12)),
              child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                Icon(Icons.wb_sunny_rounded, color: _cyanDk, size: 16),
                SizedBox(width: 8),
                Text('Available: 7:00 AM – 7:00 PM',
                    style: TextStyle(color: Color(0xFF0E7490),
                        fontSize: 13, fontWeight: FontWeight.w800)),
              ])),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                if (_service == null) return;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => BookingFlowScreen(
                    mode: 'schedule', serviceId: _service!['id'] as String,
                    overridePrice: _computedPrice, overrideDuration: _computedDuration,
                    selectedBhk: _pricing['type'] == 'by_bhk' ? _selectedBhk : null,
                    quantity: null,
                    isFirstBooking: _isFirstBookingEligible)));
              },
              child: Container(
                width: double.infinity, height: 52, alignment: Alignment.center,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_cyan, Color(0xFF0E7490)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: _cyan.withValues(alpha: 0.32),
                        blurRadius: 10, offset: const Offset(0, 4))]),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Schedule Instead', style: TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                ]))),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 44, alignment: Alignment.center,
                decoration: BoxDecoration(color: _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                child: const Text('OK', style: TextStyle(
                    color: _muted, fontSize: 14, fontWeight: FontWeight.w700)))),
          ]),
        ),
      ),
    );
  }

  void _showInstantBusyDialog(String reason) {
    if (reason == 'time_window') { _showInstantTimeDialog(); return; }
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white, elevation: 0,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64,
              decoration: const BoxDecoration(
                  color: Color(0xFFFEF2F2), shape: BoxShape.circle),
              child: const Center(child: Text('👷', style: TextStyle(fontSize: 32)))),
            const SizedBox(height: 16),
            const Text('All Pros Are\nBusy Right Now',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 10),
            const Text('All our professionals are currently\noccupied. Try after some time\nor schedule for a later slot.',
                textAlign: TextAlign.center,
                style: TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                if (_service == null) return;
                Navigator.push(context, MaterialPageRoute(
                  builder: (_) => BookingFlowScreen(
                    mode: 'schedule', serviceId: _service!['id'] as String,
                    overridePrice: _computedPrice, overrideDuration: _computedDuration,
                    selectedBhk: _pricing['type'] == 'by_bhk' ? _selectedBhk : null,
                    quantity: null,
                    isFirstBooking: _isFirstBookingEligible)));
              },
              child: Container(
                width: double.infinity, height: 52, alignment: Alignment.center,
                decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_cyan, Color(0xFF0E7490)]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: _cyan.withValues(alpha: 0.32),
                        blurRadius: 10, offset: const Offset(0, 4))]),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.calendar_month_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 8),
                  Text('Schedule Instead', style: TextStyle(
                      color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)),
                ]))),
            const SizedBox(height: 10),
            GestureDetector(
              onTap: () => Navigator.pop(ctx),
              child: Container(
                width: double.infinity, height: 44, alignment: Alignment.center,
                decoration: BoxDecoration(color: _bg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border)),
                child: const Text('Try After Some Time', style: TextStyle(
                    color: _muted, fontSize: 14, fontWeight: FontWeight.w700)))),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(backgroundColor: _bg,
          body: Center(child: CircularProgressIndicator(color: _cyan)));
    }
    if (_service == null) {
      return Scaffold(backgroundColor: _bg,
        body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text('Service not found',
              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: _ink)),
          const SizedBox(height: 16),
          TextButton(onPressed: () => Navigator.pop(context),
              child: const Text('Go back')),
        ])));
    }
    final svc   = _service!;
    final name  = svc['name'] as String;
    final emoji = _emojis[name] ?? '🧹';

    return Scaffold(
      backgroundColor: _bg,
      body: FadeTransition(
        opacity: _entranceFade,
        child: SlideTransition(
          position: _entranceSlide,
          child: Stack(children: [
            CustomScrollView(
              physics: const BouncingScrollPhysics(),
              slivers: [
                _buildHero(svc, name, emoji),
                SliverToBoxAdapter(child: _buildBody(svc)),
                const SliverToBoxAdapter(child: SizedBox(height: 200)),
              ],
            ),
            _buildBottomBar(),
          ]),
        ),
      ),
    );
  }

  Widget _buildHero(Map<String, dynamic> svc, String name, String emoji) {
    final avg = (_reviewStats?['avg_rating'] as num?)?.toDouble() ?? 4.8;
    return SliverAppBar(
      expandedHeight: 310, pinned: true,
      backgroundColor: Colors.white, surfaceTintColor: Colors.transparent, elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax, titlePadding: EdgeInsets.zero,
        title: const SizedBox.shrink(),
        background: Stack(fit: StackFit.expand, children: [
          _heroImage(svc, emoji),
          Positioned(left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: const BoxDecoration(color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(32))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                if ((svc['category'] as String?) != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(color: _cyanLt,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: _cyan.withValues(alpha: 0.3))),
                    child: Text((svc['category'] as String).toUpperCase(),
                        style: const TextStyle(color: _cyanDk, fontSize: 9,
                            fontWeight: FontWeight.w800, letterSpacing: 1.4))),
                ],
                Text(name, style: const TextStyle(fontSize: 22,
                    fontWeight: FontWeight.w900, color: _ink, height: 1.2)),
                const SizedBox(height: 10),
                Row(children: [
                  _chip('⭐ ${avg.toStringAsFixed(1)}',
                      const Color(0xFFFFFBEB), const Color(0xFFFDE68A), const Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  _chip('⏱ ~$_displayDuration min',
                      _cyanXl, _cyan.withValues(alpha: 0.25), _cyanDk),
                  const SizedBox(width: 8),
                  _chip('✓ Verified Professional',
                      const Color(0xFFECFDF5), const Color(0xFF6EE7B7), const Color(0xFF065F46)),
                ]),
              ])),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                _iconBtn(Icons.arrow_back_ios_new_rounded, () => Navigator.pop(context)),
                Row(children: [
                  _iconBtn(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded, () {
                    setState(() => _liked = !_liked);
                    HapticFeedback.lightImpact();
                  }, iconColor: _liked ? Colors.red : _ink),
                  const SizedBox(width: 8),
                  _iconBtn(Icons.ios_share_rounded, () {
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied!')));
                  }),
                ]),
              ])),
          ),
        ]),
      ),
    );
  }

  Widget _heroImage(Map<String, dynamic> svc, String emoji) {
    final asset = _assetFor(svc);
    final url   = (svc['image_url'] as String?)?.trim();
    Widget placeholder() => Stack(fit: StackFit.expand, children: [
      Container(color: const Color(0xFFECFEFF)),
      Positioned(top: -80, right: -80, child: Container(width: 280, height: 280,
          decoration: const BoxDecoration(color: Color(0xFFCFFAFE), shape: BoxShape.circle))),
      Positioned(bottom: -40, left: -60, child: Container(width: 200, height: 200,
          decoration: const BoxDecoration(color: Color(0xFFBAE6FD), shape: BoxShape.circle))),
      Positioned(right: 10, bottom: 70, child: Text(emoji,
          style: TextStyle(fontSize: 130, color: Colors.white.withValues(alpha: 0.18)))),
      Positioned(right: 24, top: 72, child: Container(
          width: 108, height: 108,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: _cyan.withValues(alpha: 0.22), blurRadius: 30, spreadRadius: 4),
                BoxShadow(color: _cyan.withValues(alpha: 0.08), blurRadius: 60, spreadRadius: 12),
              ]),
          child: Center(child: Text(emoji, style: const TextStyle(fontSize: 54))))),
    ]);
    if (asset != null) {
      return Image.asset(asset, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) {
            if (url != null && url.isNotEmpty) {
              return Image.network(url, fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => placeholder());
            }
            return placeholder();
          });
    }
    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
          loadingBuilder: (ctx, child, prog) =>
              prog == null ? child : Container(color: const Color(0xFFECFEFF)),
          errorBuilder: (_, __, ___) => placeholder());
    }
    return placeholder();
  }

  Widget _chip(String label, Color bg, Color borderColor, Color textColor) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor)),
        child: Text(label, style: TextStyle(fontSize: 11,
            fontWeight: FontWeight.w700, color: textColor)));

  Widget _iconBtn(IconData icon, VoidCallback onTap, {Color? iconColor}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle,
              border: Border.all(color: _border),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 8, offset: const Offset(0, 2))]),
          child: Icon(icon, color: iconColor ?? _ink, size: 18)));

  Widget _buildBody(Map<String, dynamic> svc) {
    return Container(
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_isFirstBookingEligible) _buildFirstBookingBanner(),
        _buildPriceDisplay(),
        const SizedBox(height: 8),
        Divider(color: _border, height: 1, indent: 20, endIndent: 20),
        _buildTabs(),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) => FadeTransition(opacity: anim, child: child),
          child: Padding(
            key: ValueKey(_tab),
            padding: const EdgeInsets.all(20),
            child: _buildTabContent(svc),
          ),
        ),
      ]),
    );
  }

  Widget _buildFirstBookingBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: const Color(0xFFECFDF5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFF6EE7B7))),
      child: Row(children: [
        Container(width: 42, height: 42,
          decoration: BoxDecoration(color: const Color(0xFF10B981),
              borderRadius: BorderRadius.circular(12)),
          child: const Center(child: Text('🎉', style: TextStyle(fontSize: 22)))),
        const SizedBox(width: 12),
        const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('First booking — just ₹25!',
              style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w900, fontSize: 13)),
          SizedBox(height: 2),
          Text('No promo code needed. One time only.',
              style: TextStyle(color: Color(0xFF059669), fontSize: 11)),
        ])),
        const Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹25', style: TextStyle(color: Color(0xFF059669),
              fontSize: 22, fontWeight: FontWeight.w900)),
          Text('only', style: TextStyle(color: Color(0xFF6EE7B7), fontSize: 10)),
        ]),
      ]),
    );
  }




  Widget _counterBtn(IconData icon, bool enabled, VoidCallback onTap) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        width: 48, height: 48,
        decoration: BoxDecoration(
          color: enabled ? _cyan : _border, shape: BoxShape.circle,
          boxShadow: enabled ? [BoxShadow(color: _cyan.withValues(alpha: 0.30),
              blurRadius: 12, offset: const Offset(0, 4))] : []),
        child: Icon(icon, color: enabled ? Colors.white : _faint, size: 24)));
  }

  Widget _buildBhkSelector(Map<String, dynamic> p) {
    final prices    = p['prices']    as Map;
    final durations = p['durations'] as Map;
    const bhks      = ['1 BHK', '2 BHK', '3 BHK'];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Padding(
        padding: EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Icon(Icons.apartment_rounded, color: _cyanDk, size: 18),
          SizedBox(width: 8),
          Text('Select home size', style: TextStyle(color: _ink,
              fontWeight: FontWeight.w800, fontSize: 14)),
        ])),
      Row(children: bhks.map((bhk) {
        final active = _selectedBhk == bhk;
        final price  = prices[bhk] as int;
        final dur    = durations[bhk] as int;
        return Expanded(child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () { setState(() => _selectedBhk = bhk); HapticFeedback.selectionClick(); },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: active ? _cyan : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: active ? _cyan : _border, width: active ? 0 : 1.5),
                boxShadow: active
                    ? [BoxShadow(color: _cyan.withValues(alpha: 0.30),
                        blurRadius: 14, offset: const Offset(0, 6))]
                    : [BoxShadow(color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6, offset: const Offset(0, 2))]),
              child: Column(children: [
                Text(bhk, style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13,
                    color: active ? Colors.white : _ink)),
                const SizedBox(height: 6),
                Text('₹$price', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18,
                    color: active ? Colors.white : _cyan)),
                const SizedBox(height: 3),
                Text('~${dur}m', style: TextStyle(fontSize: 10,
                    color: active ? Colors.white.withValues(alpha: 0.75) : _faint)),
              ]),
            ),
          ),
        ));
      }).toList()),
    ]);
  }

  Widget _buildPriceDisplay() {
    final display  = _computedPrice;
    final original = _originalPrice;
    final isFirst  = _isFirstBookingEligible;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isFirst ? 'FIRST BOOKING PRICE' : 'TOTAL PRICE',
              style: const TextStyle(color: _faint, fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹$display', style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900,
                color: isFirst ? const Color(0xFF10B981) : _ink, height: 1.0)),
            const SizedBox(width: 10),
            Padding(padding: const EdgeInsets.only(bottom: 4),
              child: Text(isFirst ? '₹$original' : '₹${(display * 1.4).round()}',
                  style: const TextStyle(fontSize: 16, color: _faint,
                      decoration: TextDecoration.lineThrough))),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
              isFirst ? '🎉 ₹${original - display} off for first booking'
                  : 'Save ₹${(display * 0.4).round()}',
              style: const TextStyle(color: Color(0xFF065F46),
                  fontSize: 11, fontWeight: FontWeight.w700))),
        ])),
        const SizedBox(width: 16),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(children: [
            const Text('⭐', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 4),
            Text(((_reviewStats?['avg_rating'] as num?)?.toDouble() ?? 4.8).toStringAsFixed(1),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900, color: _ink)),
          ]),
          Text(_reviewStats != null
              ? '${(_reviewStats!['total_reviews'] as num?)?.toInt() ?? 0} reviews'
              : 'No reviews',
              style: const TextStyle(color: _faint, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('2,400+ bookings',
              style: TextStyle(color: _muted, fontSize: 11, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  Widget _buildTabs() {
    const tabs = ['about', 'includes', 'reviews'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: tabs.map((t) {
        final active = _tab == t;
        return GestureDetector(
          onTap: () { setState(() => _tab = t); HapticFeedback.selectionClick(); },
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Column(children: [
              const SizedBox(height: 14),
              Text(t[0].toUpperCase() + t.substring(1), style: TextStyle(
                  fontSize: 14,
                  fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                  color: active ? _ink : _faint)),
              const SizedBox(height: 10),
              AnimatedContainer(duration: const Duration(milliseconds: 200),
                  height: 2.5, width: active ? 36 : 0,
                  decoration: BoxDecoration(color: _cyan,
                      borderRadius: BorderRadius.circular(2))),
            ])));
      }).toList()));
  }

  Widget _buildTabContent(Map<String, dynamic> svc) {
    switch (_tab) {
      case 'about':    return _buildAbout(svc);
      case 'includes': return _buildIncludes(svc);
      default:         return _buildReviews();
    }
  }

  Widget _buildAbout(Map<String, dynamic> svc) {
    final desc = svc['description'] as String? ?? 'Professional cleaning by verified experts.';
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(desc, style: const TextStyle(color: _ink, fontSize: 14, height: 1.75)),
      const SizedBox(height: 12),
      const Text(
        'Our verified professional will arrive at your home at the '
        'scheduled time and take care of the cleaning with attention '
        'to detail. Please note that cleaning equipment and materials '
        'need to be arranged by you — our experts bring the skill, '
        'you provide the supplies.',
        style: TextStyle(color: _ink, fontSize: 13.5, height: 1.7)),
      const SizedBox(height: 24),
      const Text('What to expect', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 14),
      ...[
        {'text': '✓ Verified & background-checked professionals', 'color': const Color(0xFF000000)},
        {'text': '✓ ~$_displayDuration min estimated duration',   'color': const Color(0xFF000000)},
      ].map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 6, height: 6,
              decoration: BoxDecoration(color: item['color'] as Color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(item['text'] as String,
              style: const TextStyle(color: _ink, fontSize: 13, fontWeight: FontWeight.w500))),
        ]))),
      const SizedBox(height: 24),
      const Text('Why Cleenzo', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 14),
      GridView.count(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 2.6,
        children: [
          _whyCard('🛡️', 'Instant Booking',        const Color(0xFFECFEFF), const Color(0xFF0891B2)),
          _whyCard('⏱️', 'House Help in Minutes',  const Color(0xFFECFEFF), const Color(0xFF0891B2)),
          _whyCard('🔄', 'Safe And Trusted',        const Color(0xFFECFEFF), const Color(0xFF0891B2)),
          _whyCard('💳', 'Verified and trained Staff', const Color(0xFFECFEFF), const Color(0xFF0891B2)),
        ]),
    ]);
  }

  Widget _whyCard(String emoji, String title, Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14),
          border: Border.all(color: textColor.withValues(alpha: 0.15))),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 24)),
        const SizedBox(width: 10),
        Expanded(child: Text(title, style: TextStyle(color: textColor,
            fontSize: 12.5, fontWeight: FontWeight.w800, height: 1.2))),
      ]));
  }

  Widget _buildIncludes(Map<String, dynamic> svc) {
    final inc = (svc['includes'] as List?)?.cast<String>() ?? [];
    final exc = (svc['excludes'] as List?)?.cast<String>() ?? [];
    if (inc.isEmpty && exc.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Text('📋', style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text('No details yet', style: TextStyle(color: _faint, fontSize: 13)),
        ])));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (inc.isNotEmpty) ...[
        const Text('Included', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 12),
        ...inc.map((item) => _includeRow(item, true)),
        const SizedBox(height: 20),
      ],
      if (exc.isNotEmpty) ...[
        const Text('Not included', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 12),
        ...exc.map((item) => _includeRow(item, false)),
      ],
    ]);
  }

  Widget _includeRow(String text, bool included) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(width: 24, height: 24,
          decoration: BoxDecoration(
              color: included ? const Color(0xFF16A34A) : const Color(0xFFDC2626),
              shape: BoxShape.circle),
          child: Icon(included ? Icons.check_rounded : Icons.close_rounded,
              size: 14, color: Colors.white)),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(
            color: _ink, fontSize: 13, fontWeight: FontWeight.w700))),
      ]));
  }

  Widget _buildReviews() {
    if (_reviewsLoading) {
      return const Padding(padding: EdgeInsets.symmetric(vertical: 40),
          child: Center(child: CircularProgressIndicator(color: _cyan)));
    }
    final avgRating  = (_reviewStats?['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final totalCount = (_reviewStats?['total_reviews'] as num?)?.toInt() ?? 0;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Column(children: [
          Text(avgRating > 0 ? avgRating.toStringAsFixed(1) : '–',
              style: const TextStyle(fontSize: 52, fontWeight: FontWeight.w900,
                  color: _ink, height: 1.0)),
          Row(children: List.generate(5, (i) => Icon(
              i < avgRating.floor() ? Icons.star_rounded : Icons.star_border_rounded,
              color: const Color(0xFFF59E0B), size: 14))),
          const SizedBox(height: 4),
          Text('$totalCount reviews', style: const TextStyle(color: _faint,
              fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(width: 24),
        Expanded(child: Column(
          children: [5, 4, 3, 2, 1].map((star) {
            final cnt = (_reviewStats?['${_starKey(star)}_star'] as num?)?.toInt() ?? 0;
            final pct = totalCount > 0 ? cnt / totalCount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                SizedBox(width: 12, child: Text('$star',
                    style: const TextStyle(color: _faint, fontSize: 11, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(3),
                    child: LinearProgressIndicator(value: pct, backgroundColor: _border,
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFF59E0B)), minHeight: 6))),
                const SizedBox(width: 8),
                SizedBox(width: 20, child: Text('$cnt',
                    style: const TextStyle(color: _faint, fontSize: 11))),
              ]));
          }).toList())),
      ]),
      const SizedBox(height: 20),
      const Divider(color: _border, height: 1),
      const SizedBox(height: 16),
      if (_reviews.isEmpty)
        const Center(child: Padding(padding: EdgeInsets.symmetric(vertical: 30),
          child: Column(children: [
            Text('💬', style: TextStyle(fontSize: 40)),
            SizedBox(height: 12),
            Text('No reviews yet', style: TextStyle(color: _faint, fontSize: 13)),
          ])))
      else
        Column(children: _reviews.map((r) => _buildReviewCard(r)).toList()),
    ]);
  }

  String _starKey(int star) => ['zero', 'one', 'two', 'three', 'four', 'five'][star];

  Widget _buildReviewCard(Map<String, dynamic> r) {
    final uid      = _supabase.auth.currentUser?.id;
    final isOwn    = r['user_id'] == uid;
    final fullName = (r['full_name'] as String?) ?? 'User';
    final initials = fullName.trim().split(' ')
        .where((w) => w.isNotEmpty).take(2).map((w) => w[0].toUpperCase()).join();
    final stars    = (r['stars'] as num?)?.toInt() ?? 0;
    final text     = (r['text'] as String?) ?? '';
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr  = createdAt != null ? '${createdAt.day} ${months[createdAt.month - 1]}' : '';
    const avatarColors = [_cyan, Color(0xFF7C3AED), Color(0xFFDB2777),
        Color(0xFF059669), Color(0xFFD97706)];
    final avatarColor = avatarColors[
        fullName.isEmpty ? 0 : fullName.codeUnitAt(0) % avatarColors.length];
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36,
            decoration: BoxDecoration(color: avatarColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: avatarColor.withValues(alpha: 0.3))),
            child: Center(child: Text(initials, style: TextStyle(color: avatarColor,
                fontWeight: FontWeight.w900, fontSize: 12)))),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(isOwn ? 'You' : fullName, style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13, color: _ink)),
              if (isOwn) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(color: _cyanLt,
                      borderRadius: BorderRadius.circular(6)),
                  child: const Text('You', style: TextStyle(color: _cyanDk,
                      fontSize: 9, fontWeight: FontWeight.w800))),
              ],
            ]),
            Text(dateStr, style: const TextStyle(color: _faint, fontSize: 11)),
          ])),
          Row(children: List.generate(5, (i) => Icon(
              i < stars ? Icons.star_rounded : Icons.star_border_rounded,
              color: const Color(0xFFF59E0B), size: 13))),
        ]),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(color: _muted, fontSize: 13, height: 1.6)),
        ],
        const SizedBox(height: 12),
        const Divider(color: _border, height: 1),
      ]));
  }

  Widget _buildBottomBar() {
    final bottom   = MediaQuery.of(context).padding.bottom;
    final price    = _computedPrice;
    final isFirst  = _isFirstBookingEligible;
    final name     = _service?['name'] as String? ?? '';
    final itemType = CartService.typeOf(name);
    final qty      = _cart.quantityOf(widget.serviceId);
    final inCart   = qty > 0;
    final durPer   = CartService.durationFor(name);
    final totalDur = durPer * (qty > 0 ? qty : 1);
    final totalPr  = price * (qty > 0 ? qty : 1);

    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: _border)),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20, offset: const Offset(0, -4))]),
        child: Column(mainAxisSize: MainAxisSize.min, children: [

          // ── Cartable services: counter row ─────────────────────
          if (_isCartable) ...[
            Row(children: [
              // Left: price + duration info
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isFirst ? 'FIRST BOOKING' : 'TOTAL',
                    style: const TextStyle(color: _faint, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                const SizedBox(height: 2),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹$totalPr',
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                          color: isFirst ? _green : _ink)),
                  if (isFirst) ...[
                    const SizedBox(width: 6),
                    Padding(padding: const EdgeInsets.only(bottom: 2),
                      child: Text('₹${_originalPrice * (qty > 0 ? qty : 1)}',
                          style: const TextStyle(fontSize: 12, color: _faint,
                              decoration: TextDecoration.lineThrough))),
                  ],
                ]),
                const SizedBox(height: 2),
                Row(children: [
                  const Icon(Icons.timer_outlined, size: 12, color: _cyan),
                  const SizedBox(width: 4),
                  Text('$totalDur min total',
                      style: const TextStyle(color: _cyan, fontSize: 11,
                          fontWeight: FontWeight.w600)),
                  if (qty > 1) ...[
                    const SizedBox(width: 6),
                    Text(
                      itemType == CartItemType.hourly
                          ? '($qty × 60 min)'
                          : '($qty × $durPer min)',
                      style: const TextStyle(color: _faint, fontSize: 10)),
                  ],
                ]),
              ])),
              const SizedBox(width: 12),
              // Right: − qty + counter (same style as services grid)
              if (!inCart)
                // Not in cart — show Add to Cart button
                GestureDetector(
                  onTap: () {
                    _cart.increment(_buildCartItem());
                    setState(() {});
                  },
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    decoration: BoxDecoration(
                      color: _cyan,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                          color: _cyan.withValues(alpha: 0.4),
                          blurRadius: 12, offset: const Offset(0, 4))]),
                    child: const Row(children: [
                      Icon(Icons.add_shopping_cart_rounded,
                          color: Colors.white, size: 16),
                      SizedBox(width: 8),
                      Text('Add to Cart',
                          style: TextStyle(color: Colors.white,
                              fontSize: 13, fontWeight: FontWeight.w900)),
                    ])))
              else
                // In cart — show − qty + counter
                Container(
                  height: 44,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _cyan, width: 1.5)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    // Minus
                    GestureDetector(
                      onTap: () {
                        _cart.decrement(widget.serviceId);
                        setState(() {});
                      },
                      child: Container(
                        width: 44, height: 44,
                        alignment: Alignment.center,
                        child: const Icon(Icons.remove_rounded,
                            color: _cyan, size: 20))),
                    // Qty + duration
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                        Text('$qty', style: const TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w900,
                            color: _ink)),
                        Text('${durPer * qty} min',
                            style: const TextStyle(
                                fontSize: 9, color: _cyan,
                                fontWeight: FontWeight.w700)),
                      ])),
                    // Plus
                    GestureDetector(
                      onTap: qty < CartService.maxQtyFor(name)
                          ? () {
                              _cart.increment(_buildCartItem());
                              setState(() {});
                            }
                          : null,
                      child: Container(
                        width: 44, height: 44,
                        alignment: Alignment.center,
                        child: Icon(Icons.add_rounded,
                            color: qty < CartService.maxQtyFor(name)
                                ? _cyan : _faint,
                            size: 20))),
                  ])),
            ]),
            const SizedBox(height: 12),
            // Go to cart button
            if (inCart)
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  height: 46, width: double.infinity,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F172A),
                    borderRadius: BorderRadius.circular(14)),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.shopping_cart_rounded,
                        color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text('View Cart · ₹${_cart.totalPrice}',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white54, size: 14),
                  ]))),
            const SizedBox(height: 10),
          ],

          // ── Non-cartable: standard price + Schedule/Book Now ───
          if (!_isCartable)
            Row(children: [
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isFirst ? 'FIRST BOOKING' : 'TOTAL',
                    style: const TextStyle(color: _faint, fontSize: 9,
                        fontWeight: FontWeight.w700, letterSpacing: 1.2)),
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text('₹$price', style: TextStyle(fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: isFirst ? const Color(0xFF10B981) : _ink)),
                  if (isFirst) ...[
                    const SizedBox(width: 6),
                    Padding(padding: const EdgeInsets.only(bottom: 2),
                      child: Text('₹$_originalPrice', style: const TextStyle(
                          fontSize: 13, color: _faint,
                          decoration: TextDecoration.lineThrough))),
                  ],
                ]),
                if (_pricing['type'] == 'by_bhk')
                  Text(_selectedBhk,
                      style: const TextStyle(color: _cyan, fontSize: 11,
                          fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(width: 16),
              Expanded(child: Row(children: [
                Expanded(child: GestureDetector(
                  onTap: () => _navigate('schedule'),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: _cyan, width: 1.5)),
                    child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Icon(Icons.calendar_month_rounded, color: _cyan, size: 16),
                      SizedBox(width: 5),
                      Text('Schedule', style: TextStyle(color: _cyan,
                          fontSize: 13, fontWeight: FontWeight.w800)),
                    ])))),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: GestureDetector(
                  onTap: _checkingInstant ? null : () => _navigate('instant'),
                  child: Container(
                    height: 50,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.40),
                          blurRadius: 14, offset: const Offset(0, 5))]),
                    child: _checkingInstant
                        ? const Center(child: SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5)))
                        : const Row(mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                            Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                            SizedBox(width: 4),
                            Text('Book Now', style: TextStyle(color: Colors.white,
                                fontSize: 13, fontWeight: FontWeight.w900)),
                          ])))),
              ])),
            ]),

          // ── Cartable + not in cart: Schedule/Book Now still visible
          if (_isCartable && !inCart) ...[
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: GestureDetector(
                onTap: () => _navigate('schedule'),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _border)),
                  child: const Row(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.calendar_month_rounded, color: _cyan, size: 16),
                    SizedBox(width: 5),
                    Text('Schedule', style: TextStyle(color: _cyan,
                        fontSize: 13, fontWeight: FontWeight.w800)),
                  ])))),
              const SizedBox(width: 8),
              Expanded(flex: 2, child: GestureDetector(
                onTap: _checkingInstant ? null : () => _navigate('instant'),
                child: Container(
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: _cyan.withValues(alpha: 0.40),
                        blurRadius: 14, offset: const Offset(0, 5))]),
                  child: _checkingInstant
                      ? const Center(child: SizedBox(width: 20, height: 20,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5)))
                      : const Row(mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                          Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                          SizedBox(width: 4),
                          Text('Book Now', style: TextStyle(color: Colors.white,
                              fontSize: 13, fontWeight: FontWeight.w900)),
                        ])))),
            ]),
          ],
        ]),
      ),
    );
  }
}