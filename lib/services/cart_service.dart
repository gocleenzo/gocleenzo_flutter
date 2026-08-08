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

  // Includes 'name' so downstream screens (BookingFlowScreen summary,
  // booking_items insert, My Bookings, Booking Detail) can show and store
  // the actual service name — previously missing, which is why every
  // multi-service booking fell back to the generic "Service" label.
  Map<String, dynamic> toBookingItem() => {
    'service_id':       serviceId,
    'name':             serviceName,
    'price':            totalPrice,
    'quantity':         quantity,
    'duration_minutes': totalDuration,
  };

  // ── Persistence (save/restore across app close) ──────────────
  // Full serialization of everything needed to reconstruct this exact
  // item — NOT the same as toBookingItem() above, which only includes
  // what a booking record needs. This needs tiers/pricePerUnit/etc. too,
  // since re-hydrating a CartItem after app restart requires every
  // field the constructor takes.
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

/// Global singleton cart — all prices read from database, nothing hardcoded.
class CartService extends ChangeNotifier {
  CartService._() {
    // Fires once, the first time CartService.instance is ever accessed
    // (e.g. from services_screen's State field). Loads whatever was
    // saved from a previous session, so a customer who adds items,
    // fully closes the app, and reopens it later finds their cart
    // exactly as they left it.
    _loadPersisted();
  }
  static final CartService instance = CartService._();

  static const _prefsKey = 'cleenzo_cart_v1';

  // ── Service type config (only behavior, no prices) ────────────
  static const _tieredServices = {
    'Bathroom Cleaning',
    'Utensil Cleaning',
    'Fan Cleaning',
    'Sweeping & Mopping',
    'Dusting & Wiping',
    'Balcony Cleaning',
    'Kitchen Cleaning',
    'Refrigerator Cleaning',
  };

  /// Single source of truth for which services get the first-booking ₹25
  /// discount. Public (was private + duplicated with a DIFFERENT, drifted
  /// list in service_detail_screen.dart — that duplicate is now removed;
  /// that screen reads this instead) so there's only ever one place this
  /// can be edited, and the UI banner + actual price calculation can never
  /// disagree about which services qualify again.
  static const firstBookingEligibleServices = {
    'Bathroom Cleaning',
    'Utensil Cleaning',
    'Fan Cleaning',
    'Sweeping & Mopping',
    'Dusting & Wiping',
    'Balcony Cleaning',
    'Kitchen Cleaning',
  };

  static const _hourlyServices  = {'Hourly Cleaning'};
  static const _noCartServices  = {'Full House Cleaning'};
  static const _hourlyMaxQty    = 4;  // max 4 hours
  static const int cartMaxMins  = 180;

  // ── Pricing tiers — built from database values ────────────────
  // Called from services_screen when building a cart item.
  // base_price, price_30min, price_60min, price_90min all come from Supabase.
  //
  // First-booking discount model: only the FIRST unit of an eligible
  // service is priced at firstBookingPrice (₹25). Every additional unit of
  // that SAME service is charged at its flat REGULAR single-unit price
  // (price_30min) — deliberately ignoring any bundle discount baked into
  // the normal 60/90-min tier prices, so a first-time customer always
  // gets a predictable "₹25 + (₹regular × extra units)" total. Each
  // eligible service in a multi-service cart gets its OWN independent
  // ₹25-for-the-first-unit treatment — that already falls out naturally
  // from tiers being built per-service here and cart totals being summed
  // across items, so a Bathroom Cleaning ×1 (₹25) + Utensil Cleaning ×2
  // (₹25 + ₹regular) cart correctly totals both discounts added together.
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
      // First unit is the special ₹25 offer price. Every additional unit
      // is priced at the flat REGULAR single-unit rate (p30) — not
      // whatever bundle/incremental rate the normal 60/90-min tiers
      // happen to be. This was previously computed as
      // firstBookingPrice + (p60 − p30), which quietly inherited any
      // bundle discount baked into price_60min/price_90min (e.g. Bathroom
      // Cleaning ×2 coming out to ₹95 instead of the expected ₹104,
      // because its DB-configured 60-min tier price was itself already
      // discounted below 2×p30). "Regular calculation" for extra units
      // now means exactly p30 added per unit, with no bundle discount
      // applied on top of the first-unit offer.
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

  // ── Static helpers ────────────────────────────────────────────
  static bool isCartable(String name) => !_noCartServices.contains(name);

  static CartItemType typeOf(String name) {
    if (_tieredServices.contains(name)) return CartItemType.tiered;
    if (_hourlyServices.contains(name)) return CartItemType.hourly;
    return CartItemType.fixed;
  }

  static int maxQtyFor(String name) {
    if (_hourlyServices.contains(name)) return _hourlyMaxQty;
    if (_tieredServices.contains(name)) return 3;
    return 1;
  }

  static int durationFor(String name) {
    if (_hourlyServices.contains(name)) return 60;
    if (_tieredServices.contains(name)) return 30;
    return 60; // fallback for fixed services
  }

  // Price fallback — only used if DB value is missing
  static int defaultPriceFor(Map<String, dynamic> svc) =>
      (svc['base_price'] as num?)?.toInt() ?? 0;

  // ── State ──────────────────────────────────────────────────────
  final Map<String, CartItem> _items = {};
  bool _isFirstBooking = false;

  // ── Persistence ────────────────────────────────────────────────
  Future<void> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return;
      final List<dynamic> list = jsonDecode(raw);
      for (final entry in list) {
        final item = CartItem.fromJson(entry as Map<String, dynamic>);
        _items[item.serviceId] = item;
      }
      if (_items.isNotEmpty) notifyListeners();
    } catch (e) {
      debugPrint('CartService: failed to load persisted cart (non-fatal): $e');
    }
  }

  /// Fire-and-forget — UI state already updates via notifyListeners() in
  /// each mutation below; this just writes the same state to disk right
  /// after, so a subsequent app close/reopen restores it. An empty cart
  /// persists as an empty list, which is exactly what makes clear()
  /// (called after a successful booking, or by the customer directly)
  /// correctly wipe the saved cart too — nothing lingers after checkout.
  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = jsonEncode(_items.values.map((i) => i.toJson()).toList());
      await prefs.setString(_prefsKey, raw);
    } catch (e) {
      debugPrint('CartService: failed to persist cart (non-fatal): $e');
    }
  }

  void setFirstBooking(bool v) {
    _isFirstBooking = v;
    notifyListeners();
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

  /// Returns null on success, -1 if at item max, or cap value if duration exceeded.
  int? increment(CartItem template) {
    if (_items.containsKey(template.serviceId)) {
      final item = _items[template.serviceId]!;
      if (item.quantity >= item.maxQty) return -1;
    }
    final cap = wouldExceedCap(template);
    if (cap != null) return cap;

    if (_items.containsKey(template.serviceId)) {
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
    }
    notifyListeners();
    _persist();
  }

  void remove(String serviceId) {
    _items.remove(serviceId);
    notifyListeners();
    _persist();
  }

  void clear() {
    _items.clear();
    notifyListeners();
    _persist();
  }

  List<Map<String, dynamic>> toCartItems() =>
      _items.values.map((i) => i.toBookingItem()).toList();
}