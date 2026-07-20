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
  final List<ServiceTier> tiers; // empty for fixed/hourly
  final int          pricePerUnit;   // for hourly/fixed
  final int          durationPerUnit; // for hourly/fixed
  final int          maxQty;
  int                quantity; // tier index (0=30min,1=60min,2=90min) OR hours for hourly

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

  // For tiered services: index into tiers list
  ServiceTier? get currentTier =>
      type == CartItemType.tiered && quantity <= tiers.length
          ? tiers[quantity - 1]
          : null;

  int get totalPrice {
    switch (type) {
      case CartItemType.tiered:
        return currentTier?.price ?? 0;
      case CartItemType.hourly:
        return pricePerUnit * quantity;
      case CartItemType.fixed:
        return pricePerUnit;
    }
  }

  int get totalDuration {
    switch (type) {
      case CartItemType.tiered:
        return currentTier?.mins ?? 0;
      case CartItemType.hourly:
        return durationPerUnit * quantity;
      case CartItemType.fixed:
        return durationPerUnit;
    }
  }

  // Label shown on counter (e.g. "30 min", "2 hr", "180 min")
  String get durationLabel {
    switch (type) {
      case CartItemType.tiered:
        return '${currentTier?.mins ?? 0} min';
      case CartItemType.hourly:
        return '${quantity}hr';
      case CartItemType.fixed:
        return '$durationPerUnit min';
    }
  }

  Map<String, dynamic> toBookingItem() => {
    'service_id':       serviceId,
    'price':            totalPrice,
    'quantity':         quantity,
    'duration_minutes': totalDuration,
  };
}

/// Global singleton cart.
class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

  // ── Service config ─────────────────────────────────────────────
  // Standard tiers (30/60/90 min)
  static const _standardTiers = [
    ServiceTier(30,  79),
    ServiceTier(60,  149),
    ServiceTier(90,  209),
  ];

  // First-booking tiers (₹25 for 30min, then standard)
  static const _firstBookingTiers = [
    ServiceTier(30,  25),
    ServiceTier(60,  149),
    ServiceTier(90,  209),
  ];

  // Hourly tiers (each unit = 1hr = ₹99)
  static const _hourlyMaxQty = 4; // max 4 hours = 240min

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

  static const _hourlyServices = {'Hourly Cleaning'};
  static const _noCartServices = {'Full House Cleaning'};

  static bool isCartable(String name) => !_noCartServices.contains(name);

  static CartItemType typeOf(String name) {
    if (_tieredServices.contains(name)) return CartItemType.tiered;
    if (_hourlyServices.contains(name)) return CartItemType.hourly;
    return CartItemType.fixed;
  }

  static List<ServiceTier> tiersFor(String name, {bool isFirstBooking = false}) {
    if (!_tieredServices.contains(name)) return [];
    if (isFirstBooking && _firstBookingEligible.contains(name)) {
      return _firstBookingTiers;
    }
    return _standardTiers;
  }

  static int maxQtyFor(String name) {
    if (_hourlyServices.contains(name)) return _hourlyMaxQty;
    if (_tieredServices.contains(name)) return 3; // 3 tiers
    return 1; // fixed services: max 1
  }

  static int durationFor(String name) {
    if (_hourlyServices.contains(name)) return 60;
    if (_tieredServices.contains(name)) return 30; // base duration
    // Fixed services
    const fixedDurations = {
      'Kitchen Cabinet Cleaning': 180,
      'Wardrobe Cleaning':        150,
  
    };
    return fixedDurations[name] ?? 60;
  }

  static int defaultPriceFor(String name) {
    if (_tieredServices.contains(name)) return 79;
    if (_hourlyServices.contains(name)) return 99;
    const fixedPrices = {
      'Kitchen Cabinet Cleaning': 499,
      'Wardrobe Cleaning':        349,
  
    };
    return fixedPrices[name] ?? 0;
  }

  // ── State ──────────────────────────────────────────────────────
  final Map<String, CartItem> _items = {};
  bool _isFirstBooking = false;

  void setFirstBooking(bool v) {
    _isFirstBooking = v;
    notifyListeners();
  }

  List<CartItem> get items          => _items.values.toList();
  int  get count                    => _items.length;
  int  get totalQuantity            => _items.values.fold(0, (s, i) => s + i.quantity);
  bool get isEmpty                  => _items.isEmpty;
  bool get isNotEmpty               => _items.isNotEmpty;
  int  get totalPrice               => _items.values.fold(0, (s, i) => s + i.totalPrice);
  int  get totalDurationMins        => _items.values.fold(0, (s, i) => s + i.totalDuration);

  bool contains(String serviceId)   => _items.containsKey(serviceId);
  int  quantityOf(String serviceId) => _items[serviceId]?.quantity ?? 0;
  CartItem? itemFor(String serviceId) => _items[serviceId];

  CartItem _makeItem(String serviceId, String name,
      int basePrice, String? emoji) {
    final t = typeOf(name);
    if (t == CartItemType.tiered) {
      return CartItem(
        serviceId:  serviceId,
        serviceName: name,
        emoji:      emoji,
        type:       CartItemType.tiered,
        tiers:      tiersFor(name, isFirstBooking: _isFirstBooking),
        maxQty:     3,
        quantity:   1,
      );
    } else if (t == CartItemType.hourly) {
      return CartItem(
        serviceId:       serviceId,
        serviceName:     name,
        emoji:           emoji,
        type:            CartItemType.hourly,
        pricePerUnit:    basePrice > 0 ? basePrice : 99,
        durationPerUnit: 60,
        maxQty:          _hourlyMaxQty,
        quantity:        1,
      );
    } else {
      return CartItem(
        serviceId:       serviceId,
        serviceName:     name,
        emoji:           emoji,
        type:            CartItemType.fixed,
        pricePerUnit:    basePrice > 0 ? basePrice : defaultPriceFor(name),
        durationPerUnit: durationFor(name),
        maxQty:          1,
        quantity:        1,
      );
    }
  }

  // ── Cap logic ──────────────────────────────────────────────────

  /// Whether the cart contains any hourly service.
  bool get _hasHourly => _items.values
      .any((i) => i.type == CartItemType.hourly);

  /// Whether the cart contains any non-hourly service.
  bool get _hasNonHourly => _items.values
      .any((i) => i.type != CartItemType.hourly);

  /// Effective max total duration in minutes:
  /// - Hourly only → 240 min
  /// - Mixed or non-hourly → 180 min
  int get effectiveMaxMins {
    if (_hasHourly && !_hasNonHourly) return 240;
    return 180;
  }

  /// How many minutes adding the next step of this service would cost.
  int _nextStepDuration(CartItem template) {
    final existing = _items[template.serviceId];
    if (existing == null) {
      // First add — costs first tier duration
      if (template.type == CartItemType.tiered) {
        final tiers = tiersFor(template.serviceName,
            isFirstBooking: _isFirstBooking);
        return tiers.isNotEmpty ? tiers[0].mins : 30;
      }
      return template.durationPerUnit > 0
          ? template.durationPerUnit
          : durationFor(template.serviceName);
    }
    // Already in cart — costs the difference between next and current tier
    if (existing.type == CartItemType.tiered &&
        existing.quantity < existing.maxQty) {
      final tiers = tiersFor(existing.serviceName,
          isFirstBooking: _isFirstBooking);
      final nextMins = tiers[existing.quantity].mins;   // next tier
      final currMins = tiers[existing.quantity - 1].mins; // current tier
      return nextMins - currMins;
    }
    return existing.durationPerUnit;
  }

  /// Check if adding the next step of this service would exceed the cap.
  /// Returns null if OK, or the cap exceeded (180 or 240).
  int? wouldExceedCap(CartItem template) {
    final isHourly = template.type == CartItemType.hourly;

    // Figure out what the cap would be AFTER adding this item
    final wouldHaveHourly  = _hasHourly || isHourly;
    final wouldHaveOther   = _hasNonHourly || !isHourly;
    final capAfterAdd = (wouldHaveHourly && !wouldHaveOther) ? 240 : 180;

    final step = _nextStepDuration(template);
    if (totalDurationMins + step > capAfterAdd) return capAfterAdd;
    return null;
  }

  // ── Mutations ──────────────────────────────────────────────────

  /// Increment tier/quantity.
  /// Returns null if OK, or the cap value (180/240) if blocked.
  int? increment(CartItem template) {
    final name = template.serviceName;

    // Check per-item max
    if (_items.containsKey(template.serviceId)) {
      final item = _items[template.serviceId]!;
      if (item.quantity >= item.maxQty) return -1; // at item max
    }

    // Check duration cap
    final cap = wouldExceedCap(template);
    if (cap != null) return cap; // blocked by cap

    if (_items.containsKey(template.serviceId)) {
      _items[template.serviceId]!.quantity++;
    } else {
      _items[template.serviceId] = _makeItem(
        template.serviceId, name,
        template.pricePerUnit, template.emoji);
    }
    notifyListeners();
    return null; // success
  }

  /// Decrement tier/quantity. Removes item when reaches 0.
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