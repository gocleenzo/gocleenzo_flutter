import 'dart:async';
import 'package:go_router/go_router.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import 'service_detail_screen.dart';

class ServicesScreen extends StatefulWidget {
  const ServicesScreen({super.key});
  @override
  State<ServicesScreen> createState() => _ServicesScreenState();
}

class _ServicesScreenState extends State<ServicesScreen>
    with TickerProviderStateMixin {
  final _supabase   = Supabase.instance.client;
  final _scrollCtrl = ScrollController();

  // Hero banner carousel
  late final PageController _bannerCtrl;
  Timer? _bannerAutoTimer;
  bool _userInteractingWithBanner = false;
  int _bannerIndex = 0;

  late final AnimationController _intro;
  late final Animation<double>   _fade;
  late final Animation<Offset>   _slide;

  // Subtle ambient animation for shimmer + pulse
  late final AnimationController _ambientCtrl;

  // ── Cyan blue + white palette ───────────────────────────────
  static const _cyan    = Color(0xFF06B6D4);
  static const _cyanDk  = Color(0xFF0891B2);
  static const _cyanDp  = Color(0xFF0E7490);
  static const _cyanBg  = Color(0xFFECFEFF);
  static const _cyanBg2 = Color(0xFFCFFAFE);
  static const _ink     = Color(0xFF0F172A);
  static const _muted   = Color(0xFF64748B);
  static const _faint   = Color(0xFF94A3B8);
  static const _border  = Color(0xFFE8EDF2);
  static const _bg      = Color(0xFFF8FAFC);
  static const _amber   = Color(0xFFF59E0B);
  static const _greenDk = Color(0xFF059669);

  // Hero banner images — pure photo carousel, no text/button overlay.
  static const _bannerImages = [
    'assets/banners/offer1.png',
    'assets/banners/offer2.png',
    'assets/banners/offer3.png',
  ];

  // ── Fixed display order — services always sort into this order
  // (not alphabetical), regardless of Supabase's default ordering.
  // Any service whose name isn't in this list falls to the end,
  // keeping its relative original order.
  static const List<String> _serviceOrder = [
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
    'Pre-Party Cleaning',
    'After-Party Cleanup',
  ];

  List<Map<String, dynamic>> _applyCustomOrder(
      List<Map<String, dynamic>> list) {
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

  // Same 5 services eligible for the ₹25 first-booking price, matching
  // service_detail_screen.dart's _firstBookingEligible set.
  static const Set<String> _firstBookingEligible = {
    'Bathroom Cleaning',
    'Balcony Cleaning',
    'Fan Cleaning',
    'Utensil Cleaning',
    'Kitchen Cleaning',
  };

  bool _isFirstBooking = false;

  // ── Exact service.id → local asset mapping (reliable) ─────────
  static const Map<String, String> _assetMap = {
    '6f150323-d018-44c0-bfe2-2037efa1f5c0': 'assets/services/bathroom-cleaning.png',  // Bathroom Cleaning
    '6201b258-ed2c-4c83-b8e7-bd413cc5b67b': 'assets/services/wardrobe.png',           // Wardrobe Cleaning
    '6678a63d-059c-4ca5-ad11-3781f8449bb0': 'assets/services/full-home-cleaning.png', // Full House Cleaning
    'b7e6db9d-455d-46d5-ba4d-8e993fe1255d': 'assets/services/fan-cleaning.png',       // Fan Cleaning
    '42719385-f88c-41ab-9e59-6ac4856f6112': 'assets/services/dusting-wiping.png',     // Dusting & Wiping
    '2b3bd63d-c1d5-40cf-a818-33501e9e61b4': 'assets/services/sweeping-mopping.png',   // Sweeping & Mopping
    'ab1004e9-de4e-4ab6-9d34-30d7b23913a3': 'assets/services/fridge-cleaning.png',    // Refrigerator Cleaning
    '423a1354-d995-49df-ba67-effcb43befbf': 'assets/services/kitchen-cleaning.png',   // Kitchen Cleaning
    '5af62745-c480-4579-a81a-a6a267cef2c3': 'assets/services/Utensils-cleaning.png',  // Utensil Cleaning
    '581ee014-e42b-43bf-9818-692b08a0ac53': 'assets/services/cabinet.png',            // Kitchen Cabinet Cleaning
    'ae4eac44-3444-4d45-b4a3-6387c043d5cf': 'assets/services/balcony-cleaning.png',   // Balcony Cleaning
    'c104cecf-dc59-4514-bbaa-33301da6db1e': 'assets/services/after.png',              // After-Party Cleanup
    '44a7c787-41f1-4ed9-b8e6-5066dcc009ce': 'assets/services/pre.png',                // Pre-Party Cleaning
  };

  List<Map<String, dynamic>> _services   = [];
  List<String>               _categories = ['All'];
  String _activeTab    = 'All';
  bool   _loading      = true;
  String _userName     = 'there';

  // Location
  String _locationLabel   = ''; // e.g. "Home", "Office"
  String _locationArea    = '';
  String _locationCity    = '';
  String _locationAddress = ''; // full address line, for the subtitle
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
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════
  // RESPONSIVE SCALE
  // ═══════════════════════════════════════════════════════════════
  double _scale(BuildContext context) {
    final w = MediaQuery.of(context).size.width;
    final factor = w / 375.0;
    return factor.clamp(0.92, 1.15);
  }

  // ═══════════════════════════════════════════════════════════════
  // DATA
  // ═══════════════════════════════════════════════════════════════
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
        // First-booking check — same status filter as service_detail_screen.
        _supabase.from('bookings').select('id')
            .eq('customer_id', userId)
            .inFilter('status', ['completed', 'accepted',
                'in_progress', 'pending'])
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
        _isFirstBooking   = bookingsRows.isEmpty;
        _locationLoading   = false;
        _loading    = false;
      });
      _intro.forward();
    } catch (e) {
      debugPrint('Services load error: $e');
      if (mounted) {
        setState(() {
          _loading = false;
          _locationLoading = false;
        });
      }
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
    if (s.contains('bath'))                              return Icons.bathtub_outlined;
    if (s.contains('kitchen'))                           return Icons.countertops_outlined;
    if (s.contains('sofa') || s.contains('uphol'))       return Icons.weekend_outlined;
    if (s.contains('fridge') || s.contains('appliance')) return Icons.kitchen_outlined;
    if (s.contains('window') || s.contains('glass'))     return Icons.window_outlined;
    if (s.contains('floor') || s.contains('tile'))       return Icons.grid_4x4_outlined;
    if (s.contains('party') || s.contains('event'))      return Icons.celebration_outlined;
    if (s.contains('home') || s.contains('full'))        return Icons.home_outlined;
    if (s.contains('all'))                               return Icons.apps_outlined;
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

  // ═══════════════════════════════════════════════════════════════
  // BUILD
  // ═══════════════════════════════════════════════════════════════
  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(
            color: _cyan, strokeWidth: 2.5)),
      );
    }

    // No more separate "Popular" bucket — every service goes into the
    // single 2-column grid below, in the fixed custom order.
    final grid = isAllTab ? _services : _filtered;

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(children: [
        CustomScrollView(
          controller: _scrollCtrl,
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
                child: _anim(_buildHeroBanner(topPad))),

            if (_services.isEmpty)
              SliverToBoxAdapter(child: _buildEmpty())
            else ...[
              if (grid.isNotEmpty) ...[
                _sliverHeader(isAllTab ? 'All house help services' : _activeTab),
                _buildGrid(grid),
              ] else
                SliverToBoxAdapter(child: _buildEmpty()),
            ],

            SliverToBoxAdapter(child: SizedBox(height: botPad + 24)),
          ],
        ),

        // Floating header — sits ON TOP of the banner image (transparent
        // at rest, so the photo shows straight through it), then fades
        // to solid white once the user scrolls, same as before — but
        // now it's a true overlay instead of a pinned sliver, so it can
        // sit directly over the full-bleed photo like the reference.
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
            userInitial: _userName.isNotEmpty
                ? _userName[0].toUpperCase() : 'A',
            onLocationTap: _openLocationPicker,
            onNotificationsTap: _openNotifications,
            onProfileTap: () => context.go('/account'),
          ),
        ),
      ]),
    );
  }

  // ── Hero promo banner — pure image slideshow, full-bleed, extends
  // behind the status bar so the floating header can sit on top of it ─
  Widget _buildHeroBanner(double topPad) {
    // Extra height at the top so the photo itself extends behind the
    // status bar / floating header, instead of starting below it.
    const visibleBannerHeight = 320.0;
    final totalHeight = topPad + visibleBannerHeight;

    return Column(children: [
      SizedBox(
        height: totalHeight,
        child: NotificationListener<ScrollNotification>(
          onNotification: (notif) {
            if (notif is ScrollStartNotification &&
                notif.dragDetails != null) {
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
            borderRadius: BorderRadius.circular(4)),
        );
      })),
      const SizedBox(height: 8),
    ]);
  }

  // Full-bleed image — no side padding, no top rounding (so it runs
  // flush behind the status bar and the floating header sits directly
  // on top of it, matching the reference). Slight rounding only at the
  // bottom, where it meets the white "All house help services" section.
  Widget _heroBannerCard(String imagePath) {
    return ClipRRect(
      borderRadius: const BorderRadius.only(
        bottomLeft: Radius.circular(28),
        bottomRight: Radius.circular(28),
      ),
      child: SizedBox(
        width: double.infinity,
        height: double.infinity,
        child: Image.asset(
          imagePath,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [_cyanDp, _cyan]),
            ),
            child: const Center(
              child: Icon(Icons.image_outlined,
                  size: 48, color: Colors.white70),
            ),
          ),
        ),
      ),
    );
  }

  // ── Grid of smaller photo cards ───────────────────────────────
  Widget _buildGrid(List<Map<String, dynamic>> svcs) {
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount:   2,
          crossAxisSpacing: 14,
          mainAxisSpacing:  18,
          mainAxisExtent:   190,
        ),
        delegate: SliverChildBuilderDelegate(
          (_, i) => FadeTransition(
              opacity: _fade, child: _gridCard(svcs[i])),
          childCount: svcs.length,
        ),
      ),
    );
  }

  // ── Grid card — plain image on top, name + price below ──────────
  // Shows ₹25 first-booking price (with original struck through) for
  // eligible services when this is the customer's first booking.
  Widget _gridCard(Map<String, dynamic> svc) {
    final name      = svc['name'] as String? ?? 'Service';
    final basePrice = (svc['base_price'] as num?)?.toInt() ?? 0;
    final icon      = _iconFor('${svc['category'] ?? ''} $name');
    final s         = _scale(context);

    final isFirstBookingPrice =
        _isFirstBooking && _firstBookingEligible.contains(name);

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
                Positioned(top: 8, right: 8, child: _ratingBadge(svc)),
              ]),
            ),
          ),
          const SizedBox(height: 8),
          Text(name, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: _ink,
                  fontSize: 14 * s, fontWeight: FontWeight.w800,
                  letterSpacing: 0.1)),
          const SizedBox(height: 3),
          isFirstBookingPrice
              ? Row(children: [
                  Text('₹25',
                      style: TextStyle(color: _greenDk,
                          fontSize: 15 * s, fontWeight: FontWeight.w900)),
                  const SizedBox(width: 6),
                  Text('₹$basePrice',
                      style: TextStyle(color: _faint,
                          fontSize: 11.5 * s, fontWeight: FontWeight.w600,
                          decoration: TextDecoration.lineThrough)),
                ])
              : Text('₹$basePrice ', maxLines: 1, overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: _cyanDk,
                      fontSize: 13.5 * s, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  // ── Shared pieces ─────────────────────────────────────────────
  Widget _ratingBadge(Map<String, dynamic> svc) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
    decoration: BoxDecoration(
      color: Colors.white, borderRadius: BorderRadius.circular(20),
      boxShadow: [BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 6, offset: const Offset(0, 2))]),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      const Icon(Icons.star_rounded, size: 12, color: _amber),
      const SizedBox(width: 2),
      Text(_rating(svc), style: const TextStyle(fontSize: 10.5,
          fontWeight: FontWeight.w800, color: _ink)),
    ]),
  );

  String _rating(Map<String, dynamic> svc) {
    final r = svc['rating'];
    if (r is num) return r.toStringAsFixed(1);
    return '4.8';
  }

  Widget _serviceImage(Map<String, dynamic> svc, IconData icon) {
    final url = (svc['image_url'] as String?)?.trim();

    Widget placeholder() => Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft, end: Alignment.bottomRight,
          colors: [_cyanBg, _cyanBg2])),
      child: Center(child: Icon(icon, size: 40,
          color: _cyanDk.withValues(alpha: 0.50))),
    );

    if (url != null && url.isNotEmpty) {
      return Image.network(url, fit: BoxFit.cover,
        loadingBuilder: (ctx, child, prog) =>
            prog == null ? child : Container(color: const Color(0xFFF1F5F9)),
        errorBuilder: (ctx, e, s) {
          final asset = _assetFor(svc);
          if (asset != null) {
            return Image.asset(asset, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => placeholder());
          }
          return placeholder();
        });
    }

    final asset = _assetFor(svc);
    if (asset != null) {
      return Image.asset(asset, fit: BoxFit.cover,
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
    ]),
  );

  Widget _buildEmpty() => Padding(
    padding: const EdgeInsets.symmetric(vertical: 52),
    child: Column(children: [
      Container(width: 66, height: 66,
        decoration: const BoxDecoration(color: _cyanBg, shape: BoxShape.circle),
        child: const Icon(Icons.search_off_rounded, size: 28, color: _cyanDk)),
      const SizedBox(height: 14),
      const Text('No services found', style: TextStyle(color: _ink,
          fontSize: 15, fontWeight: FontWeight.w800)),
      const SizedBox(height: 4),
      const Text('Try a different category',
          style: TextStyle(color: _ink, fontSize: 13)),
    ]),
  );
}

// ═══════════════════════════════════════════════════════════════
// TOP HEADER BAR — transparent at rest, fades to solid white once
// the user scrolls past a small threshold. Listens to the scroll
// controller directly so only this small widget rebuilds on scroll,
// not the whole screen.
// ═══════════════════════════════════════════════════════════════
class _TopHeaderBar extends StatefulWidget {
  final ScrollController scrollController;
  final double topPad;
  final double scale;
  final Animation<double> fade;
  final AnimationController ambientCtrl;
  final String primaryLabel;
  final String secondaryLine;
  final String userInitial;
  final VoidCallback onLocationTap;
  final VoidCallback onNotificationsTap;
  final VoidCallback onProfileTap;

  const _TopHeaderBar({
    required this.scrollController,
    required this.topPad,
    required this.scale,
    required this.fade,
    required this.ambientCtrl,
    required this.primaryLabel,
    required this.secondaryLine,
    required this.userInitial,
    required this.onLocationTap,
    required this.onNotificationsTap,
    required this.onProfileTap,
  });

  @override
  State<_TopHeaderBar> createState() => _TopHeaderBarState();
}

class _TopHeaderBarState extends State<_TopHeaderBar> {
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _border = Color(0xFFE8EDF2);
  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);

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
    if (shouldBeSolid != _solid) {
      setState(() => _solid = shouldBeSolid);
    }
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
          boxShadow: _solid
              ? [BoxShadow(
                  color: Colors.black.withValues(alpha: 0.05),
                  blurRadius: 10, offset: const Offset(0, 4))]
              : [],
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(20, widget.topPad + 14, 20, 14),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: GestureDetector(
                onTap: widget.onLocationTap,
                behavior: HitTestBehavior.opaque,
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Flexible(
                      child: Text(widget.primaryLabel,
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              color: _ink, fontSize: 20 * s,
                              fontWeight: FontWeight.w800)),
                    ),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down_rounded,
                        size: 22, color: _ink),
                  ]),
                  const SizedBox(height: 2),
                  Text(widget.secondaryLine,
                      maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          color: _ink,
                          fontSize: 12.5 * s,
                          fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
            const SizedBox(width: 12),
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
                        border: Border.all(color: Colors.white, width: 1.5))),
                  ),
                )),
              ]),
            ),
            const SizedBox(width: 10),
            GestureDetector(
              onTap: widget.onProfileTap,
              child: Container(
                width: 42, height: 42,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                      color: _cyan.withValues(alpha: 0.30),
                      blurRadius: 10, offset: const Offset(0, 4))]),
                child: Center(child: Text(
                  widget.userInitial,
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w800, fontSize: 16))),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════
// NOTIFICATIONS SHEET
// ═══════════════════════════════════════════════════════════════
class _NotificationsSheet extends StatefulWidget {
  final SupabaseClient supabase;
  const _NotificationsSheet({required this.supabase});
  @override
  State<_NotificationsSheet> createState() => _NotificationsSheetState();
}

class _NotificationsSheetState extends State<_NotificationsSheet> {
  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
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
    } catch (e) {
      debugPrint('Notifications sheet load error: $e');
    }
    if (mounted) {
      setState(() {
        _new = _sampleNew;
        _earlier = _sampleEarlier;
        _loading = false;
      });
    }
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

  static final _sampleNew = [
    _Notif(title: 'Booking confirmed',
        body: 'Your bathroom deep clean is scheduled for tomorrow, 10:00 AM.',
        time: '2h ago', unread: true, isNew: true,
        icon: Icons.event_available_rounded),
    _Notif(title: 'Offer applied',
        body: 'You saved ₹100 with code CLEAN20 on your last booking.',
        time: '5h ago', unread: true, isNew: true,
        icon: Icons.local_offer_rounded),
  ];
  static final _sampleEarlier = [
    _Notif(title: 'Your pro is on the way',
        body: 'Rahul is arriving for your kitchen deep clean.',
        time: 'Yesterday', icon: Icons.directions_car_rounded),
    _Notif(title: 'Rate your service',
        body: 'How was your sofa cleaning? Tap to leave a review.',
        time: '2d ago', icon: Icons.star_rounded),
    _Notif(title: 'Welcome to Cleenzo',
        body: 'Book your first clean and get 20% off your order.',
        time: '1w ago', icon: Icons.celebration_rounded),
  ];

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
            decoration: BoxDecoration(
              color: _border, borderRadius: BorderRadius.circular(2))),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
            child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Notifications', style: TextStyle(fontSize: 19,
                  fontWeight: FontWeight.w900, color: _ink)),
              GestureDetector(
                onTap: () => Navigator.pop(ctx),
                child: Container(width: 32, height: 32,
                  decoration: const BoxDecoration(
                      color: _cyanBg, shape: BoxShape.circle),
                  child: const Icon(Icons.close_rounded,
                      size: 18, color: _cyanDk))),
            ])),
          Expanded(child: _loading
            ? const Center(child: CircularProgressIndicator(
                color: _cyan, strokeWidth: 2.5))
            : (_new.isEmpty && _earlier.isEmpty)
              ? _empty()
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
      border: Border.all(
          color: n.unread ? const Color(0xFFCFFAFE) : _border)),
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
                color: _cyan, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 3),
        Text(n.body, style: const TextStyle(
            fontSize: 12, color: _ink, height: 1.35)),
        const SizedBox(height: 5),
        Text(n.time, style: const TextStyle(
            fontSize: 10.5, color: _ink, fontWeight: FontWeight.w600)),
      ])),
    ]),
  );

  Widget _empty() => Center(child: Column(
      mainAxisSize: MainAxisSize.min, children: [
    Container(width: 66, height: 66,
      decoration: const BoxDecoration(color: _cyanBg, shape: BoxShape.circle),
      child: const Icon(Icons.notifications_none_rounded,
          size: 30, color: _cyanDk)),
    const SizedBox(height: 14),
    const Text("You're all caught up", style: TextStyle(
        fontSize: 15, fontWeight: FontWeight.w800, color: _ink)),
    const SizedBox(height: 4),
    const Text('No notifications yet',
        style: TextStyle(fontSize: 13, color: _ink)),
  ]));
}

class _Notif {
  final String title, body, time;
  final bool unread, isNew;
  final IconData icon;
  _Notif({required this.title, required this.body, required this.time,
      this.unread = false, this.isNew = false,
      this.icon = Icons.notifications_rounded});
}