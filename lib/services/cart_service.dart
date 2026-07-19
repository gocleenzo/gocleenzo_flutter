import 'package:flutter/foundation.dart';

// ── Cart item types ───────────────────────────────────────────
enum CartItemType { perUnit, fixed, hourly }

/// A single cart entry.
class CartItem {
  final String       serviceId;
  final String       serviceName;
  final int          pricePerUnit;  // price per unit/hour/fixed
  final int          durationPerUnit; // mins per unit (30 / 60 / fixed)
  final String?      emoji;
  final int          maxQty;        // hard cap on quantity
  final CartItemType type;
  int                quantity;      // units / hours added

  CartItem({
    required this.serviceId,
    required this.serviceName,
    required this.pricePerUnit,
    required this.durationPerUnit,
    this.emoji,
    this.maxQty = 1,
    this.type   = CartItemType.fixed,
    this.quantity = 1,
  });

  int get totalPrice    => pricePerUnit * quantity;
  int get totalDuration => durationPerUnit * quantity;

  Map<String, dynamic> toBookingItem() => {
    'service_id':       serviceId,
    'price':            totalPrice,
    'quantity':         quantity,
    'duration_minutes': totalDuration,
  };
}

/// Global singleton cart — drives both the services grid and detail screen.
class CartService extends ChangeNotifier {
  CartService._();
  static final CartService instance = CartService._();

  // ── Service config ────────────────────────────────────────────
  // Full House is NOT in this map — it has no cart button.
  static const _config = <String, Map<String, dynamic>>{
    // 6 × 30min per-unit services
    'Bathroom Cleaning':  {'type': 'perUnit', 'duration': 30,  'maxQty': 6,  'price': 149},
    'Utensil Cleaning':   {'type': 'perUnit', 'duration': 30,  'maxQty': 1,  'price': 129},
    'Fan Cleaning':       {'type': 'perUnit', 'duration': 30,  'maxQty': 10, 'price': 49},
    'Sweeping & Mopping': {'type': 'perUnit', 'duration': 30,  'maxQty': 1,  'price': 129},
    'Dusting & Wiping':   {'type': 'perUnit', 'duration': 30,  'maxQty': 1,  'price': 129},
    'Balcony Cleaning':   {'type': 'perUnit', 'duration': 30,  'maxQty': 4,  'price': 129},
    // Fixed duration services (add once only)
    'Kitchen Cleaning':         {'type': 'fixed', 'duration': 60,  'maxQty': 1, 'price': 149},
    'Refrigerator Cleaning':    {'type': 'fixed', 'duration': 60,  'maxQty': 1, 'price': 249},
    'Wardrobe Cleaning':        {'type': 'fixed', 'duration': 150, 'maxQty': 1, 'price': 349},
    'Kitchen Cabinet Cleaning': {'type': 'fixed', 'duration': 180, 'maxQty': 1, 'price': 599},
    'Pre-Party Cleaning':       {'type': 'fixed', 'duration': 120, 'maxQty': 1, 'price': 299},
    'After-Party Cleanup':      {'type': 'fixed', 'duration': 120, 'maxQty': 1, 'price': 379},
    // Hourly service — each unit = 60min, max 4 units (240min)
    'Hourly Cleaning':          {'type': 'hourly', 'duration': 60, 'maxQty': 4, 'price': 99},
  };

  // Total cart duration cap in minutes (except hourly which has own cap)
  static const int cartMaxMins = 180;

  static bool isCartable(String name) => _config.containsKey(name);

  static CartItemType typeOf(String name) {
    final t = _config[name]?['type'] as String? ?? 'fixed';
    switch (t) {
      case 'perUnit': return CartItemType.perUnit;
      case 'hourly':  return CartItemType.hourly;
      default:        return CartItemType.fixed;
    }
  }

  static int maxQtyFor(String name)     => (_config[name]?['maxQty']   as int?) ?? 1;
  static int durationFor(String name)   => (_config[name]?['duration'] as int?) ?? 60;
  static int defaultPriceFor(String name) => (_config[name]?['price'] as int?) ?? 0;

  // ── State ─────────────────────────────────────────────────────
  final Map<String, CartItem> _items = {};

  List<CartItem> get items           => _items.values.toList();
  int  get count                     => _items.length;
  int  get totalQuantity             => _items.values.fold(0, (s, i) => s + i.quantity);
  bool get isEmpty                   => _items.isEmpty;
  bool get isNotEmpty                => _items.isNotEmpty;
  int  get totalPrice                => _items.values.fold(0, (s, i) => s + i.totalPrice);
  int  get totalDurationMins         => _items.values.fold(0, (s, i) => s + i.totalDuration);

  bool contains(String serviceId)    => _items.containsKey(serviceId);
  int  quantityOf(String serviceId)  => _items[serviceId]?.quantity ?? 0;

  // ── Can we add more? (respects 180min cap) ───────────────────
  bool canAdd(String name, {int addDuration = 0}) {
    final dur = addDuration > 0 ? addDuration : durationFor(name);
    // Hourly bypasses cart cap (has its own 240min cap)
    if (typeOf(name) == CartItemType.hourly) return true;
    return totalDurationMins + dur <= cartMaxMins;
  }

  // ── Mutations ─────────────────────────────────────────────────

  /// Add 1 unit — respects maxQty and cartMaxMins cap.
  /// Returns true if added, false if blocked.
  bool increment(CartItem template) {
    final name = template.serviceName;
    final dur  = template.durationPerUnit;

    if (_items.containsKey(template.serviceId)) {
      final item = _items[template.serviceId]!;
      if (item.quantity >= item.maxQty) return false;
      // Check total duration cap (skip for hourly)
      if (item.type != CartItemType.hourly && !canAdd(name, addDuration: dur)) return false;
      item.quantity++;
    } else {
      // Check total duration cap before adding new item
      if (template.type != CartItemType.hourly && !canAdd(name, addDuration: dur)) return false;
      _items[template.serviceId] = CartItem(
        serviceId:       template.serviceId,
        serviceName:     name,
        pricePerUnit:    template.pricePerUnit,
        durationPerUnit: dur,
        emoji:           template.emoji,
        maxQty:          template.maxQty,
        type:            template.type,
        quantity:        1,
      );
    }
    notifyListeners();
    return true;
  }

  /// Remove 1 unit — removes item entirely when qty reaches 0.
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