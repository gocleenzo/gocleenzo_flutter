import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../utils/theme.dart';
import 'booking_detail_screen.dart';

/// Pass either [cartItems] (multi-service) or [serviceId] (single service)
class BookScreen extends StatefulWidget {
  final List<Map<String, dynamic>>? cartItems;
  final String? serviceId;

  const BookScreen({super.key, this.cartItems, this.serviceId});

  @override
  State<BookScreen> createState() => _BookScreenState();
}

class _BookScreenState extends State<BookScreen> {
  final _supabase = Supabase.instance.client;

  List<Map<String, dynamic>> _addresses = [];
  Map<String, dynamic>? _service;
  int _step = 1;
  DateTime _selectedDate = DateTime.now();
  String _selectedTime = '';
  String _selectedAddressId = '';
  String _promoCode = '';
  bool _promoApplied = false;
  int _discount = 0;
  String _notes = '';
  bool _loading = false;
  bool _promoLoading = false;

  static const _timeSlots = [
    '07:00 AM', '08:00 AM', '09:00 AM', '10:00 AM', '11:00 AM',
    '12:00 PM', '01:00 PM', '02:00 PM', '03:00 PM',
    '04:00 PM', '05:00 PM', '06:00 PM', '07:00 PM',
  ];

  static const _slotLabels = {
    '07:00 AM': 'Early Morning', '08:00 AM': 'Early Morning',
    '09:00 AM': 'Morning', '10:00 AM': 'Mid Morning', '11:00 AM': 'Late Morning',
    '12:00 PM': 'Noon', '01:00 PM': 'Afternoon',
    '02:00 PM': 'Afternoon', '03:00 PM': 'Late Afternoon',
    '04:00 PM': 'Evening', '05:00 PM': 'Evening',
    '06:00 PM': 'Late Evening', '07:00 PM': 'Late Evening',
  };

  List<DateTime> get _dates =>
      List.generate(7, (i) => DateTime.now().add(Duration(days: i)));

  int get _baseAmount {
    if (widget.cartItems != null) {
      return widget.cartItems!.fold(0, (s, c) =>
          s + ((c['price'] as num).toInt() * (c['quantity'] as num).toInt()));
    }
    return (_service?['base_price'] as num?)?.toInt() ?? 0;
  }

  int get _finalAmount => _baseAmount - _discount;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    final futures = <Future>[
      _supabase.from('addresses').select('*').eq('user_id', user.id),
    ];
    if (widget.serviceId != null) {
      futures.add(_supabase
          .from('services')
          .select('id,name,base_price,duration_minutes')
          .eq('id', widget.serviceId!)
          .single());
    }

    final results = await Future.wait(futures);
    if (!mounted) return;

    setState(() {
      _addresses = (results[0] as List).cast<Map<String, dynamic>>();
      if (_addresses.isNotEmpty) {
        final def = _addresses.firstWhere(
            (a) => a['is_default'] == true,
            orElse: () => _addresses.first);
        _selectedAddressId = def['id'];
      }
      if (widget.serviceId != null && results.length > 1) {
        _service = results[1] as Map<String, dynamic>;
      }
    });
  }

  Future<void> _applyPromo() async {
    if (_promoCode.isEmpty || _promoApplied) return;
    setState(() => _promoLoading = true);
    final data = await _supabase
        .from('promo_codes')
        .select('*')
        .eq('code', _promoCode.toUpperCase())
        .eq('is_active', true)
        .maybeSingle();
    if (!mounted) return;
    setState(() => _promoLoading = false);
    if (data == null) {
      _showError('Invalid or expired promo code');
      return;
    }
    final disc = data['discount_type'] == 'flat'
        ? (data['discount_value'] as num).toInt()
        : ((_baseAmount * (data['discount_value'] as num)) / 100)
            .floor()
            .clamp(0, (data['max_discount_amount'] as num?)?.toInt() ?? 9999);
    setState(() {
      _discount = disc;
      _promoApplied = true;
    });
  }

  Future<void> _confirmBooking() async {
    if (_selectedAddressId.isEmpty) {
      _showError('Please select an address');
      return;
    }
    if (_selectedTime.isEmpty) {
      _showError('Please select a time slot');
      return;
    }

    setState(() => _loading = true);

    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) context.go('/login');
      return;
    }

    final scheduledAt = _buildScheduledAt();
    final otp =
        (1000 + (DateTime.now().millisecondsSinceEpoch % 9000)).toString();

    try {
      if (widget.cartItems != null && widget.cartItems!.isNotEmpty) {
        // ── Multi-service cart booking ──────────────────────
        // Step 1: insert one booking row (no service_id — multiple services)
        final booking = await _supabase.from('bookings').insert({
          'customer_id': user.id,
          'address_id': _selectedAddressId,
          'scheduled_at': scheduledAt.toIso8601String(),
          'status': 'pending',
          'base_price': _baseAmount,
          'discount_amount': _discount,
          'final_amount': _finalAmount,
          'special_instructions': _notes.isEmpty ? null : _notes,
          'payment_status': 'pending',
          'otp': otp,
        }).select().single();

        final bookingId = booking['id'] as String;

        // Step 2: insert one row per service into booking_items
        // Safe int conversion handles both int and double from Supabase
        try {
          final items = widget.cartItems!.map((c) {
            final unitPrice = (c['price'] as num).toInt();
            final qty       = (c['quantity'] as num).toInt();
            return {
              'booking_id':   bookingId,
              'service_id':   c['service_id'] as String,
              'quantity':     qty,
              'unit_price':   unitPrice,
              'total_price':  unitPrice * qty,
            };
          }).toList();
          await _supabase.from('booking_items').insert(items);
        } catch (itemsError) {
          // booking_items table may not exist in all setups — log but don't fail
          debugPrint('booking_items insert skipped: $itemsError');
        }

        if (mounted) {
          setState(() => _loading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BookingDetailScreen(bookingId: bookingId, isNew: true),
            ),
          );
        }
      } else {
        // ── Single service booking ──────────────────────────
        final booking = await _supabase.from('bookings').insert({
          'customer_id': user.id,
          'service_id': widget.serviceId,
          'address_id': _selectedAddressId,
          'scheduled_at': scheduledAt.toIso8601String(),
          'status': 'pending',
          'base_price': _baseAmount,
          'discount_amount': _discount,
          'final_amount': _finalAmount,
          'special_instructions': _notes.isEmpty ? null : _notes,
          'payment_status': 'pending',
          'otp': otp,
        }).select().single();

        if (mounted) {
          setState(() => _loading = false);
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BookingDetailScreen(
                  bookingId: booking['id'] as String, isNew: true),
            ),
          );
        }
      }
    } catch (e, stack) {
      debugPrint('Booking failed: $e\n$stack');
      if (mounted) {
        setState(() => _loading = false);
        _showError('Booking failed: ${e.toString().split('\n').first}');
      }
    }
  }

  DateTime _buildScheduledAt() {
    final parts = _selectedTime.split(' ');
    final timePart = parts[0];
    final meridiem = parts[1];
    final timeParts = timePart.split(':');
    int hh = int.parse(timeParts[0]);
    final mm = int.parse(timeParts[1]);
    if (meridiem == 'PM' && hh != 12) hh += 12;
    if (meridiem == 'AM' && hh == 12) hh = 0;
    return DateTime(
        _selectedDate.year, _selectedDate.month, _selectedDate.day, hh, mm);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Colors.red));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      body: Column(
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 160),
              child: Column(
                children: [
                  if (_step == 1) ...[
                    _buildDatePicker(),
                    const SizedBox(height: 16),
                    _buildTimePicker()
                  ],
                  if (_step == 2) ...[
                    _buildAddressPicker(),
                    const SizedBox(height: 16),
                    _buildNotesInput()
                  ],
                  if (_step == 3) ...[
                    _buildSummary(),
                    const SizedBox(height: 16),
                    _buildPromoInput(),
                    const SizedBox(height: 16),
                    _buildPriceBreakdown()
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    const steps = ['Date & Time', 'Address', 'Confirm'];
    final progress = _step == 1 ? 0.1 : _step == 2 ? 0.55 : 1.0;

    return Container(
      decoration: const BoxDecoration(
        gradient:
            LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Colors.white, size: 18),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('📅 Schedule Booking',
                            style: TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w900)),
                        Text(
                          widget.cartItems != null
                              ? '${widget.cartItems!.length} services'
                              : (_service?['name'] ?? ''),
                          style:
                              const TextStyle(color: Color(0xFFBAE6FD), fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Text('Total',
                          style: TextStyle(
                              color: Color(0xFFBAE6FD),
                              fontSize: 10,
                              fontWeight: FontWeight.w600)),
                      Text('₹$_finalAmount',
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 20,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: List.generate(steps.length, (i) {
                  final s = i + 1;
                  final active = _step == s;
                  final done = _step > s;
                  return Expanded(
                    child: Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: done || active
                                ? Colors.white
                                : Colors.white.withOpacity(0.25),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(done ? '✓' : '$s',
                                style: TextStyle(
                                    color: done || active
                                        ? AppTheme.primary
                                        : Colors.white.withOpacity(0.7),
                                    fontSize: 10,
                                    fontWeight: FontWeight.w900)),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                            child: Text(steps[i],
                                style: TextStyle(
                                    color: active
                                        ? Colors.white
                                        : Colors.white.withOpacity(
                                            done ? 0.8 : 0.5),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600),
                                overflow: TextOverflow.ellipsis)),
                        if (i < steps.length - 1)
                          Expanded(
                              child: Container(
                                  height: 1,
                                  color: Colors.white
                                      .withOpacity(done ? 0.6 : 0.2),
                                  margin: const EdgeInsets.symmetric(
                                      horizontal: 4))),
                      ],
                    ),
                  );
                }),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: progress,
                  backgroundColor: Colors.white.withOpacity(0.2),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(Colors.white),
                  minHeight: 6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDatePicker() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                _SectionIcon(icon: Icons.calendar_month_rounded),
                SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Choose Date',
                      style: TextStyle(
                          fontWeight: FontWeight.w800, fontSize: 14)),
                  Text('Select your preferred date',
                      style: TextStyle(
                          color: Color(0xFF9CA3AF), fontSize: 12)),
                ]),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          SizedBox(
            height: 90,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
              itemCount: _dates.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final d = _dates[i];
                final active = d.year == _selectedDate.year &&
                    d.month == _selectedDate.month &&
                    d.day == _selectedDate.day;
                return GestureDetector(
                  onTap: () => setState(() => _selectedDate = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 58,
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.primary
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                  color:
                                      AppTheme.primary.withOpacity(0.45),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4))
                            ]
                          : [],
                      border: active
                          ? null
                          : Border.all(color: const Color(0xFFF0F0F0)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                            ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']
                                [d.weekday - 1],
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: active
                                    ? const Color(0xFFBAE6FD)
                                    : const Color(0xFF9CA3AF))),
                        Text('${d.day}',
                            style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                                color: active
                                    ? Colors.white
                                    : const Color(0xFF111827))),
                        Text(i == 0 ? 'TODAY' : '·',
                            style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                                color: active
                                    ? Colors.white
                                    : (i == 0
                                        ? AppTheme.primary
                                        : Colors.transparent))),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePicker() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)
          ]),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              _SectionIcon(icon: Icons.access_time_rounded),
              SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Choose Time',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                Text('Pick a convenient slot',
                    style: TextStyle(
                        color: Color(0xFF9CA3AF), fontSize: 12)),
              ]),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 3,
              childAspectRatio: 1.8,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              children: _timeSlots.map((slot) {
                final active = _selectedTime == slot;
                return GestureDetector(
                  onTap: () => setState(() => _selectedTime = slot),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      color: active
                          ? AppTheme.primary
                          : const Color(0xFFF9FAFB),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: active
                          ? [
                              BoxShadow(
                                  color: AppTheme.primary.withOpacity(0.4),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4))
                            ]
                          : [],
                      border: active
                          ? null
                          : Border.all(color: const Color(0xFFF0F0F0)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(slot,
                            style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w900,
                                color: active
                                    ? Colors.white
                                    : const Color(0xFF111827))),
                        Text(_slotLabels[slot] ?? '',
                            style: TextStyle(
                                fontSize: 9,
                                color: active
                                    ? const Color(0xFFBAE6FD)
                                    : const Color(0xFF9CA3AF))),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddressPicker() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)
          ]),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(
              children: [
                const _SectionIcon(icon: Icons.location_on_rounded),
                const SizedBox(width: 12),
                const Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Service Address',
                          style: TextStyle(
                              fontWeight: FontWeight.w800, fontSize: 14)),
                      Text('Where should we come?',
                          style: TextStyle(
                              color: Color(0xFF9CA3AF), fontSize: 12)),
                    ])),
                GestureDetector(
                  onTap: () => Navigator.pushNamed(context, '/account'),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                        color: const Color(0xFFECFEFF),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFA5F3FC))),
                    child: const Text('+ Add',
                        style: TextStyle(
                            color: AppTheme.primary,
                            fontSize: 12,
                            fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.all(16),
            child: _addresses.isEmpty
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Column(children: [
                      Text('📍', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 12),
                      Text('No saved addresses',
                          style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF374151))),
                      Text('Add an address to continue',
                          style: TextStyle(
                              color: Color(0xFF9CA3AF), fontSize: 13)),
                    ]),
                  )
                : Column(
                    children: _addresses.map((addr) {
                      final active = _selectedAddressId == addr['id'];
                      final icon = addr['label'] == 'Home'
                          ? '🏠'
                          : addr['label'] == 'Office'
                              ? '🏢'
                              : '📍';
                      return GestureDetector(
                        onTap: () =>
                            setState(() => _selectedAddressId = addr['id']),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: active
                                ? const Color(0xFFECFEFF)
                                : const Color(0xFFF9FAFB),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                                color: active
                                    ? AppTheme.primary
                                    : const Color(0xFFF0F0F0),
                                width: active ? 2 : 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(
                                    color: Colors.white,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                        color: const Color(0xFFE5E7EB))),
                                child: Center(
                                    child: Text(icon,
                                        style: const TextStyle(fontSize: 20))),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Row(children: [
                                      Text(addr['label'] ?? 'Address',
                                          style: const TextStyle(
                                              fontWeight: FontWeight.w800,
                                              fontSize: 14)),
                                      if (addr['is_default'] == true) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                                color:
                                                    const Color(0xFFECFEFF),
                                                borderRadius:
                                                    BorderRadius.circular(20)),
                                            child: const Text('Default',
                                                style: TextStyle(
                                                    color: AppTheme.primary,
                                                    fontSize: 10,
                                                    fontWeight:
                                                        FontWeight.bold))),
                                      ],
                                    ]),
                                    const SizedBox(height: 2),
                                    Text(
                                      [
                                        if (addr['flat_no'] != null)
                                          addr['flat_no'],
                                        if (addr['building'] != null)
                                          addr['building'],
                                        addr['area'],
                                        addr['city'],
                                      ]
                                          .where((e) => e != null)
                                          .join(', '),
                                      style: const TextStyle(
                                          color: Color(0xFF6B7280),
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                width: 24,
                                height: 24,
                                decoration: BoxDecoration(
                                  color: active
                                      ? AppTheme.primary
                                      : Colors.transparent,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                      color: active
                                          ? AppTheme.primary
                                          : const Color(0xFFD1D5DB),
                                      width: 2),
                                ),
                                child: active
                                    ? const Icon(Icons.check,
                                        color: Colors.white, size: 14)
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotesInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            _SectionIcon(icon: Icons.chat_bubble_outline_rounded),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Special Instructions',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              Text('Optional notes for the cleaner',
                  style:
                      TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 16),
          TextField(
            maxLines: 3,
            onChanged: (v) => _notes = v,
            decoration: InputDecoration(
              hintText:
                  'e.g. Ring bell twice, pet at home, focus on bathroom tiles...',
              hintStyle:
                  const TextStyle(color: Color(0xFF9CA3AF), fontSize: 13),
              filled: true,
              fillColor: const Color(0xFFF9FAFB),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFFF0F0F0))),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide:
                      const BorderSide(color: Color(0xFFF0F0F0))),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                  borderSide: BorderSide(
                      color: AppTheme.primary.withOpacity(0.5))),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary() {
    final addr = _addresses.firstWhere(
        (a) => a['id'] == _selectedAddressId,
        orElse: () => {});
    final rows = [
      {
        'icon': '🧹',
        'label': 'Services',
        'value': widget.cartItems != null
            ? '${widget.cartItems!.length} services'
            : (_service?['name'] ?? '—')
      },
      {
        'icon': '📅',
        'label': 'Date',
        'value':
            '${_selectedDate.day}/${_selectedDate.month}/${_selectedDate.year}'
      },
      {'icon': '⏰', 'label': 'Time', 'value': _selectedTime},
      {
        'icon': '📍',
        'label': 'Address',
        'value': addr.isNotEmpty
            ? '${addr['area']}, ${addr['city']}'
            : '—'
      },
      if (_notes.isNotEmpty) {'icon': '💬', 'label': 'Notes', 'value': _notes},
    ];

    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)
          ]),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              _SectionIcon(icon: Icons.receipt_long_rounded),
              SizedBox(width: 12),
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Booking Summary',
                    style: TextStyle(
                        fontWeight: FontWeight.w800, fontSize: 14)),
                Text('Review your booking details',
                    style:
                        TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
              ]),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: rows
                  .map((row) => Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Row(
                          children: [
                            Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                    color: const Color(0xFFF3F4F6),
                                    borderRadius:
                                        BorderRadius.circular(12)),
                                child: Center(
                                    child: Text(row['icon']!,
                                        style: const TextStyle(
                                            fontSize: 16)))),
                            const SizedBox(width: 12),
                            Expanded(
                                child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(row['label']!,
                                    style: const TextStyle(
                                        color: Color(0xFF9CA3AF),
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        letterSpacing: 0.5)),
                                Text(row['value']!,
                                    style: const TextStyle(
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF111827))),
                              ],
                            )),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPromoInput() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)
          ]),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Text('🎟️', style: TextStyle(fontSize: 24)),
            SizedBox(width: 12),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Promo Code',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
              Text('Have a coupon? Save more!',
                  style:
                      TextStyle(color: Color(0xFF9CA3AF), fontSize: 12)),
            ]),
          ]),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: TextField(
                  enabled: !_promoApplied,
                  textCapitalization: TextCapitalization.characters,
                  onChanged: (v) =>
                      setState(() => _promoCode = v.toUpperCase()),
                  decoration: InputDecoration(
                    hintText: 'Enter code e.g. CLEAN20',
                    filled: true,
                    fillColor: const Color(0xFFF9FAFB),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: Color(0xFFF0F0F0))),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide:
                            const BorderSide(color: Color(0xFFF0F0F0))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(16),
                        borderSide: BorderSide(
                            color: AppTheme.primary.withOpacity(0.5))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: _promoApplied ? null : _applyPromo,
                child: Container(
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  decoration: BoxDecoration(
                    color: _promoApplied
                        ? const Color(0xFF10B981)
                        : AppTheme.primary,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                          color: AppTheme.primary.withOpacity(0.3),
                          blurRadius: 12)
                    ],
                  ),
                  child: Center(
                    child: _promoLoading
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2))
                        : Text(_promoApplied ? '✓' : 'Apply',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w900)),
                  ),
                ),
              ),
            ],
          ),
          if (_promoApplied)
            Container(
              margin: const EdgeInsets.only(top: 12),
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                  color: const Color(0xFFECFDF5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFA7F3D0))),
              child: Row(children: [
                const Text('✓ ',
                    style: TextStyle(color: Color(0xFF059669))),
                Text('Promo applied — you save ₹$_discount!',
                    style: const TextStyle(
                        color: Color(0xFF065F46),
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _buildPriceBreakdown() {
    return Container(
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.07), blurRadius: 12)
          ]),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 20, 20, 16),
            child: Row(children: [
              _SectionIcon(icon: Icons.receipt_outlined),
              SizedBox(width: 12),
              Text('Price Breakdown',
                  style: TextStyle(
                      fontWeight: FontWeight.w800, fontSize: 14)),
            ]),
          ),
          const Divider(height: 1, color: Color(0xFFF3F4F6)),
          Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                _priceRow('Service price', '₹$_baseAmount'),
                if (_discount > 0)
                  _priceRow('Discount ($_promoCode)', '− ₹$_discount',
                      color: const Color(0xFF10B981)),
                _priceRow('Platform fee', 'FREE',
                    color: const Color(0xFF10B981)),
                const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Divider(color: Color(0xFFF3F4F6))),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Total amount',
                        style: TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 16)),
                    Text('₹$_finalAmount',
                        style: const TextStyle(
                            color: AppTheme.primary,
                            fontSize: 24,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                      color: const Color(0xFFECFEFF),
                      borderRadius: BorderRadius.circular(12),
                      border:
                          Border.all(color: const Color(0xFFA5F3FC))),
                  child: const Row(children: [
                    Text('✅', style: TextStyle(fontSize: 18)),
                    SizedBox(width: 10),
                    Expanded(
                        child: Text(
                            'Your booking will be confirmed instantly. Our team will reach out shortly.',
                            style: TextStyle(
                                color: Color(0xFF0E7490),
                                fontSize: 12,
                                fontWeight: FontWeight.w600))),
                  ]),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: const TextStyle(
                  color: Color(0xFF6B7280), fontSize: 14)),
          Text(value,
              style: TextStyle(
                  color: color ?? const Color(0xFF111827),
                  fontSize: 14,
                  fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildBottomBar() {
    final canProceed =
        !(_step == 1 && _selectedTime.isEmpty) &&
            !(_step == 2 && _selectedAddressId.isEmpty);

    return Container(
      padding: EdgeInsets.fromLTRB(
          16, 12, 16, 16 + MediaQuery.of(context).padding.bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFF3F4F6))),
        boxShadow: [
          BoxShadow(
              color: Color(0x1A000000),
              blurRadius: 24,
              offset: Offset(0, -8))
        ],
      ),
      child: Row(
        children: [
          if (_step > 1)
            GestureDetector(
              onTap: () => setState(() => _step--),
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(16)),
                child: const Icon(Icons.arrow_back_ios_new,
                    color: Color(0xFF6B7280), size: 20),
              ),
            ),
          if (_step > 1) const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: canProceed && !_loading
                  ? () {
                      if (_step < 3) {
                        setState(() => _step++);
                      } else {
                        _confirmBooking();
                      }
                    }
                  : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                height: 56,
                decoration: BoxDecoration(
                  gradient: canProceed
                      ? const LinearGradient(colors: [
                          Color(0xFF06B6D4),
                          Color(0xFF0891B2)
                        ])
                      : null,
                  color: canProceed ? null : const Color(0xFFE5E7EB),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: canProceed
                      ? [
                          BoxShadow(
                              color: AppTheme.primary.withOpacity(0.45),
                              blurRadius: 20,
                              offset: const Offset(0, 6))
                        ]
                      : [],
                ),
                child: Center(
                  child: _loading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2.5))
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _step == 3
                                  ? 'Confirm Booking'
                                  : 'Continue',
                              style: TextStyle(
                                  color: canProceed
                                      ? Colors.white
                                      : const Color(0xFF9CA3AF),
                                  fontSize: 16,
                                  fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(width: 8),
                            Icon(
                                _step == 3
                                    ? Icons.check
                                    : Icons.arrow_forward,
                                color: canProceed
                                    ? Colors.white
                                    : const Color(0xFF9CA3AF),
                                size: 20),
                          ],
                        ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionIcon extends StatelessWidget {
  final IconData icon;
  const _SectionIcon({required this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
          color: AppTheme.primary,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
                color: AppTheme.primary.withOpacity(0.3), blurRadius: 8)
          ]),
      child: Icon(icon, color: Colors.white, size: 18),
    );
  }
}