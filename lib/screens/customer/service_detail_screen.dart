import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'booking_flow_screen.dart';

// ── Pricing config ────────────────────────────────────────────────────────────
class _ServicePricing {
  static const Map<String, Map<String, dynamic>> config = {
    'Bathroom Cleaning': {
      'type': 'per_unit', 'unit': 'Bathroom', 'unit_plural': 'Bathrooms',
      'price_per_unit': 99, 'duration_per_unit': 30, 'min': 1, 'max': 6,
    },
    'Fan Cleaning': {
      'type': 'per_unit', 'unit': 'Fan', 'unit_plural': 'Fans',
      'price_per_unit': 49, 'duration_per_unit': 15, 'min': 1, 'max': 10,
    },
    'Balcony Cleaning': {
      'type': 'per_unit', 'unit': 'Balcony', 'unit_plural': 'Balconies',
      'price_per_unit': 79, 'duration_per_unit': 20, 'min': 1, 'max': 4,
    },
    'Dusting & Wiping': {
      'type': 'by_bhk',
      'prices':    {'1 BHK': 299, '2 BHK': 449, '3 BHK': 599},
      'durations': {'1 BHK': 60,  '2 BHK': 90,  '3 BHK': 120},
    },
    'Sweeping & Mopping': {
      'type': 'by_bhk',
      'prices':    {'1 BHK': 249, '2 BHK': 399, '3 BHK': 549},
      'durations': {'1 BHK': 45,  '2 BHK': 75,  '3 BHK': 105},
    },
    'Full House Cleaning': {
      'type': 'by_bhk',
      'prices':    {'1 BHK': 599, '2 BHK': 899,  '3 BHK': 1199},
      'durations': {'1 BHK': 90,  '2 BHK': 150,  '3 BHK': 210},
    },
    'Kitchen Cleaning':            {'type': 'fixed', 'duration': 45},
    'Kitchen Cabinet Cleaning':    {'type': 'fixed', 'duration': 60},
    'Utensil Cleaning':            {'type': 'fixed', 'duration': 30},
    'Wardrobe Cleaning':           {'type': 'fixed', 'duration': 45},
    'Refrigerator Cleaning':       {'type': 'fixed', 'duration': 30},
    'Pre-Party Express Cleaning':  {'type': 'fixed', 'duration': 60},
    'After-Party Cleanup':         {'type': 'fixed', 'duration': 90},
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

  Map<String, dynamic>? _service;
  bool   _loading = true;
  bool   _liked   = false;
  String _tab     = 'about';

  late AnimationController _entranceCtrl;
  late Animation<double>   _entranceFade;
  late Animation<Offset>   _entranceSlide;

  // Pricing state
  int    _quantity    = 1;
  String _selectedBhk = '2 BHK';
  bool   _isFirstBooking = false;

  // Reviews
  List<Map<String, dynamic>> _reviews     = [];
  Map<String, dynamic>?      _reviewStats;
  bool             _reviewsLoading = true;
  RealtimeChannel? _reviewChannel;

  // ── Colors ─────────────────────────────────────────────────────
  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _cyanLt = Color(0xFFCFFAFE);
  static const _cyanXl = Color(0xFFECFEFF);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _bg     = Color(0xFFF8FAFC);

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
  };

  // ── Computed values ─────────────────────────────────────────────
  Map<String, dynamic> get _pricing {
    if (_service == null) return {'type': 'fixed', 'duration': 60};
    return _ServicePricing.get(_service!['name'] as String);
  }

  int get _originalPrice {
    final p = _pricing;
    switch (p['type'] as String) {
      case 'per_unit': return (p['price_per_unit'] as int) * _quantity;
      case 'by_bhk':  return (p['prices'] as Map)[_selectedBhk] as int;
      default:         return (_service?['base_price'] as num?)?.toInt() ?? 0;
    }
  }

  int get _computedPrice => _isFirstBooking ? 25 : _originalPrice;

  int get _computedDuration {
    final p = _pricing;
    switch (p['type'] as String) {
      case 'per_unit':
        final mins = (p['duration_per_unit'] as int) * _quantity;
        return ((mins / 60).ceil()) * 60;
      case 'by_bhk':
        final mins = (p['durations'] as Map)[_selectedBhk] as int;
        return ((mins / 60).ceil()) * 60;
      default:
        final raw = (p['duration'] as int?) ??
            (_service?['duration_minutes'] as num?)?.toInt() ?? 60;
        return ((raw / 60).ceil()) * 60;
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
    _load();
    _loadReviews();
    _subscribeRealtime();
    _checkFirstBooking();
  }

  @override
  void dispose() {
    _entranceCtrl.dispose();
    _reviewChannel?.unsubscribe();
    super.dispose();
  }

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
    final uid = _supabase.auth.currentUser?.id;
    if (uid == null) return;
    try {
      final rows = await _supabase.from('bookings').select('id')
          .eq('customer_id', uid)
          .inFilter('payment_status', ['paid'])
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
        _reviews        = (results[0] as List).cast<Map<String, dynamic>>();
        _reviewStats    = results[1] as Map<String, dynamic>?;
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

  void _navigate(String mode) {
    if (_service == null) return;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => BookingFlowScreen(
        mode:             mode,
        serviceId:        _service!['id'] as String,
        overridePrice:    _computedPrice,
        overrideDuration: _computedDuration,
        selectedBhk:      _pricing['type'] == 'by_bhk' ? _selectedBhk : null,
        quantity:         _pricing['type'] == 'per_unit' ? _quantity : null,
        isFirstBooking:   _isFirstBooking,
      ),
    ));
  }

  // ═══════════════════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _cyan)));
    }

    if (_service == null) {
      return Scaffold(
        backgroundColor: _bg,
        body: Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center, children: [
          const Text('🔍', style: TextStyle(fontSize: 48)),
          const SizedBox(height: 16),
          const Text('Service not found',
              style: TextStyle(fontWeight: FontWeight.w700,
                  fontSize: 16, color: _ink)),
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
                const SliverToBoxAdapter(child: SizedBox(height: 160)),
              ],
            ),
            _buildBottomBar(),
          ]),
        ),
      ),
    );
  }

  // ── HERO ──────────────────────────────────────────────────────────────────
  Widget _buildHero(Map<String, dynamic> svc, String name, String emoji) {
    final avg = (_reviewStats?['avg_rating'] as num?)?.toDouble() ?? 4.8;

    return SliverAppBar(
      expandedHeight: 310,
      pinned: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      automaticallyImplyLeading: false,
      flexibleSpace: FlexibleSpaceBar(
        collapseMode: CollapseMode.parallax,
        titlePadding: EdgeInsets.zero,
        title: const SizedBox.shrink(),
        background: Stack(fit: StackFit.expand, children: [

          // Background wash
          Container(color: const Color(0xFFECFEFF)),
          Positioned(top: -80, right: -80,
            child: Container(width: 280, height: 280,
              decoration: const BoxDecoration(
                  color: Color(0xFFCFFAFE), shape: BoxShape.circle))),
          Positioned(bottom: -40, left: -60,
            child: Container(width: 200, height: 200,
              decoration: const BoxDecoration(
                  color: Color(0xFFBAE6FD), shape: BoxShape.circle))),

          // Ghost emoji
          Positioned(right: 10, bottom: 70,
            child: Text(emoji, style: TextStyle(
                fontSize: 130,
                color: Colors.white.withValues(alpha: 0.18)))),

          // Main emoji in glowing circle
          Positioned(right: 24, top: 72,
            child: Container(
              width: 108, height: 108,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: _cyan.withValues(alpha: 0.22),
                      blurRadius: 30, spreadRadius: 4),
                  BoxShadow(color: _cyan.withValues(alpha: 0.08),
                      blurRadius: 60, spreadRadius: 12),
                ]),
              child: Center(child: Text(emoji,
                  style: const TextStyle(fontSize: 54))))),

          // Bottom white card
          Positioned(left: 0, right: 0, bottom: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(
                    top: Radius.circular(32))),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min, children: [
                // Category pill
                if ((svc['category'] as String?) != null) ...[
                  Container(
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 3),
                    decoration: BoxDecoration(
                      color: _cyanLt,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _cyan.withValues(alpha: 0.3))),
                    child: Text(
                      (svc['category'] as String).toUpperCase(),
                      style: const TextStyle(color: _cyanDk, fontSize: 9,
                          fontWeight: FontWeight.w800, letterSpacing: 1.4)),
                  ),
                ],

                // Service name
                Text(name, style: const TextStyle(fontSize: 22,
                    fontWeight: FontWeight.w900, color: _ink, height: 1.2)),
                const SizedBox(height: 10),

                // Info chips row
                Row(children: [
                  _chip('⭐ ${avg.toStringAsFixed(1)}',
                      const Color(0xFFFFFBEB), const Color(0xFFFDE68A),
                      const Color(0xFFB45309)),
                  const SizedBox(width: 8),
                  _chip('⏱ ~$_computedDuration min',
                      _cyanXl, _cyan.withValues(alpha: 0.25), _cyanDk),
                  const SizedBox(width: 8),
                  _chip('✓ Verified pros',
                      const Color(0xFFECFDF5),
                      const Color(0xFF6EE7B7),
                      const Color(0xFF065F46)),
                ]),
              ]),
            )),

          // Top action buttons
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                _iconBtn(Icons.arrow_back_ios_new_rounded,
                    () => Navigator.pop(context)),
                Row(children: [
                  _iconBtn(
                    _liked ? Icons.favorite_rounded
                           : Icons.favorite_border_rounded,
                    () {
                      setState(() => _liked = !_liked);
                      HapticFeedback.lightImpact();
                    },
                    iconColor: _liked ? Colors.red : _ink,
                  ),
                  const SizedBox(width: 8),
                  _iconBtn(Icons.ios_share_rounded, () {
                    HapticFeedback.lightImpact();
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Link copied!')));
                  }),
                ]),
              ]),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _chip(String label, Color bg, Color borderColor, Color textColor) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: borderColor)),
        child: Text(label,
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
                color: textColor)));

  Widget _iconBtn(IconData icon, VoidCallback onTap, {Color? iconColor}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40, height: 40,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            border: Border.all(color: _border),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.06),
                blurRadius: 8, offset: const Offset(0, 2))]),
          child: Icon(icon, color: iconColor ?? _ink, size: 18)),
      );

  // ── BODY ──────────────────────────────────────────────────────────────────
  Widget _buildBody(Map<String, dynamic> svc) {
    return Container(
      color: Colors.white,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // First booking banner
        if (_isFirstBooking) _buildFirstBookingBanner(),

        // Pricing selector
        _buildPricingSelector(),

        // Price display
        _buildPriceDisplay(),

        const SizedBox(height: 8),
        Divider(color: _border, height: 1, indent: 20, endIndent: 20),

        // Tabs
        _buildTabs(),

        // Tab content
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          transitionBuilder: (child, anim) =>
              FadeTransition(opacity: anim, child: child),
          child: Padding(
            key: ValueKey(_tab),
            padding: const EdgeInsets.all(20),
            child: _buildTabContent(svc),
          ),
        ),
      ]),
    );
  }

  // ── First booking banner ───────────────────────────────────────────────────
  Widget _buildFirstBookingBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6EE7B7))),
      child: Row(children: [
        Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: const Color(0xFF10B981),
            borderRadius: BorderRadius.circular(12)),
          child: const Center(child: Text('🎉',
              style: TextStyle(fontSize: 22)))),
        const SizedBox(width: 12),
        const Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('First booking — just ₹25!',
              style: TextStyle(color: Color(0xFF065F46),
                  fontWeight: FontWeight.w900, fontSize: 13)),
          SizedBox(height: 2),
          Text('No promo code needed. One time only.',
              style: TextStyle(color: Color(0xFF059669), fontSize: 11)),
        ])),
        const Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text('₹25', style: TextStyle(color: Color(0xFF059669),
              fontSize: 22, fontWeight: FontWeight.w900)),
          Text('only', style: TextStyle(color: Color(0xFF6EE7B7),
              fontSize: 10)),
        ]),
      ]),
    );
  }

  // ── Pricing selector ───────────────────────────────────────────────────────
  Widget _buildPricingSelector() {
    final p = _pricing;
    if (p['type'] == 'fixed') return const SizedBox(height: 16);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: p['type'] == 'per_unit'
          ? _buildUnitSelector(p)
          : _buildBhkSelector(p),
    );
  }

  Widget _buildUnitSelector(Map<String, dynamic> p) {
    final unit       = p['unit'] as String;
    final unitPlural = p['unit_plural'] as String;
    final min        = p['min'] as int;
    final max        = p['max'] as int;
    final ppu        = p['price_per_unit'] as int;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _cyanXl,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _cyan.withValues(alpha: 0.2))),
      child: Column(children: [
        Row(children: [
          const Icon(Icons.add_circle_outline_rounded,
              color: _cyanDk, size: 18),
          const SizedBox(width: 8),
          Text('How many ${unitPlural.toLowerCase()}?',
              style: const TextStyle(color: _ink,
                  fontWeight: FontWeight.w800, fontSize: 14)),
          const Spacer(),
          Text('₹$ppu each',
              style: const TextStyle(color: _cyanDk,
                  fontSize: 12, fontWeight: FontWeight.w600)),
        ]),
        const SizedBox(height: 16),
        Row(children: [
          _counterBtn(Icons.remove_rounded, _quantity > min, () {
            setState(() => _quantity--);
            HapticFeedback.selectionClick();
          }),
          Expanded(child: Column(children: [
            Text('$_quantity', style: const TextStyle(
                fontSize: 34, fontWeight: FontWeight.w900, color: _ink)),
            Text(_quantity == 1 ? unit : unitPlural,
                style: const TextStyle(color: _muted, fontSize: 12)),
          ])),
          _counterBtn(Icons.add_rounded, _quantity < max, () {
            setState(() => _quantity++);
            HapticFeedback.selectionClick();
          }),
        ]),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _border)),
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
            Text('$_quantity × ₹$ppu',
                style: const TextStyle(color: _muted, fontSize: 13)),
            Text('= ₹$_originalPrice',
                style: const TextStyle(fontWeight: FontWeight.w900,
                    fontSize: 15, color: _ink)),
          ]),
        ),
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
          color: enabled ? _cyan : _border,
          shape: BoxShape.circle,
          boxShadow: enabled
              ? [BoxShadow(color: _cyan.withValues(alpha: 0.30),
                  blurRadius: 12, offset: const Offset(0, 4))]
              : [],
        ),
        child: Icon(icon,
            color: enabled ? Colors.white : _faint, size: 24)),
    );
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
        ]),
      ),
      Row(children: bhks.map((bhk) {
        final active = _selectedBhk == bhk;
        final price  = prices[bhk] as int;
        final dur    = durations[bhk] as int;
        return Expanded(child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedBhk = bhk);
              HapticFeedback.selectionClick();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(vertical: 14),
              decoration: BoxDecoration(
                color: active ? _cyan : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                    color: active ? _cyan : _border,
                    width: active ? 0 : 1.5),
                boxShadow: active
                    ? [BoxShadow(color: _cyan.withValues(alpha: 0.30),
                        blurRadius: 14, offset: const Offset(0, 6))]
                    : [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6, offset: const Offset(0, 2))]),
              child: Column(children: [
                Text(bhk, style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 13,
                    color: active ? Colors.white : _ink)),
                const SizedBox(height: 6),
                Text('₹$price', style: TextStyle(
                    fontWeight: FontWeight.w900, fontSize: 18,
                    color: active ? Colors.white : _cyan)),
                const SizedBox(height: 3),
                Text('~${dur}m', style: TextStyle(
                    fontSize: 10,
                    color: active
                        ? Colors.white.withValues(alpha: 0.75)
                        : _faint)),
              ]),
            ),
          ),
        ));
      }).toList()),
    ]);
  }

  // ── Price display ──────────────────────────────────────────────────────────
  Widget _buildPriceDisplay() {
    final display  = _computedPrice;
    final original = _originalPrice;
    final isFirst  = _isFirstBooking;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(isFirst ? 'FIRST BOOKING PRICE' : 'TOTAL PRICE',
              style: const TextStyle(color: _faint, fontSize: 9,
                  fontWeight: FontWeight.w700, letterSpacing: 1.2)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('₹$display',
                style: TextStyle(fontSize: 38, fontWeight: FontWeight.w900,
                    color: isFirst ? const Color(0xFF10B981) : _ink,
                    height: 1.0)),
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                isFirst ? '₹$original' : '₹${(display * 1.4).round()}',
                style: const TextStyle(fontSize: 16, color: _faint,
                    decoration: TextDecoration.lineThrough))),
          ]),
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(20)),
            child: Text(
              isFirst
                  ? '🎉 ₹${original - 25} off for first booking'
                  : 'Save ₹${(display * 0.4).round()}',
              style: const TextStyle(color: Color(0xFF065F46),
                  fontSize: 11, fontWeight: FontWeight.w700)),
          ),
        ])),
        const SizedBox(width: 16),
        // Rating summary
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(children: [
            const Text('⭐', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 4),
            Text(
              ((_reviewStats?['avg_rating'] as num?)?.toDouble() ?? 4.8)
                  .toStringAsFixed(1),
              style: const TextStyle(fontSize: 20,
                  fontWeight: FontWeight.w900, color: _ink)),
          ]),
          Text(
            _reviewStats != null
                ? '${(_reviewStats!['total_reviews'] as num?)?.toInt() ?? 0} reviews'
                : 'No reviews',
            style: const TextStyle(color: _faint, fontSize: 11)),
          const SizedBox(height: 4),
          const Text('2,400+ bookings',
              style: TextStyle(color: _muted, fontSize: 11,
                  fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }

  // ── Tabs ──────────────────────────────────────────────────────────────────
  Widget _buildTabs() {
    const tabs = ['about', 'includes', 'reviews'];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(children: tabs.map((t) {
        final active = _tab == t;
        return GestureDetector(
          onTap: () {
            setState(() => _tab = t);
            HapticFeedback.selectionClick();
          },
          child: Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Column(children: [
              const SizedBox(height: 14),
              Text(t[0].toUpperCase() + t.substring(1),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: active ? FontWeight.w800 : FontWeight.w500,
                    color: active ? _ink : _faint)),
              const SizedBox(height: 10),
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 2.5,
                width: active ? 36 : 0,
                decoration: BoxDecoration(
                  color: _cyan,
                  borderRadius: BorderRadius.circular(2))),
            ]),
          ),
        );
      }).toList()),
    );
  }

  Widget _buildTabContent(Map<String, dynamic> svc) {
    switch (_tab) {
      case 'about':    return _buildAbout(svc);
      case 'includes': return _buildIncludes(svc);
      default:         return _buildReviews();
    }
  }

  // ── About tab ─────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _expectItems() {
    return [
      {'text': '✓ Verified & background-checked professional',
        'color': const Color(0xFF0891B2)},
      {'text': '✓ All equipment provided — no extra cost',
        'color': const Color(0xFF059669)},
      {'text': '✓ Eco-friendly, safe cleaning products',
        'color': const Color(0xFF7C3AED)},
      {'text': '✓ ~$_computedDuration min estimated duration',
        'color': const Color(0xFFD97706)},
    ];
  }

  Widget _buildAbout(Map<String, dynamic> svc) {
    final desc = svc['description'] as String? ??
        'Professional cleaning by verified experts. We bring all equipment '
        'and eco-friendly products — leaving your space spotless and fresh.';

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(desc, style: const TextStyle(color: _muted,
          fontSize: 14, height: 1.75)),
      const SizedBox(height: 24),

      const Text('What to expect', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 14),

      ..._expectItems().map((item) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Row(children: [
          Container(width: 6, height: 6,
            decoration: BoxDecoration(
                color: item['color'] as Color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(child: Text(item['text'] as String,
              style: const TextStyle(color: _muted, fontSize: 13,
                  fontWeight: FontWeight.w500))),
        ]),
      )),

      const SizedBox(height: 24),
      const Text('Why Cleenzo', style: TextStyle(
          fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
      const SizedBox(height: 14),

      GridView.count(
        shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
        crossAxisCount: 2, crossAxisSpacing: 10, mainAxisSpacing: 10,
        childAspectRatio: 2.6,
        children: [
          _whyCard('🛡️', 'Insured',    'Damage covered',
              const Color(0xFFF5F3FF), const Color(0xFF6D28D9)),
          _whyCard('⭐', 'Top Rated',  '4.8 / 5 stars',
              const Color(0xFFFFFBEB), const Color(0xFFB45309)),
          _whyCard('🔄', 'Re-Clean',   'If not satisfied',
              const Color(0xFFECFEFF), const Color(0xFF0891B2)),
          _whyCard('💳', 'Flexible',   'UPI · Card · Cash',
              const Color(0xFFECFDF5), const Color(0xFF065F46)),
        ],
      ),
    ]);
  }

  Widget _whyCard(String emoji, String title, String sub,
      Color bg, Color textColor) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: textColor.withValues(alpha: 0.15))),
      child: Row(children: [
        Text(emoji, style: const TextStyle(fontSize: 20)),
        const SizedBox(width: 10),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(title, style: TextStyle(color: textColor,
              fontSize: 11, fontWeight: FontWeight.w800)),
          Text(sub, style: const TextStyle(color: _muted, fontSize: 10)),
        ])),
      ]),
    );
  }

  // ── Includes tab ──────────────────────────────────────────────────────────
  Widget _buildIncludes(Map<String, dynamic> svc) {
    final inc = (svc['includes'] as List?)?.cast<String>() ?? [];
    final exc = (svc['excludes'] as List?)?.cast<String>() ?? [];

    if (inc.isEmpty && exc.isEmpty) {
      return const Center(child: Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(children: [
          Text('📋', style: TextStyle(fontSize: 40)),
          SizedBox(height: 12),
          Text('No details yet',
              style: TextStyle(color: _faint, fontSize: 13)),
        ])));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (inc.isNotEmpty) ...[
        const Text('Included', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 12),
        ...inc.map((item) => _includeRow(item, true)),
        const SizedBox(height: 20),
      ],
      if (exc.isNotEmpty) ...[
        const Text('Not included', style: TextStyle(
            fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
        const SizedBox(height: 12),
        ...exc.map((item) => _includeRow(item, false)),
      ],
    ]);
  }

  Widget _includeRow(String text, bool included) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(children: [
        Container(
          width: 24, height: 24,
          decoration: BoxDecoration(
            color: included
                ? const Color(0xFFECFDF5) : const Color(0xFFFEF2F2),
            shape: BoxShape.circle,
            border: Border.all(color: included
                ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5))),
          child: Icon(
            included ? Icons.check_rounded : Icons.close_rounded,
            size: 13,
            color: included
                ? const Color(0xFF059669) : const Color(0xFFDC2626))),
        const SizedBox(width: 12),
        Expanded(child: Text(text,
            style: TextStyle(
              color: included ? _muted : _faint,
              fontSize: 13, fontWeight: FontWeight.w500))),
      ]),
    );
  }

  // ── Reviews tab ───────────────────────────────────────────────────────────
  Widget _buildReviews() {
    if (_reviewsLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(color: _cyan)));
    }

    final avgRating  = (_reviewStats?['avg_rating'] as num?)?.toDouble() ?? 0.0;
    final totalCount = (_reviewStats?['total_reviews'] as num?)?.toInt() ?? 0;

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Rating summary
      Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Column(children: [
          Text(avgRating > 0 ? avgRating.toStringAsFixed(1) : '–',
              style: const TextStyle(fontSize: 52,
                  fontWeight: FontWeight.w900, color: _ink, height: 1.0)),
          Row(children: List.generate(5, (i) => Icon(
            i < avgRating.floor()
                ? Icons.star_rounded : Icons.star_border_rounded,
            color: const Color(0xFFF59E0B), size: 14))),
          const SizedBox(height: 4),
          Text('$totalCount reviews',
              style: const TextStyle(color: _faint,
                  fontSize: 11, fontWeight: FontWeight.w500)),
        ]),
        const SizedBox(width: 24),
        Expanded(child: Column(
          children: [5, 4, 3, 2, 1].map((star) {
            final cnt = (_reviewStats?['${_starKey(star)}_star'] as num?)
                ?.toInt() ?? 0;
            final pct = totalCount > 0 ? cnt / totalCount : 0.0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(children: [
                SizedBox(width: 12, child: Text('$star',
                    style: const TextStyle(color: _faint,
                        fontSize: 11, fontWeight: FontWeight.w600))),
                const SizedBox(width: 8),
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: pct,
                    backgroundColor: _border,
                    valueColor: const AlwaysStoppedAnimation(
                        Color(0xFFF59E0B)),
                    minHeight: 6))),
                const SizedBox(width: 8),
                SizedBox(width: 20, child: Text('$cnt',
                    style: const TextStyle(
                        color: _faint, fontSize: 11))),
              ]),
            );
          }).toList(),
        )),
      ]),

      const SizedBox(height: 20),
      const Divider(color: _border, height: 1),
      const SizedBox(height: 16),

      if (_reviews.isEmpty)
        const Center(child: Padding(
          padding: EdgeInsets.symmetric(vertical: 30),
          child: Column(children: [
            Text('💬', style: TextStyle(fontSize: 40)),
            SizedBox(height: 12),
            Text('No reviews yet',
                style: TextStyle(color: _faint, fontSize: 13)),
          ])))
      else
        Column(children: _reviews.map((r) => _buildReviewCard(r)).toList()),
    ]);
  }

  String _starKey(int star) =>
      ['zero', 'one', 'two', 'three', 'four', 'five'][star];

  Widget _buildReviewCard(Map<String, dynamic> r) {
    final uid      = _supabase.auth.currentUser?.id;
    final isOwn    = r['user_id'] == uid;
    final fullName = (r['full_name'] as String?) ?? 'User';
    final initials = fullName.trim().split(' ')
        .where((w) => w.isNotEmpty).take(2)
        .map((w) => w[0].toUpperCase()).join();
    final stars    = (r['stars'] as num?)?.toInt() ?? 0;
    final text     = (r['text'] as String?) ?? '';
    final createdAt = DateTime.tryParse(r['created_at'] as String? ?? '');
    const months   = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    final dateStr  = createdAt != null
        ? '${createdAt.day} ${months[createdAt.month - 1]}' : '';
    const avatarColors = [_cyan, Color(0xFF7C3AED), Color(0xFFDB2777),
        Color(0xFF059669), Color(0xFFD97706)];
    final avatarColor  = avatarColors[
        fullName.isEmpty ? 0 : fullName.codeUnitAt(0) % avatarColors.length];

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
                color: avatarColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(
                    color: avatarColor.withValues(alpha: 0.3))),
            child: Center(child: Text(initials,
                style: TextStyle(color: avatarColor,
                    fontWeight: FontWeight.w900, fontSize: 12)))),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(isOwn ? 'You' : fullName,
                  style: const TextStyle(fontWeight: FontWeight.w700,
                      fontSize: 13, color: _ink)),
              if (isOwn) ...[
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: _cyanLt,
                    borderRadius: BorderRadius.circular(6)),
                  child: const Text('You',
                      style: TextStyle(color: _cyanDk, fontSize: 9,
                          fontWeight: FontWeight.w800))),
              ],
            ]),
            Text(dateStr,
                style: const TextStyle(color: _faint, fontSize: 11)),
          ])),
          Row(children: List.generate(5, (i) => Icon(
            i < stars ? Icons.star_rounded : Icons.star_border_rounded,
            color: const Color(0xFFF59E0B), size: 13))),
        ]),
        if (text.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(
              color: _muted, fontSize: 13, height: 1.6)),
        ],
        const SizedBox(height: 12),
        const Divider(color: _border, height: 1),
      ]),
    );
  }

  // ── Bottom bar ────────────────────────────────────────────────────────────
  Widget _buildBottomBar() {
    final bottom  = MediaQuery.of(context).padding.bottom;
    final price   = _computedPrice;
    final isFirst = _isFirstBooking;

    return Positioned(
      left: 0, right: 0, bottom: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
        decoration: BoxDecoration(
          color: Colors.white,
          border: const Border(top: BorderSide(color: _border)),
          boxShadow: [BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 20, offset: const Offset(0, -4))]),
        child: Row(children: [
          // Price info
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(isFirst ? 'FIRST BOOKING' : 'TOTAL',
                style: const TextStyle(color: _faint, fontSize: 9,
                    fontWeight: FontWeight.w700, letterSpacing: 1.2)),
            Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹$price',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900,
                      color: isFirst ? const Color(0xFF10B981) : _ink)),
              if (isFirst) ...[
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text('₹${_originalPrice}',
                      style: const TextStyle(fontSize: 13, color: _faint,
                          decoration: TextDecoration.lineThrough))),
              ],
            ]),
            if (_pricing['type'] != 'fixed')
              Text(
                _pricing['type'] == 'per_unit'
                    ? '$_quantity × ${_pricing['unit']}'
                    : _selectedBhk,
                style: const TextStyle(color: _cyan, fontSize: 11,
                    fontWeight: FontWeight.w600)),
          ]),
          const SizedBox(width: 16),

          // Buttons
          Expanded(child: Row(children: [
            // Schedule
            Expanded(child: GestureDetector(
              onTap: () => _navigate('schedule'),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _cyan, width: 1.5)),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.calendar_month_rounded, color: _cyan, size: 16),
                  SizedBox(width: 5),
                  Text('Schedule', style: TextStyle(color: _cyan,
                      fontSize: 13, fontWeight: FontWeight.w800)),
                ]),
              ),
            )),
            const SizedBox(width: 8),
            // Instant
            Expanded(flex: 2, child: GestureDetector(
              onTap: () => _navigate('instant'),
              child: Container(
                height: 50,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                      colors: [_cyan, _cyanDk]),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(
                      color: _cyan.withValues(alpha: 0.40),
                      blurRadius: 14, offset: const Offset(0, 5))]),
                child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  Icon(Icons.bolt_rounded, color: Colors.white, size: 18),
                  SizedBox(width: 4),
                  Text('Book Now', style: TextStyle(color: Colors.white,
                      fontSize: 13, fontWeight: FontWeight.w900)),
                ]),
              ),
            )),
          ])),
        ]),
      ),
    );
  }
}