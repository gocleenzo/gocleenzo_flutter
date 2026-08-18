import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/cart_service.dart';
import 'service_detail_screen.dart';
import 'booking_flow_screen.dart';
import 'recurring_booking_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with TickerProviderStateMixin {
  final _supabase   = Supabase.instance.client;
  final _scrollCtrl = ScrollController();
  final _cart       = CartService.instance;

  late final PageController _bannerCtrl;
  Timer? _bannerAutoTimer;
  bool _userInteractingWithBanner = false;
  int _bannerIndex = 0;

  late final AnimationController _intro;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;
  late final AnimationController _ambientCtrl;

  static const _cyan    = Color(0xFF00B1FC);
  static const _cyanDk  = Color(0xFF00B1FC);
  static const _cyanDp  = Color(0xFF00B1FC);
  static const _cyanBg  = Color(0xFF00B1FC);
  static const _cyanBg2 = Color(0xFF00B1FC);
  static const _ink     = Color(0xFF0F172A);
  static const _muted   = Color(0xFF64748B);
  static const _faint   = Color(0xFF94A3B8);
  static const _border  = Color(0xFFE8EDF2);
  static const _bg      = Color(0xFFF8FAFC);
  static const _amber   = Color(0xFFF59E0B);
  static const _greenDk = Color(0xFF059669);

  static const _bannerImages = [
    'assets/banners/offer1.png',
    'assets/banners/offer2.png',
    'assets/banners/offer3.png',
  ];

  static const List<String> _serviceOrder = [
    'Hourly Cleaning',
    'Bathroom Cleaning',
    'Utensil Cleaning',
    'Kitchen Cleaning',
    'Sweeping & Mopping',
    'Dusting & Wiping',
    'Fan Cleaning',
    'Refrigerator Cleaning',
    'Balcony Cleaning',
    'Wardrobe Cleaning',
    'Kitchen Cabinet Cleaning',
    'Full House Cleaning',
  ];

  List<Map<String, dynamic>> _applyCustomOrder(List<Map<String, dynamic>> list) {
    final ordered = [...list];
    ordered.sort((a, b) {
      final an = a['name'] as String? ?? '';
      final bn = b['name'] as String? ?? '';
      final ai = _serviceOrder.indexOf(an);
      final bi = _serviceOrder.indexOf(bn);
      final aIdx = ai == -1 ? _serviceOrder.length : ai;
      final bIdx = bi == -1 ? _serviceOrder.length : bi;
      return aIdx.compareTo(bIdx);
    });
    return ordered;
  }

  static const Set<String> _firstBookingEligible = {
    'Bathroom Cleaning',
    'Balcony Cleaning',
    'Fan Cleaning',
    'Utensil Cleaning',
    'Kitchen Cleaning',
  };

  bool _isFirstBooking = false;

  // Grid card thumbnails — servicename1.png
  static const Map<String, String> _assetMap = {
    '6f150323-d018-44c0-bfe2-2037efa1f5c0': 'assets/services/bathroom-cleaning1.png',
    '6201b258-ed2c-4c83-b8e7-bd413cc5b67b': 'assets/services/wardrobe1.png',
    '6678a63d-059c-4ca5-ad11-3781f8449bb0': 'assets/services/full-home-cleaning1.png',
    'b7e6db9d-455d-46d5-ba4d-8e993fe1255d': 'assets/services/fan-cleaning1.png',
    '42719385-f88c-41ab-9e59-6ac4856f6112': 'assets/services/dusting-wiping1.png',
    '2b3bd63d-c1d5-40cf-a818-33501e9e61b4': 'assets/services/sweeping-mopping1.png',
    'ab1004e9-de4e-4ab6-9d34-30d7b23913a3': 'assets/services/fridge-cleaning1.png',
    '423a1354-d995-49df-ba67-effcb43befbf': 'assets/services/kitchen-cleaning1.png',
    '5af62745-c480-4579-a81a-a6a267cef2c3': 'assets/services/Utensils-cleaning1.png',
    '581ee014-e42b-43bf-9818-692b08a0ac53': 'assets/services/cabinet1.png',
    'ae4eac44-3444-4d45-b4a3-6387c043d5cf': 'assets/services/balcony-cleaning1.png',
    'e89d50c0-493a-44d6-a49e-7ab5737a464d': 'assets/services/hourly1.png',
  };

  static const Map<String, String> _emojis = {
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
  };

  List<Map<String, dynamic>> _services   = [];
  List<String>               _categories = ['All'];
  final String _activeTab    = 'All';
  bool   _loading      = true;
  String _userName     = 'there';

  String _locationLabel   = '';
  String _locationArea    = '';
  String _locationCity    = '';
  String _locationAddress = '';
  bool   _locationLoading = true;

  @override
  void initState() {
    super.initState();
    _bannerCtrl = PageController();
    _intro = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 650));
    _fade  = CurvedAnimation(parent: _intro, curve: Curves.easeOut);
    _slide = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(parent: _intro, curve: Curves.easeOutCubic));
    _ambientCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 2600))
      ..repeat(reverse: true);
    _cart.addListener(_onCartChanged);
    _load();
    _startBannerAutoSlide();
  }

  @override
  void dispose() {
    _bannerAutoTimer?.cancel();
    _bannerCtrl.dispose();
    _intro.dispose();
    _ambientCtrl.dispose();
    _scrollCtrl.dispose();
    _cart.removeListener(_onCartChanged);
    super.dispose();
  }

  void _onCartChanged() {
    if (mounted) setState(() {});
  }

  double _scale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    return (w / 375.0).clamp(0.92, 1.15);
  }

  Future<void> _load() async {
    final userId = await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (userId == null) { if (mounted) context.go('/login'); return; }
    try {
      final results = await Future.wait([
        _supabase.from('users').select('full_name')
            .eq('id', userId).maybeSingle(),
        _supabase.from('services').select('*')
            .eq('is_active', true).order('category'),
        _supabase.from('addresses')
            .select('label,area,city,flat_no,building,full_address,is_default')
            .eq('user_id', userId).eq('is_deleted', false)
            .order('is_default', ascending: false).limit(1).maybeSingle(),
        _supabase.from('bookings').select('id')
            .eq('customer_id', userId)
            .inFilter('status', ['completed', 'accepted', 'in_progress', 'pending'])
            .limit(1),
      ]);
      if (!mounted) return;
      final profile      = results[0] as Map<String, dynamic>?;
      final svcs         = results[1] as List<dynamic>;
      final addr         = results[2] as Map<String, dynamic>?;
      final bookingsRows = results[3] as List<dynamic>;
      setState(() {
        if (profile != null) {
          _userName = (profile['full_name'] as String?)
              ?.split(' ').first ?? 'there';
        }
        _services = _applyCustomOrder(svcs.cast<Map<String, dynamic>>());
        final cats = _services
            .map((s) => s['category'] as String? ?? '')
            .where((c) => c.isNotEmpty).toSet().toList()..sort();
        _categories = ['All', ...cats];
        if (addr != null) {
          _locationLabel = (addr['label'] as String?)?.trim() ?? '';
          _locationArea  = addr['area'] as String? ?? '';
          _locationCity  = addr['city'] as String? ?? '';
          final parts = [
            if ((addr['flat_no'] as String?)?.isNotEmpty == true) addr['flat_no'],
            if ((addr['building'] as String?)?.isNotEmpty == true) addr['building'],
            if ((addr['full_address'] as String?)?.isNotEmpty == true)
              addr['full_address']
            else ...[_locationArea, _locationCity],
          ];
          _locationAddress = parts
              .where((e) => e != null && e.toString().isNotEmpty)
              .join(', ');
        }
        _isFirstBooking  = bookingsRows.isEmpty;
        _cart.setFirstBooking(bookingsRows.isEmpty);
        _locationLoading = false;
        _loading         = false;
      });
      _intro.forward();
    } catch (e) {
      debugPrint('Services load error: $e');
      if (mounted) setState(() { _loading = false; _locationLoading = false; });
    }
  }

  void _startBannerAutoSlide() {
    _bannerAutoTimer?.cancel();
    _bannerAutoTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (!mounted || _userInteractingWithBanner) return;
      if (!_bannerCtrl.hasClients) return;
      if (_bannerImages.length <= 1) return;
      final next = (_bannerIndex + 1) % _bannerImages.length;
      _bannerCtrl.animateToPage(next,
          duration: const Duration(milliseconds: 500),
          curve: Curves.easeOutCubic);
    });
  }

  List<Map<String, dynamic>> get _filtered => _services
      .where((s) => _activeTab == 'All' || s['category'] == _activeTab)
      .toList();

  IconData _iconFor(String text) {
    final s = text.toLowerCase();
    if (s.contains('bath'))   return Icons.bathtub_outlined;
    if (s.contains('kitchen')) return Icons.countertops_outlined;
    if (s.contains('fridge') || s.contains('appliance')) return Icons.kitchen_outlined;
    if (s.contains('party') || s.contains('event')) return Icons.celebration_outlined;
    if (s.contains('home') || s.contains('full')) return Icons.home_outlined;
    if (s.contains('all')) return Icons.apps_outlined;
    return Icons.cleaning_services_outlined;
  }

  String? _assetFor(Map<String, dynamic> svc) {
    final id = svc['id'] as String?;
    if (id == null) return null;
    return _assetMap[id];
  }

  Widget _anim(Widget child) => FadeTransition(
      opacity: _fade,
      child: SlideTransition(position: _slide, child: child));

  void _open(Map<String, dynamic> svc) {
    HapticFeedback.lightImpact();
    Navigator.push(context, MaterialPageRoute(
        builder: (_) => ServiceDetailScreen(serviceId: svc['id'] as String)));
  }

  // Recurring packages are only offered for Hourly Cleaning — this finds
  // that service from whatever's already loaded and jumps straight into
  // RecurringBookingScreen, used by both the small card chip and the
  // horizontal "Recurring Booking" banner above the grid.
  void _openRecurring() {
    HapticFeedback.selectionClick();
    final hourly = _services.firstWhere(
      (s) => s['name'] == 'Hourly Cleaning',
      orElse: () => {},
    );
    if (hourly.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Weekly packages are temporarily unavailable.'),
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final basePrice = (hourly['base_price'] as num?)?.toInt() ?? 0;
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => RecurringBookingScreen(
        serviceId:     hourly['id'] as String,
        serviceName:   hourly['name'] as String,
        pricePerVisit: basePrice,
        durationMins:  60,
      ),
    ));
  }

  // ── Quick add to cart from grid card ─────────────────────────
 CartItem _templateFor(Map<String, dynamic> svc) {
    final name      = svc['name'] as String? ?? '';
    final basePrice = (svc['base_price'] as num?)?.toInt()
        ?? CartService.defaultPriceFor(svc);
    final t = CartService.typeOf(name);
    // For 'fixed' services, CartService.durationFor(name) falls back to a
    // hardcoded 60 min for anything not in its own small _tieredServices
    // list — Kitchen Cabinet Cleaning (180 min) and Wardrobe Cleaning
    // (150 min) both hit that fallback and silently reserved only 60
    // min of worker time regardless of what duration_minutes actually
    // said in the database. For fixed services, read the REAL duration
    // straight from the service record instead of trusting that lookup.
    final durationMins = t == CartItemType.fixed
        ? ((svc['duration_minutes'] as num?)?.toInt() ?? CartService.durationFor(name))
        : CartService.durationFor(name);
    return CartItem(
      serviceId:       svc['id'] as String,
      serviceName:     name,
      emoji:           _emojis[name],
      type:            t,
      // Tiers built from database price columns — no hardcoded prices
      tiers:           t == CartItemType.tiered
          ? CartService.buildTiers(svc, isFirstBooking: _isFirstBooking)
          : [],
      pricePerUnit:    basePrice,
      durationPerUnit: durationMins,
      maxQty:          CartService.maxQtyFor(name),
    );
  }

  void _increment(Map<String, dynamic> svc) {
    final name = svc['name'] as String? ?? '';
    if (!CartService.isCartable(name)) return;
    HapticFeedback.selectionClick();
    final blocked = _cart.increment(_templateFor(svc));
    if (blocked != null && blocked != -1) {
      // Duration cap hit — show snackbar
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
          blocked == 240
              ? 'Maximum 4 hours reached for hourly booking'
              : 'Cart limit reached ($blocked min). Checkout to book more.',
        ),
        backgroundColor: const Color(0xFF0891B2),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12)),
      ));
    }
    setState(() {});
  }

  void _decrement(Map<String, dynamic> svc) {
    HapticFeedback.selectionClick();
    _cart.decrement(svc['id'] as String);
    setState(() {});
  }

  void _openCart() {
    if (_cart.isEmpty) return;
    HapticFeedback.selectionClick();
    // Navigate to booking flow with cart items
    Navigator.push(context, MaterialPageRoute(
      builder: (_) => _CartSheet(cart: _cart, isFirstBooking: _isFirstBooking),
    ));
  }

  void _openNotifications() {
    HapticFeedback.selectionClick();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _NotificationsSheet(supabase: _supabase),
    );
  }

  void _openLocationPicker() {
    HapticFeedback.selectionClick();
    context.push('/saved-addresses');
  }

  bool get isAllTab => _activeTab == 'All';

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(
            color: Colors.black, strokeWidth: 2.5)));
    }

    final grid = isAllTab ? _services : _filtered;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _anim(_buildHeroBanner(topPad))),
            if (_services.isEmpty)
              SliverToBoxAdapter(child: _buildEmpty())
            else ...[
              if (grid.isNotEmpty) ...[
                SliverToBoxAdapter(child: _anim(_buildRecurringBanner())),
                _sliverHeader(isAllTab ? 'All house help services' : _activeTab),
                _buildGrid(grid),
              ] else
                SliverToBoxAdapter(child: _buildEmpty()),
            ],
            SliverToBoxAdapter(child: SizedBox(height: botPad + 24)),
          ],
        ),
        Positioned(
          top: 0, left: 0, right: 0,
          child: _TopHeaderBar(
            scrollController: _scrollCtrl,
            topPad: topPad,
            scale: _scale(context),
            fade: _fade,
            ambientCtrl: _ambientCtrl,
            primaryLabel: _locationLabel.isNotEmpty
                ? _locationLabel
                : (_locationArea.isNotEmpty ? _locationArea : 'Set location'),
            secondaryLine: _locationLoading
                ? 'Locating…'
                : ((_locationLabel.isNotEmpty || _locationArea.isNotEmpty)
                    ? _locationAddress
                    : 'Add your address to get started'),
            userInitial: _userName.isNotEmpty ? _userName[0].toUpperCase() : 'A',
            cartCount: _cart.totalQuantity,
            onLocationTap: _openLocationPicker,
            onNotificationsTap: _openNotifications,
            onProfileTap: () => context.go('/account'),
            onCartTap: _openCart,
          ),
        ),
        // Sticky cart bottom bar
        if (_cart.isNotEmpty)
          Positioned(
            left: 16, right: 16, bottom: botPad + 16,
            child: _CartBottomBar(cart: _cart, onCheckout: _openCart),
          ),
      ]),
    );
  }

  Widget _buildHeroBanner(double topPad) {
    const visibleBannerHeight = 320.0;
    final totalHeight = topPad + visibleBannerHeight;
    return Column(children: [
      SizedBox(
        height: totalHeight,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notif) {
            if (notif is ScrollStartNotification && notif.dragDetails != null) {
              _userInteractingWithBanner = true;
            } else if (notif is ScrollEndNotification) {
              _userInteractingWithBanner = false;
            }
            return false;
          },
          child: PageView.builder(
            controller: _bannerCtrl,
            onPageChanged: (i) => setState(() => _bannerIndex = i),
            itemCount: _bannerImages.length,
            itemBuilder: (_, i) => _heroBannerCard(_bannerImages[i]),
          ),
        ),
      ),
      const SizedBox(height: 12),
      Row(mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_bannerImages.length, (i) {
        final active = i == _bannerIndex;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          margin: const EdgeInsets.symmetric(horizontal: 3),
          width: active ? 18 : 7, height: 7,
          decoration: BoxDecoration(
            color: active ? _cyan : _border,
            borderRadius: BorderRadius.circular(4)));
      })),
      const SizedBox(height: 8),
    ]);
  }

  // Small horizontal banner that jumps straight into the weekly recurring
  // flow (Hourly Cleaning only). Sits right above "All house help
  // services" — a second, more visible entry point alongside the small
  // "Weekly" chip on the Hourly Cleaning card itself.
  Widget _buildRecurringBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
      child: GestureDetector(
        onTap: _openRecurring,
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.centerLeft, end: Alignment.centerRight,
              colors: [Color(0xFF0F172A), Color(0xFF0E7490)]),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [BoxShadow(
                color: const Color(0xFF0E7490).withValues(alpha: 0.30),
                blurRadius: 16, offset: const Offset(0, 6))]),
          child: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(11)),
              child: const Icon(Icons.repeat_rounded, color: Colors.white, size: 19)),
            const SizedBox(width: 12),
            const Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min, children: [
              Text('Recurring Booking',
                  style: TextStyle(color: Colors.white,
                      fontSize: 14.5, fontWeight: FontWeight.w900)),
              SizedBox(height: 1),
              Text('7 days, same pro, one payment',
                  style: TextStyle(color: Colors.white70, fontSize: 11)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20)),
              child: const Row(mainAxisSize: MainAxisSize.min, children: [
                Text('Book', style: TextStyle(
                    color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800)),
                SizedBox(width: 3),
                Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 13),
              ])),
          ]),
        ),
      ),
    );
  }

  Widget _heroBannerCard(String imagePath) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28), bottomRight: Radius.circular(28)),
      child: SizedBox(
        width: double.infinity, height: double.infinity,
        child: Image.asset(imagePath, fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                  colors: [_cyanDp, _cyan])),
              child: const Center(child: Icon(Icons.image_outlined,
                  size: 48, color: Colors.white70))))));
  }

  Widget _buildGrid(List<Map<String, dynamic>> svcs) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2, crossAxisSpacing: 14,
          mainAxisSpacing: 18, mainAxisExtent: 210),
        delegate: SliverChildBuilderDelegate(
          (_, i) => FadeTransition(opacity: _fade, child: _gridCard(svcs[i])),
          childCount: svcs.length),
      ),
    );
  }

  Widget _gridCard(Map<String, dynamic> svc) {
    final name       = svc['name'] as String? ?? 'Service';
    final basePrice  = (svc['base_price'] as num?)?.toInt() ?? 0;
    final icon       = _iconFor('${svc['category'] ?? ''} $name');
    final s          = _scale(context);
    final isCartable = CartService.isCartable(name);
    final itemType   = CartService.typeOf(name);
    final qty        = _cart.quantityOf(svc['id'] as String? ?? '');
    final inCart     = qty > 0;
    final cartItem   = _cart.itemFor(svc['id'] as String? ?? '');
    final isFullHouse = name == 'Full House Cleaning';
    // Weekly recurring packages are only offered for Hourly Cleaning —
    // see recurring_booking_screen.dart for the full 7-day flow. The chip
    // below is the ONLY entry point into that flow (product decision:
    // Option B — a badge on the card itself, no separate service picker
    // screen, since the service is fixed to Hourly Cleaning already).
    final isHourly = name == 'Hourly Cleaning';

    // Display price — from cart item if in cart, else base
    final originalPrice = (svc['original_price'] as num?)?.toInt();
    final displayPrice = inCart && cartItem != null
        ? cartItem.totalPrice
        : (itemType == CartItemType.tiered
            ? (CartService.buildTiers(svc, isFirstBooking: _isFirstBooking).isNotEmpty ? CartService.buildTiers(svc, isFirstBooking: _isFirstBooking).first.price : basePrice)
            : basePrice);

    // Duration label — hidden for Full House (BHK based, no single duration)
    // Fixed-type services read their real duration_minutes from the
    // service record — see _templateFor's comment for why the
    // CartService.durationFor(name) fallback was wrong for these.
    final fixedDurationMins = (svc['duration_minutes'] as num?)?.toInt()
        ?? CartService.durationFor(name);
    final durLabel = inCart && cartItem != null
        ? cartItem.durationLabel
        : (itemType == CartItemType.tiered
            ? '30 min'
            : itemType == CartItemType.hourly
                ? '60 min/hr'
                : isFullHouse
                    ? ''
                    : '$fixedDurationMins min');

    return GestureDetector(
      onTap: () => _open(svc),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: Stack(fit: StackFit.expand, children: [
                _serviceImage(svc, icon),

                // "Weekly" recurring package entry point — Hourly
                // Cleaning only. Tapping goes straight into
                // RecurringBookingScreen with this service pre-filled at
                // 1 hour/day (fixed) — bypasses the normal service detail
                // page entirely, since the service choice is implicit.
                if (isHourly)
                  Positioned(
                    top: 8, left: 8,
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => RecurringBookingScreen(
                            serviceId:     svc['id'] as String,
                            serviceName:   name,
                            pricePerVisit: basePrice,
                            durationMins:  60,
                          ),
                        ));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A).withValues(alpha: 0.75),
                          borderRadius: BorderRadius.circular(8)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.repeat_rounded, color: Colors.white, size: 11),
                          SizedBox(width: 3),
                          Text('Weekly', style: TextStyle(
                              color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                        ]))),
                  ),

                // Duration badge — hidden when label is empty (e.g. Full House)
                if (durLabel.isNotEmpty)
                Positioned(
                  bottom: inCart ? 46 : 8, left: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 7, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(8)),
                    child: Text(durLabel,
                        style: const TextStyle(color: Colors.white,
                            fontSize: 9, fontWeight: FontWeight.w700)))),

                // Counter overlay (in cart)
                if (inCart && isCartable && !isFullHouse)
                  Positioned(
                    bottom: 8, left: 8, right: 8,
                    child: Container(
                      height: 34,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.15),
                            blurRadius: 8, offset: const Offset(0, 2))]),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => _decrement(svc),
                            behavior: HitTestBehavior.opaque,
                            child: Container(width: 34, height: 34,
                                alignment: Alignment.center,
                                child: const Icon(Icons.remove_rounded,
                                    color: _cyan, size: 18))),
                          // Show duration for tiered, qty for others
                          Text(
                            inCart && cartItem != null
                                ? cartItem.durationLabel
                                : durLabel,
                            style: const TextStyle(
                                fontSize: 12, fontWeight: FontWeight.w900,
                                color: _ink)),
                          GestureDetector(
                            onTap: () => _increment(svc),
                            behavior: HitTestBehavior.opaque,
                            child: Container(width: 34, height: 34,
                                alignment: Alignment.center,
                                child: Icon(Icons.add_rounded,
                                    color: qty < CartService.maxQtyFor(name)
                                        ? _cyan : _faint,
                                    size: 18))),
                        ])),
                  ),

                // Add button (not in cart)
                if (!inCart && isCartable && !isFullHouse)
                  Positioned(
                    bottom: 8, right: 8,
                    child: GestureDetector(
                      onTap: () => _increment(svc),
                      behavior: HitTestBehavior.opaque,
                      child: Container(
                        width: 30, height: 30,
                        decoration: BoxDecoration(
                          color: _cyan,
                          borderRadius: BorderRadius.circular(8),
                          boxShadow: [BoxShadow(
                              color: _cyan.withValues(alpha: 0.4),
                              blurRadius: 6,
                              offset: const Offset(0, 2))]),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 18)))),
              ]),
            ),
          ),
          const SizedBox(height: 6),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _ink,
                  fontSize: 13 * s, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Row(children: [
            Expanded(
              child: Row(children: [
                Text(
                  '₹$displayPrice',
                  style: TextStyle(
                    color: inCart ? _cyan : Colors.black,
                    fontSize: 13 * s, fontWeight: FontWeight.w800)),
                if (originalPrice != null && originalPrice != basePrice && !inCart) ...[
                  const SizedBox(width: 4),
                  Text('₹$originalPrice',
                      style: TextStyle(color: _faint,
                          fontSize: 10 * s,
                          decoration: TextDecoration.lineThrough)),
                ],
              ]),
            ),
            // Tier indicator when in cart
            if (inCart && itemType == CartItemType.tiered)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: _cyan.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(6)),
                child: Text(
                  cartItem?.durationLabel ?? '',
                  style: TextStyle(color: _cyan,
                      fontSize: 10 * s, fontWeight: FontWeight.w800))),
          ]),
        ],
      ),
    );
  }

  Widget _ratingBadge(Map<String, dynamic> svc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 6, offset: const Offset(0, 2))]),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 12, color: _amber),
      const SizedBox(width: 2),
      Text(_rating(svc), style: const TextStyle(fontSize: 10.5,
          fontWeight: FontWeight.w800, color: _ink)),
    ]));

  String _rating(Map<String, dynamic> svc) {
    final r = svc['rating'];
    if (r is num) return r.toStringAsFixed(1);
    return '4.8';
  }

  Widget _serviceImage(Map<String, dynamic> svc, IconData icon) {
    // Use image_url for grid card thumbnail
    final url = (svc['image_url'] as String?)?.trim();
    Widget placeholder() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft,
            end: Alignment.bottomRight, colors: [_cyanBg, _cyanBg2])),
      child: Center(child: Icon(icon, size: 40,
          color: Colors.black.withValues(alpha: 0.50))));

    // Local asset path (starts with 'assets/')
    if (url != null && url.startsWith('assets/')) {
      return Image.asset(url, fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder());
    }
    // Network URL
    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
          loadingBuilder: (ctx, child, prog) =>
              prog == null ? child : Container(color: const Color(0xFFF1F5F9)),
          errorBuilder: (_, __, ___) => placeholder());
    }
    return placeholder();
  }

  SliverToBoxAdapter _sliverHeader(String title) =>
      SliverToBoxAdapter(child: _anim(_sectionHeader(title)));

  Widget _sectionHeader(String title) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 4),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title, style: const TextStyle(fontSize: 20,
          fontWeight: FontWeight.w900, color: _ink)),
      const SizedBox(height: 2),
      const Text('Schedule & book for later',
          style: TextStyle(fontSize: 12.5, color: _ink)),
    ]));

  Widget _buildEmpty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 52),
    child: Column(children: [
      Container(width: 66, height: 66,
        decoration: const BoxDecoration(
            color: Color(0xFFECFEFF), shape: BoxShape.circle),
        child: const Icon(Icons.search_off_rounded, size: 28, color: Colors.black)),
      const SizedBox(height: 14),
      const Text('No services found', style: TextStyle(color: _ink,
          fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('Try a different category',
          style: TextStyle(color: _ink, fontSize: 13)),
    ]));
}

// ── Cart Bottom Bar ───────────────────────────────────────────────
class _CartBottomBar extends StatelessWidget {
  final CartService cart;
  final VoidCallback onCheckout;
  const _CartBottomBar({required this.cart, required this.onCheckout});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: cart,
      builder: (ctx, _) {
        final totalQty = cart.totalQuantity;
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFF0F172A),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.25),
                blurRadius: 20, offset: const Offset(0, 8))]),
          child: Row(children: [
            GestureDetector(
              onTap: onCheckout,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(children: [
                  const Icon(Icons.keyboard_arrow_up_rounded,
                      color: Colors.white70, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    '$totalQty item${totalQty == 1 ? "" : "s"}',
                    style: const TextStyle(color: Colors.white,
                        fontSize: 13, fontWeight: FontWeight.w700)),
                ]))),
            Container(width: 1, height: 28,
                color: Colors.white.withValues(alpha: 0.12)),
            Expanded(
              child: GestureDetector(
                onTap: onCheckout,
                child: Container(
                  margin: const EdgeInsets.all(4),
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF00B1FC),
                    borderRadius: BorderRadius.circular(12)),
                  child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text('Go to cart · ₹${cart.totalPrice}',
                        style: const TextStyle(color: Colors.white,
                            fontSize: 13, fontWeight: FontWeight.w900)),
                    const SizedBox(width: 6),
                    const Icon(Icons.arrow_forward_rounded,
                        color: Colors.white, size: 15),
                  ])))),
          ]),
        );
      });
  }
}

// ── Cart Sheet (review before booking) ────────────────────────────
class _CartSheet extends StatelessWidget {
  final CartService cart;
  final bool isFirstBooking;
  const _CartSheet({required this.cart, required this.isFirstBooking});

  @override
  Widget build(BuildContext context) {
    final botPad = MediaQuery.of(context).padding.bottom;
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(children: [
        // Header
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft, end: Alignment.bottomRight,
              colors: [Color(0xFF0C4A6E), Color(0xFF00B1FC)]),
          ),
          child: SafeArea(bottom: false, child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Row(children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 38, height: 38,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.25))),
                  child: const Icon(Icons.arrow_back_ios_new,
                      color: Colors.white, size: 16))),
              const SizedBox(width: 12),
              const Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Your Cart', style: TextStyle(color: Colors.white,
                    fontSize: 18, fontWeight: FontWeight.w900)),
                Text('Review services before booking',
                    style: TextStyle(color: Colors.white70, fontSize: 11)),
              ])),
            ]),
          )),
        ),
        // Items
        Expanded(child: ListenableBuilder(
          listenable: cart,
          builder: (ctx, _) => ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            children: [
              ...cart.items.map((item) => Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0))),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFFECFEFF),
                      borderRadius: BorderRadius.circular(12)),
                    child: Center(child: Text(item.emoji ?? '🧹',
                        style: const TextStyle(fontSize: 22)))),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item.serviceName, style: const TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14,
                        color: Color(0xFF0F172A))),
                    Text('${item.durationLabel} · ₹${item.totalPrice}',
                        style: const TextStyle(color: Color(0xFF94A3B8),
                            fontSize: 11)),
                  ])),
                  // Quantity counter
                  Row(children: [
                    GestureDetector(
                      onTap: () => cart.decrement(item.serviceId),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFEFF),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF00B1FC))),
                        child: const Icon(Icons.remove_rounded,
                            color: Color(0xFF00B1FC), size: 14))),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('${item.quantity}',
                          style: const TextStyle(fontWeight: FontWeight.w900,
                              fontSize: 15, color: Color(0xFF0F172A)))),
                    GestureDetector(
                      onTap: () => cart.increment(item),
                      child: Container(
                        width: 28, height: 28,
                        decoration: BoxDecoration(
                          color: const Color(0xFF00B1FC),
                          borderRadius: BorderRadius.circular(8)),
                        child: const Icon(Icons.add_rounded,
                            color: Colors.white, size: 14))),
                    const SizedBox(width: 8),
                    Text('₹${item.totalPrice}', style: const TextStyle(
                        fontWeight: FontWeight.w900, fontSize: 15,
                        color: Color(0xFF0F172A))),
                  ]),
                ]),
              )),
              // Summary
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFFECFEFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFA5F3FC))),
                child: Column(children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                    const Text('Total Duration',
                        style: TextStyle(color: Color(0xFF0891B2), fontSize: 13)),
                    Text('${cart.totalDurationMins} min',
                        style: const TextStyle(fontWeight: FontWeight.w800,
                            color: Color(0xFF0F172A), fontSize: 13)),
                  ]),
                  const SizedBox(height: 8),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                    const Text('Total Price',
                        style: TextStyle(color: Color(0xFF0891B2), fontSize: 13)),
                    Text('₹${cart.totalPrice}',
                        style: const TextStyle(fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A), fontSize: 18)),
                  ]),
                ]),
              ),
            ],
          ),
        )),
        // Checkout button
        Container(
          padding: EdgeInsets.fromLTRB(16, 14, 16, botPad + 14),
          decoration: const BoxDecoration(
            color: Colors.white,
            border: Border(top: BorderSide(color: Color(0xFFE2E8F0)))),
          child: ListenableBuilder(
            listenable: cart,
            builder: (ctx, _) => cart.isEmpty
                ? const SizedBox.shrink()
                : Column(mainAxisSize: MainAxisSize.min, children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(
                          builder: (_) => BookingFlowScreen(
                            mode:           'schedule',
                            cartItems:      cart.toCartItems(),
                            isFirstBooking: isFirstBooking,
                          ),
                        ));
                      },
                      child: Container(
                        height: 54, width: double.infinity,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [Color(0xFF00B1FC), Color(0xFF0E7490)]),
                          borderRadius: BorderRadius.circular(16),
                          boxShadow: [BoxShadow(
                              color: const Color(0xFF00B1FC).withValues(alpha: 0.4),
                              blurRadius: 14, offset: const Offset(0, 5))]),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          const Icon(Icons.calendar_month_rounded,
                              color: Colors.white, size: 20),
                          const SizedBox(width: 8),
                          Text(
                            'Schedule ${cart.count} Service${cart.count == 1 ? '' : 's'} · ₹${cart.totalPrice}',
                            style: const TextStyle(color: Colors.white,
                                fontSize: 15, fontWeight: FontWeight.w900)),
                        ]),
                      ),
                    ),
                    const SizedBox(height: 10),
                    GestureDetector(
                      onTap: () {
                        cart.clear();
                        Navigator.pop(context);
                      },
                      child: const Text('Clear cart',
                          style: TextStyle(color: Color(0xFF94A3B8),
                              fontSize: 13, fontWeight: FontWeight.w600))),
                  ]),
          ),
        ),
      ]),
    );
  }
}


// Proxy widget to launch BookingFlowScreen — keeps services_screen

// ── Top Header Bar ────────────────────────────────────────────────
class _TopHeaderBar extends StatefulWidget {
  final ScrollController scrollController;
  final double topPad;
  final double scale;
  final Animation<double> fade;
  final AnimationController ambientCtrl;
  final String primaryLabel;
  final String secondaryLine;
  final String userInitial;
  final int cartCount;
  final VoidCallback onLocationTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onProfileTap;
  final VoidCallback onCartTap;

  const _TopHeaderBar({
    required this.scrollController,
    required this.topPad,
    required this.scale,
    required this.fade,
    required this.ambientCtrl,
    required this.primaryLabel,
    required this.secondaryLine,
    required this.userInitial,
    required this.cartCount,
    required this.onLocationTap,
    required this.onNotificationsTap,
    required this.onProfileTap,
    required this.onCartTap,
  });

  @override
  State<_TopHeaderBar> createState() => _TopHeaderBarState();
}

class _TopHeaderBarState extends State<_TopHeaderBar> {
  static const _ink    = Color(0xFF0F172A);
  static const _border = Color(0xFFE8EDF2);
  static const _cyan   = Color(0xFF00B1FC);
  static const _cyanDk = Color(0xFF00B1FC);

  static const _scrollThreshold = 24.0;
  bool _solid = false;

  @override
  void initState() {
    super.initState();
    widget.scrollController.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(covariant _TopHeaderBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController.removeListener(_onScroll);
      widget.scrollController.addListener(_onScroll);
    }
  }

  void _onScroll() {
    if (!widget.scrollController.hasClients) return;
    final shouldBeSolid = widget.scrollController.offset > _scrollThreshold;
    if (shouldBeSolid != _solid) setState(() => _solid = shouldBeSolid);
  }

  @override
  void dispose() {
    widget.scrollController.removeListener(_onScroll);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.scale;
    return FadeTransition(
      opacity: widget.fade,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        decoration: BoxDecoration(
          color: _solid ? Colors.white : Colors.transparent,
          boxShadow: _solid ? [BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10, offset: const Offset(0, 4))] : []),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, widget.topPad + 14, 20, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: GestureDetector(
                onTap: widget.onLocationTap,
                behavior: HitTestBehavior.opaque,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Flexible(child: Text(widget.primaryLabel,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: _ink, fontSize: 20 * s,
                            fontWeight: FontWeight.w800))),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 22, color: _ink),
                  ]),
                  const SizedBox(height: 2),
                  Text(widget.secondaryLine,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: _ink,
                          fontSize: 12.5 * s, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(width: 10),
            // Cart icon with badge
            GestureDetector(
              onTap: widget.onCartTap,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: widget.cartCount > 0
                        ? const Color(0xFF0F172A) : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: _border),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6, offset: const Offset(0, 2))]),
                  child: Icon(Icons.shopping_cart_rounded,
                      color: widget.cartCount > 0 ? Colors.white : _ink,
                      size: 20)),
                if (widget.cartCount > 0)
                  Positioned(top: -2, right: -2,
                    child: Container(
                      width: 18, height: 18,
                      decoration: const BoxDecoration(
                          color: Color(0xFF00B1FC), shape: BoxShape.circle),
                      child: Center(child: Text('${widget.cartCount}',
                          style: const TextStyle(color: Colors.white,
                              fontSize: 9, fontWeight: FontWeight.w900))))),
              ]),
            ),
            const SizedBox(width: 8),
            // Notifications
            GestureDetector(
              onTap: widget.onNotificationsTap,
              child: Stack(clipBehavior: Clip.none, children: [
                Container(
                  width: 42, height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white, shape: BoxShape.circle,
                    border: Border.all(color: _border),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.04),
                        blurRadius: 6, offset: const Offset(0, 2))]),
                  child: const Icon(Icons.notifications_none_rounded,
                      color: _ink, size: 20)),
                Positioned(top: 8, right: 10, child: AnimatedBuilder(
                  animation: widget.ambientCtrl,
                  builder: (_, __) => Transform.scale(
                    scale: 1.0 + widget.ambientCtrl.value * 0.25,
                    child: Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444), shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 1.5)))))),
              ]),
            ),
            const SizedBox(width: 8),
            // Profile
            GestureDetector(
              onTap: widget.onProfileTap,
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.30),
                      blurRadius: 10, offset: const Offset(0, 4))]),
                child: Center(child: Text(widget.userInitial,
                    style: const TextStyle(color: Colors.white,
                        fontWeight: FontWeight.w800, fontSize: 16)))),
            ),
          ]),
        ),
      ),
    );
  }
}

// ── Notifications Sheet (unchanged) ──────────────────────────────
class _NotificationsSheet extends StatefulWidget {
  final SupabaseClient supabase;
  const _NotificationsSheet({required this.supabase});
  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  static const _cyan   = Color(0xFF00B1FC);
  static const _cyanDk = Color(0xFF00B1FC);
  static const _cyanBg = Color(0xFFECFEFF);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE8EDF2);

  bool _loading = true;
  List<_Notif> _new = [];
  List<_Notif> _earlier = [];

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    try {
      final userId = await SupabaseService.loadCachedUserId() ??
          SupabaseService.currentUserId;
      if (userId != null) {
        final rows = await widget.supabase.from('notifications')
            .select('*').eq('user_id', userId)
            .order('created_at', ascending: false).limit(50);
        final list = (rows as List).cast<Map<String, dynamic>>();
        if (list.isNotEmpty) {
          final now = DateTime.now();
          final parsed = list.map((r) {
            final created = DateTime.tryParse(
                r['created_at']?.toString() ?? '') ?? now;
            final isNew = now.difference(created).inHours < 24;
            return _Notif(
              title: r['title'] as String? ?? 'Notification',
              body: (r['body'] ?? r['message'] ?? '').toString(),
              time: _ago(created, now),
              unread: !(r['is_read'] == true || r['read'] == true),
              isNew: isNew,
            );
          }).toList();
          if (mounted) {
            setState(() {
              _new = parsed.where((n) => n.isNew).toList();
              _earlier = parsed.where((n) => !n.isNew).toList();
              _loading = false;
            });
          }
          return;
        }
      }
    } catch (e) { debugPrint('Notifications sheet load error: $e'); }
    if (mounted) setState(() { _new = []; _earlier = []; _loading = false; });
  }

  String _ago(DateTime t, DateTime now) {
    final d = now.difference(t);
    if (d.inMinutes < 1)  return 'Just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m ago';
    if (d.inHours < 24)   return '${d.inHours}h ago';
    if (d.inDays == 1)    return 'Yesterday';
    if (d.inDays < 7)     return '${d.inDays}d ago';
    return '${(d.inDays / 7).floor()}w ago';
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.72, minChildSize: 0.45, maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollCtrl) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(children: [
          const SizedBox(height: 10),
          Container(width: 40, height: 4,
            decoration: BoxDecoration(color: _border,
                borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Notifications', style: TextStyle(fontSize: 19,
                  fontWeight: FontWeight.w900, color: _ink)),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(width: 32, height: 32,
                  decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(10)),
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: Color(0xFF64748B)))),
            ])),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: Color(0xFF00B1FC), strokeWidth: 2.5))
            : (_new.isEmpty && _earlier.isEmpty)
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 66, height: 66,
                    decoration: const BoxDecoration(
                        color: Color(0xFFECFEFF), shape: BoxShape.circle),
                    child: const Icon(Icons.notifications_none_rounded,
                        size: 30, color: Colors.black)),
                  const SizedBox(height: 14),
                  const Text("You're all caught up", style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
                  const SizedBox(height: 4),
                  const Text('No notifications yet',
                      style: TextStyle(fontSize: 13, color: _muted)),
                ]))
              : ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 30),
                  children: [
                    if (_new.isNotEmpty) ..._group('New', _new),
                    if (_earlier.isNotEmpty) ..._group('Earlier', _earlier),
                  ])),
        ]),
      ),
    );
  }

  List<Widget> _group(String label, List<_Notif> items) => [
    Padding(
      padding: const EdgeInsets.fromLTRB(2, 12, 0, 8),
      child: Text(label.toUpperCase(), style: const TextStyle(
          fontSize: 11, color: _ink,
          fontWeight: FontWeight.w800, letterSpacing: 0.8))),
    ...items.map(_row),
  ];

  Widget _row(_Notif n) => Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: n.unread ? _cyanBg : Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: n.unread ? _cyan : _border)),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(width: 38, height: 38,
        decoration: const BoxDecoration(
          gradient: LinearGradient(colors: [_cyan, _cyanDk]),
          shape: BoxShape.circle),
        child: Icon(n.icon, color: Colors.white, size: 19)),
      const SizedBox(width: 12),
      Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(n.title, style: const TextStyle(
              fontSize: 13.5, fontWeight: FontWeight.w800, color: _ink))),
          if (n.unread) Container(width: 7, height: 7,
            decoration: const BoxDecoration(
                color: Colors.black, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 3),
        Text(n.body, style: const TextStyle(
            fontSize: 12, color: _ink, height: 1.35)),
        const SizedBox(height: 5),
        Text(n.time, style: const TextStyle(
            fontSize: 10.5, color: _ink, fontWeight: FontWeight.w600)),
      ])),
    ]));
}

class _Notif {
  final String title, body, time;
  final bool unread, isNew;
  final IconData icon;
  _Notif({required this.title, required this.body, required this.time,
      this.unread = false, this.isNew = false}) : icon = Icons.notifications_rounded;
}