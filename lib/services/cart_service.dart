import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ── Tier definition ───────────────────────────────────────────────
class ServiceTier {
  final int mins;
  final int price;
  const ServiceTier(this.mins, this.price);

  Map<String, dynamic> toJson() => {'mins': mins, 'price': price};
  factory ServiceTier.fromJson(Map<String, dynamic> j) =>
      ServiceTier(j['mins'] as int, j['price'] as int);
}

// ── Cart item types ───────────────────────────────────────────────
enum CartItemType { tiered, hourly, fixed }

/// A single cart entry.
class CartItem {
  final String       serviceId;
  final String       serviceName;
  final String?      emoji;
  final CartItemType type;
  final List<ServiceTier> tiers; // for tiered services
  final int          pricePerUnit;   // for hourly/fixed
  final int          durationPerUnit;
  final int          maxQty;
  int                quantity;

  CartItem({
    required this.serviceId,
    required this.serviceName,
    this.emoji,
    required this.type,
    this.tiers = const [],
    this.pricePerUnit = 0,
    this.durationPerUnit = 0,
    this.maxQty = 3,
    this.quantity = 1,
  });

  ServiceTier? get currentTier =>
      type == CartItemType.tiered && quantity <= tiers.length
          ? tiers[quantity - 1]
          : null;

  int get totalPrice {
    switch (type) {
      case CartItemType.tiered:  return currentTier?.price ?? 0;
      case CartItemType.hourly:  return pricePerUnit * quantity;
      case CartItemType.fixed:   return pricePerUnit;
    }
  }

  int get totalDuration {
    switch (type) {
      case CartItemType.tiered:  return currentTier?.mins ?? 0;
      case CartItemType.hourly:  return durationPerUnit * quantity;
      case CartItemType.fixed:   return durationPerUnit;
    }
  }

  String get durationLabel {
    switch (type) {
      case CartItemType.tiered:  return '${currentTier?.mins ?? 0} min';
      case CartItemType.hourly:  return '${quantity}hr';
      case CartItemType.fixed:   return '$durationPerUnit min';
    }
  }

  Map<String, dynamic> toBookingItem() => {
    'service_id':       serviceId,
    'name':             serviceName,
    'price':            totalPrice,
    'quantity':         quantity,
    'duration_minutes': totalDuration,
  };

  Map<String, dynamic> toJson() => {
    'serviceId':       serviceId,
    'serviceName':      serviceName,
    'emoji':            emoji,
    'type':             type.name,
    'tiers':            tiers.map((t) => t.toJson()).toList(),
    'pricePerUnit':     pricePerUnit,
    'durationPerUnit':  durationPerUnit,
    'maxQty':           maxQty,
    'quantity':         quantity,
  };

  factory CartItem.fromJson(Map<String, dynamic> j) => CartItem(
    serviceId:       j['serviceId'] as String,
    serviceName:     j['serviceName'] as String,
    emoji:           j['emoji'] as String?,
    type:            CartItemType.values.byName(j['type'] as String),
    tiers:           (j['tiers'] as List)
        .map((t) => ServiceTier.fromJson(t as Map<String, dynamic>))
        .toList(),
    pricePerUnit:    j['pricePerUnit'] as int,
    durationPerUnit: j['durationPerUnit'] as int,
    maxQty:          j['maxQty'] as int,
    quantity:        j['quantity'] as int,
  );
}

/// Global singleton cart — all prices/types read from database, nothing
/// hardcoded by service name anymore (see cart_type column / migration).
class CartService extends ChangeNotifier {
  CartService._() {
    _loadPersisted();
  }
  static final CartService instance = CartService._();

  static const _prefsKey = 'cleenzo_cart_v1';
  static const _claimPrefsKey = 'cleenzo_cart_fb_claim_v1';

  /// Single source of truth for which services get the first-booking ₹25
  /// discount. This one is still a Dart-side allowlist (not yet moved to
  /// the DB) — separate concern from cart_type, which controls
  /// pricing/duration SHAPE, not first-booking eligibility.
  static const firstBookingEligibleServices = {
    'Bathroom Cleaning',
    'Utensil Cleaning',
    'Fan Cleaning',
    'Sweeping & Mopping',
    'Dusting & Wiping',
    'Balcony Cleaning',
    'Kitchen Cleaning',
  };

  static const _noCartServices  = {'Full House Cleaning'};
  static const _hourlyMaxQty    = 4;  // max 4 hours
  static const int cartMaxMins  = 180;

  // ── cart_type-aware classification (reads the DB row) ──────────
  //
  // `svc` is the raw service map straight from Supabase (must include
  // 'cart_type' and 'name' — 'name' is only used as a legacy fallback
  // for any row that predates the migration and somehow has a null
  // cart_type despite the backfill).
  static CartItemType typeOfService(Map<String, dynamic> svc) {
    final ct = (svc['cart_type'] as String?)?.trim();
    switch (ct) {
      case 'tiered': return CartItemType.tiered;
      case 'hourly': return CartItemType.hourly;
      case 'fixed':  return CartItemType.fixed;
      default:
        // Legacy fallback for a row with no cart_type set at all —
        // matches the OLD hardcoded behavior so nothing silently
        // breaks for a service the migration's backfill somehow missed.
        final name = svc['name'] as String? ?? '';
        if (name == 'Hourly Cleaning') return CartItemType.hourly;
        return CartItemType.fixed;
    }
  }

  static int maxQtyForService(Map<String, dynamic> svc) {
    final t = typeOfService(svc);
    if (t == CartItemType.hourly) return _hourlyMaxQty;
    if (t == CartItemType.tiered) return 3;
    return 1;
  }

  static int durationForService(Map<String, dynamic> svc) {
    final t = typeOfService(svc);
    if (t == CartItemType.hourly) return 60;
    if (t == CartItemType.tiered) return 30; // first tier step
    // fixed — real duration from the DB, falling back to 60.
    return (svc['duration_minutes'] as num?)?.toInt() ?? 60;
  }

  // ── Legacy name-only helpers ────────────────────────────────────
  // Kept ONLY for call sites that don't have the full service map handy
  // (e.g. a bare service name string). Prefer the *Service variants
  // above wherever the service row is available — these fall back to
  // the OLD hardcoded sets and will drift from admin-panel changes to
  // cart_type, same limitation as before this migration existed.
  static const _legacyTieredServices = {
    'Bathroom Cleaning', 'Utensil Cleaning', 'Fan Cleaning',
    'Sweeping & Mopping', 'Dusting & Wiping', 'Balcony Cleaning',
    'Kitchen Cleaning',
  };
  static const _legacyHourlyServices = {'Hourly Cleaning'};

  static CartItemType typeOf(String name) {
    if (_legacyTieredServices.contains(name)) return CartItemType.tiered;
    if (_legacyHourlyServices.contains(name)) return CartItemType.hourly;
    return CartItemType.fixed;
  }

  static int maxQtyFor(String name) {
    if (_legacyHourlyServices.contains(name)) return _hourlyMaxQty;
    if (_legacyTieredServices.contains(name)) return 3;
    return 1;
  }

  static int durationFor(String name) {
    if (_legacyHourlyServices.contains(name)) return 60;
    if (_legacyTieredServices.contains(name)) return 30;
    return 60; // fallback for fixed services
  }

  static bool isCartable(String name) => !_noCartServices.contains(name);

  // Price fallback — only used if DB value is missing
  static int defaultPriceFor(Map<String, dynamic> svc) =>
      (svc['base_price'] as num?)?.toInt() ?? 0;

  // ── Pricing tiers — built from database values ────────────────
  static List<ServiceTier> buildTiers(
    Map<String, dynamic> svc, {
    bool isFirstBooking = false,
    int firstBookingPrice = 25,
  }) {
    final name     = svc['name'] as String? ?? '';
    final base     = (svc['base_price']  as num?)?.toInt() ?? 0;
    final p30      = (svc['price_30min'] as num?)?.toInt() ?? base;
    final p60      = (svc['price_60min'] as num?)?.toInt() ?? (base * 2);
    final p90      = (svc['price_90min'] as num?)?.toInt() ?? (base * 3);

    if (isFirstBooking && firstBookingEligibleServices.contains(name)) {
      return [
        ServiceTier(30, firstBookingPrice),
        ServiceTier(60, firstBookingPrice + p30),
        ServiceTier(90, firstBookingPrice + p30 + p30),
      ];
    }
    return [
      ServiceTier(30, p30),
      ServiceTier(60, p60),
      ServiceTier(90, p90),
    ];
  }

  // ── State ──────────────────────────────────────────────────────
  final Map<String, CartItem> _items = {};
  bool _isFirstBooking = false;

  String? _firstBookingClaimServiceId;
  String? get firstBookingClaimServiceId => _firstBookingClaimServiceId;

  // ── Persistence ────────────────────────────────────────────────
  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw != null && raw.isNotEmpty) {
        final List<dynamic> list = jsonDecode(raw);
        for (final entry in list) {
          final item = CartItem.fromJson(entry as Map<String, dynamic>);
          _items[item.serviceId] = item;
        }
      }
      _firstBookingClaimServiceId = prefs.getString(_claimPrefsKey);
      if (_firstBookingClaimServiceId != null &&
          !_items.containsKey(_firstBookingClaimServiceId)) {
        _firstBookingClaimServiceId = null;
        await prefs.remove(_claimPrefsKey);
      }
      if (_items.isNotEmpty) notifyListeners();
    } catch (e) {
      debugPrint('CartService: failed to load persisted cart (non-fatal): $e');
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_items.values.map((i) => i.toJson()).toList());
      await prefs.setString(_prefsKey, raw);
      if (_firstBookingClaimServiceId != null) {
        await prefs.setString(_claimPrefsKey, _firstBookingClaimServiceId!);
      } else {
        await prefs.remove(_claimPrefsKey);
      }
    } catch (e) {
      debugPrint('CartService: failed to persist cart (non-fatal): $e');
    }
  }

  void setFirstBooking(bool v) {
    _isFirstBooking = v;
    notifyListeners();
  }

  bool isFirstBookingPriceFor(String serviceId, String serviceName) {
    if (!_isFirstBooking) return false;
    if (!firstBookingEligibleServices.contains(serviceName)) return false;
    if (_firstBookingClaimServiceId == null) return true;
    return _firstBookingClaimServiceId == serviceId;
  }

  List<CartItem> get items           => _items.values.toList();
  int  get count                     => _items.length;
  int  get totalQuantity             => _items.values.fold(0, (s, i) => s + i.quantity);
  bool get isEmpty                   => _items.isEmpty;
  bool get isNotEmpty                => _items.isNotEmpty;
  int  get totalPrice                => _items.values.fold(0, (s, i) => s + i.totalPrice);
  int  get totalDurationMins         => _items.values.fold(0, (s, i) => s + i.totalDuration);

  bool contains(String serviceId)    => _items.containsKey(serviceId);
  int  quantityOf(String serviceId)  => _items[serviceId]?.quantity ?? 0;
  CartItem? itemFor(String serviceId) => _items[serviceId];

  // ── Cap logic ──────────────────────────────────────────────────
  bool get _hasHourly    => _items.values.any((i) => i.type == CartItemType.hourly);
  bool get _hasNonHourly => _items.values.any((i) => i.type != CartItemType.hourly);

  int get effectiveMaxMins =>
      (_hasHourly && !_hasNonHourly) ? 240 : cartMaxMins;

  int _nextStepDuration(CartItem template) {
    final existing = _items[template.serviceId];
    if (existing == null) {
      if (template.type == CartItemType.tiered && template.tiers.isNotEmpty) {
        return template.tiers[0].mins;
      }
      return template.durationPerUnit > 0
          ? template.durationPerUnit
          : durationFor(template.serviceName);
    }
    if (existing.type == CartItemType.tiered &&
        existing.quantity < existing.maxQty &&
        existing.tiers.length > existing.quantity) {
      return existing.tiers[existing.quantity].mins -
             existing.tiers[existing.quantity - 1].mins;
    }
    return existing.durationPerUnit;
  }

  int? wouldExceedCap(CartItem template) {
    final isHourly       = template.type == CartItemType.hourly;
    final wouldHaveHourly  = _hasHourly || isHourly;
    final wouldHaveOther   = _hasNonHourly || !isHourly;
    final capAfterAdd = (wouldHaveHourly && !wouldHaveOther) ? 240 : cartMaxMins;
    final step = _nextStepDuration(template);
    if (totalDurationMins + step > capAfterAdd) return capAfterAdd;
    return null;
  }

  // ── Mutations ──────────────────────────────────────────────────

  int? increment(CartItem template) {
    final isNewItem = !_items.containsKey(template.serviceId);

    if (!isNewItem) {
      final item = _items[template.serviceId]!;
      if (item.quantity >= item.maxQty) return -1;
    }
    final cap = wouldExceedCap(template);
    if (cap != null) return cap;

    if (!isNewItem) {
      _items[template.serviceId]!.quantity++;
    } else {
      _items[template.serviceId] = CartItem(
        serviceId:       template.serviceId,
        serviceName:     template.serviceName,
        emoji:           template.emoji,
        type:            template.type,
        tiers:           template.tiers,
        pricePerUnit:    template.pricePerUnit,
        durationPerUnit: template.durationPerUnit,
        maxQty:          template.maxQty,
        quantity:        1,
      );

      if (_firstBookingClaimServiceId == null &&
          isFirstBookingPriceFor(template.serviceId, template.serviceName)) {
        _firstBookingClaimServiceId = template.serviceId;
      }
    }
    notifyListeners();
    _persist();
    return null;
  }

  void decrement(String serviceId) {
    final item = _items[serviceId];
    if (item == null) return;
    if (item.quantity > 1) {
      item.quantity--;
    } else {
      _items.remove(serviceId);
      if (_firstBookingClaimServiceId == serviceId) {
        _firstBookingClaimServiceId = null;
      }
    }
    notifyListeners();
    _persist();
  }

  void remove(String serviceId) {
    _items.remove(serviceId);
    if (_firstBookingClaimServiceId == serviceId) {
      _firstBookingClaimServiceId = null;
    }
    notifyListeners();
    _persist();
  }

  void clear() {
    _items.clear();
    _firstBookingClaimServiceId = null;
    notifyListeners();
    _persist();
  }

  List<Map<String, dynamic>> toCartItems() =>
      _items.values.map((i) => i.toBookingItem()).toList();
}