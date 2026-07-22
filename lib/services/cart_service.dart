import 'package:flutter/foundation.dart';

// ── Tier definition ───────────────────────────────────────────────
class ServiceTier {
  final int mins;
  final int price;
  const ServiceTier(this.mins, this.price);
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
    'price':            totalPrice,
    'quantity':         quantity,
    'duration_minutes': totalDuration,
  };
}

/// Global singleton cart — all prices read from database, nothing hardcoded.
class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

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

  static const _firstBookingEligible = {
    'Bathroom Cleaning',
    'Utensil Cleaning',
    'Fan Cleaning',
    'Sweeping & Mopping',
    'Dusting & Wiping',
    'Balcony Cleaning',
  };

  static const _hourlyServices  = {'Hourly Cleaning'};
  static const _noCartServices  = {'Full House Cleaning'};
  static const _hourlyMaxQty    = 4;  // max 4 hours
  static const int cartMaxMins  = 180;

  // ── Pricing tiers — built from database values ────────────────
  // Called from services_screen when building a cart item.
  // base_price, price_30min, price_60min, price_90min all come from Supabase.
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

    if (isFirstBooking && _firstBookingEligible.contains(name)) {
      return [
        ServiceTier(30, firstBookingPrice),
        ServiceTier(60, p60),
        ServiceTier(90, p90),
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
  }

  void remove(String serviceId) {
    _items.remove(serviceId);
    notifyListeners();
  }

  void clear() {
    _items.clear();
    notifyListeners();
  }

  List<Map<String, dynamic>> toCartItems() =>
      _items.values.map((i) => i.toBookingItem()).toList();
}