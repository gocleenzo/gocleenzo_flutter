import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:razorpay_flutter/razorpay_flutter.dart';
import '../../services/supabase_service.dart';

/// Weekly recurring package booking — 7 consecutive days of the SAME
/// service at the SAME time, handled by the SAME worker, paid in full
/// upfront.
///
/// STEP ORDER (fixed): Address -> Date & Time -> Confirm. Address MUST
/// come first because the availability check (check_recurring_availability)
/// requires an address_id to run at all — putting date/time first left
/// the "Check availability" button silently doing nothing whenever
/// _selectedAddressId was still empty, which was always the case before
/// this fix since address selection used to be step 2.
///
/// Note: the first-booking ₹25 offer does NOT apply to packages — the
/// full per-visit price is always charged (product decision).
class RecurringBookingScreen extends StatefulWidget {
  final String serviceId;
  final String serviceName;
  final int pricePerVisit;
  final int durationMins;

  const RecurringBookingScreen({
    super.key,
    required this.serviceId,
    required this.serviceName,
    required this.pricePerVisit,
    required this.durationMins,
  });

  @override
  State<RecurringBookingScreen> createState() => _RecurringBookingScreenState();
}

class _RecurringBookingScreenState extends State<RecurringBookingScreen> {
  final _supabase = Supabase.instance.client;

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _cyanBg = Color(0xFFECFEFF);
  static const _cyanBg2 = Color(0xFFD6F6FB);
  static const _border = Color(0xFFE8EDF2);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _bg     = Color(0xFFF8FAFC);
  static const _green  = Color(0xFF10B981);
  static const _greenDk = Color(0xFF059669);
  static const _amber  = Color(0xFFD97706);

  // Same 30-min grid the rest of the app uses.
  static const _timeSlots = [
    '07:00','07:30','08:00','08:30','09:00','09:30','10:00','10:30',
    '11:00','11:30','12:00','12:30','13:00','13:30','14:00','14:30',
    '15:00','15:30','16:00','16:30','17:00','17:30','18:00','18:30','19:00',
  ];

  // 1 = address, 2 = date+time (availability check), 3 = confirm
  int _step = 1;
  bool _loading = false;
  bool _checking = false;
  String? _error;

  DateTime? _startDate;
  String _selectedTime = '';
  // Slot -> 'full' | 'partial' | 'none', fetched once whenever the start
  // date or address changes, so the time grid can show real availability
  // (matching the same greyed-out-slots pattern the regular booking flow
  // already uses) instead of showing all 25 slots as equally pickable
  // and only revealing problems after commit.
  Map<String, String> _slotGrid = {};
  bool _slotGridLoading = false;

  // Per-day alternate times chosen by the customer for days where the
  // standard time wasn't available: {dayNumber: 'HH:MM'}
  final Map<int, String> _dayOverrides = {};
  // Days (1..7) reported as conflicting by the availability check.
  List<Map<String, dynamic>> _conflicts = [];
  bool _availabilityChecked = false;
  bool _allDaysAvailable = false;
  // NEW: separately tracks whether the CURRENT set of day-overrides
  // (once all conflicts have one picked) has actually been confirmed
  // to work for a single worker — set by _verifyOverridesWork(),
  // reset to null whenever any override changes.
  bool? _overridesVerified;
  bool _verifyingOverrides = false;

  List<Map<String, dynamic>> _addresses = [];
  String _selectedAddressId = '';
  bool _addressesLoading = true;

  final _notesCtrl = TextEditingController();

  String? _userId;
  String? _userPhone;
  // Set in _startPayment, read in _onPaymentSuccess (a separate Razorpay
  // callback with no direct access to that method's local variables) —
  // needed to call complete_recurring_package_recovery with the SAME
  // attempt_ref the pending draft was saved under.
  String? _pendingAttemptRef;
  String? _userEmail;

  late Razorpay _razorpay;
  static const _razorpayKey = 'rzp_live_TJIl6FAZg8I1ru';
  static const _apiBaseUrl = 'https://gocleenzo-admin.vercel.app';
  // Same flat platform fee applied on every other booking in the app —
  // added here too so a recurring package is charged consistently with
  // a normal single booking, not treated as a special case.
  static const _platformFee = 10;

  int get _packageSubtotal => widget.pricePerVisit * 7;
  int get _totalAmount => _packageSubtotal + _platformFee;

  @override
  void initState() {
    super.initState();
    _razorpay = Razorpay();
    _razorpay.on(Razorpay.EVENT_PAYMENT_SUCCESS, _onPaymentSuccess);
    _razorpay.on(Razorpay.EVENT_PAYMENT_ERROR, _onPaymentError);
    _razorpay.on(Razorpay.EVENT_EXTERNAL_WALLET, _onExternalWallet);
    _loadData();
  }

  @override
  void dispose() {
    _razorpay.clear();
    _notesCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    _userId = await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (_userId == null) { if (mounted) context.go('/login'); return; }

    final addrData = await _supabase.from('addresses').select('*')
        .eq('user_id', _userId!).eq('is_deleted', false);
    final userData = await _supabase.from('users').select('phone, email')
        .eq('id', _userId!).maybeSingle();

    if (!mounted) return;
    setState(() {
      _addresses = (addrData as List).cast<Map<String, dynamic>>();
      if (_addresses.isNotEmpty) {
        final def = _addresses.firstWhere((a) => a['is_default'] == true,
            orElse: () => _addresses.first);
        _selectedAddressId = def['id'];
      }
      _addressesLoading = false;
      _userPhone = userData?['phone'] as String?;
      _userEmail = userData?['email'] as String?;
    });
  }

  String _dateStr(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _prettyDate(DateTime d) {
    const months = ['Jan','Feb','Mar','Apr','May','Jun',
        'Jul','Aug','Sep','Oct','Nov','Dec'];
    const days = ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'];
    return '${days[(d.weekday + 6) % 7]}, ${d.day} ${months[d.month - 1]}';
  }

  String _pretty12h(String hhmm) {
    final parts = hhmm.split(':');
    int h = int.parse(parts[0]);
    final m = parts[1];
    final ampm = h >= 12 ? 'PM' : 'AM';
    if (h > 12) h -= 12;
    if (h == 0) h = 12;
    return '$h:$m $ampm';
  }

  /// Runs the server-side all-7-days availability check. Requires
  /// _selectedAddressId to already be set — this is guaranteed now since
  /// address selection is Step 1, always completed before this can run.
  Future<void> _checkAvailability() async {
    if (_startDate == null || _selectedTime.isEmpty) return;
    if (_selectedAddressId.isEmpty) {
      // Defensive guard only — should be unreachable now that address is
      // step 1, but fail loudly instead of silently doing nothing if it
      // ever does happen (e.g. a future refactor reintroduces the bug).
      setState(() => _error = 'Please select an address first.');
      return;
    }
    setState(() { _checking = true; _error = null; _conflicts = []; });
    try {
      final result = await _supabase.rpc('check_recurring_availability', params: {
        'p_address_id':    _selectedAddressId,
        'p_start_date':    _dateStr(_startDate!),
        'p_time':          _selectedTime,
        'p_duration_mins': widget.durationMins,
      });
      debugPrint('RECURRING DEBUG: $result');
      final res = result as Map<String, dynamic>;
      if (!mounted) return;
      setState(() {
        _availabilityChecked = true;
        _allDaysAvailable = res['available'] == true;
        _conflicts = ((res['conflicts'] as List?) ?? [])
            .cast<Map<String, dynamic>>();
        _checking = false;
        if (res['reason'] == 'excluded_area') {
          _error = 'We don\'t serve this address yet.';
        } else if (!_allDaysAvailable && _conflicts.isEmpty) {
          _error = 'No professional is free at this time on all 7 days. '
                   'Try a different time or start date.';
        }
      });
    } catch (e) {
      debugPrint('recurring availability error: $e');
      if (mounted) {
        setState(() {
          _checking = false;
          _error = 'Could not check availability. Please try again.';
        });
      }
    }
  }

  /// Fetches real availability for every visible time slot in ONE call
  /// (get_recurring_slot_grid), so the picker can grey out/mark slots
  /// before the customer commits to a pick — instead of only finding out
  /// after tapping "Check availability" once. Called whenever the start
  /// date or address changes, since either changes which workers/days
  /// are actually relevant.
  Future<void> _loadSlotGrid() async {
    if (_startDate == null || _selectedAddressId.isEmpty) return;
    setState(() => _slotGridLoading = true);
    try {
      final result = await _supabase.rpc('get_recurring_slot_grid', params: {
        'p_address_id':    _selectedAddressId,
        'p_start_date':    _dateStr(_startDate!),
        'p_duration_mins': widget.durationMins,
      });
      if (!mounted) return;
      final list = result as List;
      final grid = <String, String>{};
      for (final entry in list) {
        final m = entry as Map<String, dynamic>;
        if (m['time'] != null) grid[m['time'] as String] = m['status'] as String? ?? 'none';
      }
      setState(() { _slotGrid = grid; _slotGridLoading = false; });
    } catch (e) {
      debugPrint('slot grid load error: $e');
      // Non-fatal — the picker just shows all slots as plain/unmarked if
      // this fails, and the real "Check availability" step after picking
      // still catches any actual problem correctly. This is purely a
      // UX pre-filter, not the source of truth.
      if (mounted) setState(() => _slotGridLoading = false);
    }
  }

  // Same-style horizontal date strip as the regular Schedule Booking flow
  // (booking_flow_screen.dart's _dates/_buildDateTimeStep) — 30 days
  // starting today, so a package can still be started any day within
  // roughly the same window the old date-picker dialog allowed (60 days),
  // just as a scrollable strip instead of a separate calendar dialog.
  List<DateTime> get _startDateOptions =>
      List.generate(30, (i) => DateTime.now().add(Duration(days: i)));

  void _pickStartDate(DateTime d) {
    setState(() {
      _startDate = d;
      _availabilityChecked = false;
      _conflicts = [];
      _dayOverrides.clear();
      _overridesVerified = null;
      _selectedTime = '';
      _slotGrid = {};
    });
    HapticFeedback.selectionClick();
    _loadSlotGrid();
  }

  bool get _canProceedFromAddressStep => _selectedAddressId.isNotEmpty;

  bool get _canProceedFromDateTimeStep {
    if (_startDate == null || _selectedTime.isEmpty || !_availabilityChecked) {
      return false;
    }
    final allConflictsResolved =
        _conflicts.every((c) => _dayOverrides.containsKey(c['day'] as int));

    if (!allConflictsResolved) return false;

    // No conflicts at all — the original all-days-standard-time check
    // already confirmed a single worker covers everything.
    if (_conflicts.isEmpty) return _allDaysAvailable;

    // Conflicts existed and were "resolved" with overrides — this is
    // ONLY actually safe to proceed on once verify_recurring_package_
    // with_overrides has confirmed a single worker can cover the
    // resulting mixed schedule. This is the fix for payments
    // succeeding and then failing/refunding every time for
    // combinations that could never have worked (check_recurring_
    // availability's own conflict list is built by checking each
    // conflicting day INDEPENDENTLY — any worker, standard time only —
    // it never verifies a SINGLE worker can cover the whole 7-day
    // schedule once overrides are applied; only
    // create_recurring_package used to check that, AFTER payment).
    return _overridesVerified == true;
  }

  /// Runs once every conflicting day has an override picked — confirms
  /// a SINGLE worker can actually cover the full 7-day schedule with
  /// this exact mix of standard + override times, instead of trusting
  /// "every conflict has some time picked" as if that were sufficient.
  Future<void> _verifyOverridesWork() async {
    if (_startDate == null || _selectedTime.isEmpty) return;
    final unresolved = _conflicts.where(
        (c) => !_dayOverrides.containsKey(c['day'] as int)).length;
    if (unresolved > 0) {
      // Not all conflicts resolved yet — nothing to verify.
      setState(() => _overridesVerified = null);
      return;
    }
    setState(() => _verifyingOverrides = true);
    try {
      final overrides = _dayOverrides.entries
          .map((e) => {'day': e.key, 'time': e.value}).toList();
      final result = await _supabase.rpc(
          'verify_recurring_package_with_overrides', params: {
        'p_address_id':     _selectedAddressId,
        'p_start_date':     _dateStr(_startDate!),
        'p_time':           _selectedTime,
        'p_duration_mins':  widget.durationMins,
        'p_day_overrides':  overrides,
      });
      if (!mounted) return;
      final res = result as Map<String, dynamic>;
      setState(() {
        _overridesVerified = res['available'] == true;
        _verifyingOverrides = false;
      });
    } catch (e) {
      debugPrint('verify overrides error: $e');
      if (mounted) {
        // Fail closed — if we can't confirm it works, don't let the
        // customer pay for a combination we're not sure about.
        setState(() { _overridesVerified = false; _verifyingOverrides = false; });
      }
    }
  }

  // ── Payment ────────────────────────────────────────────────────
  Future<void> _startPayment() async {
    if (_selectedAddressId.isEmpty) {
      setState(() => _error = 'Please select an address'); return;
    }
    setState(() { _loading = true; _error = null; });

    final attemptRef = 'pkg_${DateTime.now().millisecondsSinceEpoch}';
    _pendingAttemptRef = attemptRef;
    String orderId;
    try {
      final resp = await http.post(
        Uri.parse('$_apiBaseUrl/api/payments/order'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'amount': _totalAmount * 100,
          'currency': 'INR',
          'receipt': attemptRef,
        }),
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200) throw 'Order creation failed';
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      orderId = data['order_id'] as String;
    } catch (e) {
      debugPrint('package order error: $e');
      if (mounted) {
        setState(() { _loading = false; _error = 'Could not start payment. Please try again.'; });
      }
      return;
    }

    if (!mounted) return;
    setState(() => _loading = false);

    // Save a full draft of this package attempt BEFORE opening Razorpay
    // checkout — mirrors the exact same safety net already built for
    // regular bookings. If the app is killed/backgrounded right after
    // Razorpay confirms payment but before create_recurring_package()
    // finishes, this draft is what the server-side webhook uses to
    // complete the package on its own instead of silently losing a
    // captured payment. Non-fatal by design — a failure here never
    // blocks the actual payment flow.
    try {
      final overrides = _dayOverrides.entries
          .map((e) => {'day': e.key, 'time': e.value}).toList();
      await _supabase.rpc('create_pending_recurring_package', params: {
        'p_attempt_ref':           attemptRef,
        'p_customer_id':           _userId,
        'p_address_id':            _selectedAddressId,
        'p_service_id':            widget.serviceId,
        'p_start_date':            _dateStr(_startDate!),
        'p_time_of_day':           _selectedTime,
        'p_duration_mins':         widget.durationMins,
        'p_price_per_visit':       widget.pricePerVisit,
        'p_total_amount':          _totalAmount,
        'p_day_overrides':         overrides,
        'p_special_instructions':  _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
      });
    } catch (e) {
      debugPrint('create_pending_recurring_package failed (non-fatal): $e');
    }

    try {
      _razorpay.open({
        'key': _razorpayKey,
        'order_id': orderId,
        'amount': _totalAmount * 100,
        'name': 'Cleenzo',
        'description': 'Weekly Package — ${widget.serviceName} (7 visits)',
        'prefill': {'contact': _userPhone ?? '', 'email': _userEmail ?? ''},
        'notes': {'attempt_ref': attemptRef, 'customer_id': _userId ?? '', 'type': 'recurring_package'},
        'theme': {'color': '#06B6D4'},
        'method': {
          'upi': true, 'netbanking': true,
          'card': true, 'wallet': true,
          'emi': false, 'cardless_emi': false, 'paylater': false,
        },
        // No 'flow' override — lets Razorpay's checkout show ALL UPI
        // options (QR code, UPI ID, app intent) instead of forcing
        // straight into the app-chooser and hiding the QR tab.
      });
    } catch (e) {
      setState(() { _loading = false; _error = 'Could not open payment.'; });
    }
  }

  Future<void> _onPaymentSuccess(PaymentSuccessResponse response) async {
    if (!mounted) return;
    setState(() => _loading = true);

    final paymentId = response.paymentId;
    if (paymentId == null) {
      setState(() { _loading = false; _error = 'Payment confirmation incomplete. Contact support if charged.'; });
      return;
    }

    // Verify signature server-side before trusting this callback.
    try {
      final verifyResp = await http.post(
        Uri.parse('$_apiBaseUrl/api/payments/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'razorpay_order_id':   response.orderId,
          'razorpay_payment_id': response.paymentId,
          'razorpay_signature':  response.signature,
        }),
      ).timeout(const Duration(seconds: 20));
      final vd = jsonDecode(verifyResp.body) as Map<String, dynamic>;
      if (vd['verified'] != true) {
        await _refund(paymentId, 'signature_verification_failed');
        if (mounted) {
          setState(() { _loading = false; _error = 'Payment could not be verified. It has been refunded.'; });
        }
        return;
      }
    } catch (e) {
      await _refund(paymentId, 'verification_request_failed');
      if (mounted) {
        setState(() { _loading = false; _error = 'Could not confirm payment. It has been refunded.'; });
      }
      return;
    }

    try {
      // Goes through the SAME locked recovery function the server-side
      // webhook also uses (complete_recurring_package_recovery), instead
      // of calling create_recurring_package directly. If this app
      // callback and the webhook ever fired close together (e.g. slow
      // network right as the app resumes), calling create_recurring_package
      // independently in each place could create TWO packages for one
      // payment. Routing both through the same row-locked function means
      // whichever gets there first wins, and the other cleanly sees
      // 'already_completed' and does nothing.
      final recovery = await _supabase.rpc('complete_recurring_package_recovery', params: {
        'p_attempt_ref': _pendingAttemptRef,
        'p_payment_id':  paymentId,
      });
      final recoveryResult = recovery as Map<String, dynamic>;
      final action = recoveryResult['action'] as String?;

      if (action == 'package_created' || action == 'already_completed') {
        setState(() => _loading = false);
        _showSuccessDialog();
        return;
      }

      if (action == 'needs_refund') {
        await _refund(paymentId, recoveryResult['reason']?.toString() ?? 'package_creation_failed');
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = 'Those slots were just taken. Your payment has been '
                   'refunded — please pick a different time.';
        });
        return;
      }

      if (action == 'no_draft_found') {
        // The draft save before payment silently failed (non-fatal by
        // design) — fall back to the direct path so the customer isn't
        // stuck just because that bookkeeping insert had a hiccup.
        final overrides = _dayOverrides.entries
            .map((e) => {'day': e.key, 'time': e.value}).toList();
        final result = await _supabase.rpc('create_recurring_package', params: {
          'p_customer_id':          _userId,
          'p_address_id':           _selectedAddressId,
          'p_service_id':           widget.serviceId,
          'p_start_date':           _dateStr(_startDate!),
          'p_time':                 _selectedTime,
          'p_duration_mins':        widget.durationMins,
          'p_price_per_visit':      widget.pricePerVisit,
          'p_total_amount':         _totalAmount,
          'p_payment_id':           paymentId,
          'p_day_overrides':        overrides,
          'p_special_instructions': _notesCtrl.text.isEmpty ? null : _notesCtrl.text,
        });
        if (!mounted) return;
        final res = result as Map<String, dynamic>;
        if (res['success'] != true) {
          await _refund(paymentId, res['reason']?.toString() ?? 'package_creation_failed');
          if (!mounted) return;
          setState(() {
            _loading = false;
            _error = 'Those slots were just taken. Your payment has been '
                     'refunded — please pick a different time.';
          });
          return;
        }
        setState(() => _loading = false);
        _showSuccessDialog();
        return;
      }

      // 'error' or any unexpected action — treat as a genuine failure.
      throw Exception('Recovery RPC returned unexpected action: $action');
    } catch (e) {
      debugPrint('package creation error: $e');
      await _refund(paymentId, 'package_creation_error');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Something went wrong creating your package. Your payment '
                 'has been refunded — please try again.';
      });
    }
  }

  void _onPaymentError(PaymentFailureResponse response) {
    if (mounted) {
      setState(() {
        _loading = false;
        _error = 'Payment failed: ${response.message ?? "Please try again"}';
      });
    }
  }

  void _onExternalWallet(ExternalWalletResponse response) {}

  Future<void> _refund(String paymentId, String reason) async {
    try {
      final resp = await http.post(
        Uri.parse('$_apiBaseUrl/api/payments/refund'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'payment_id': paymentId, 'reason': reason}),
      ).timeout(const Duration(seconds: 20));
      if (resp.statusCode != 200 && mounted) {
        setState(() => _error =
            'Could not auto-refund. Please contact support with payment ID: $paymentId');
      }
    } catch (e) {
      debugPrint('package refund failed: $e');
      if (mounted) {
        setState(() => _error =
            'Could not auto-refund. Please contact support with payment ID: $paymentId');
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.white,
        insetPadding: const EdgeInsets.symmetric(horizontal: 32),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 64, height: 64,
              decoration: const BoxDecoration(color: Color(0xFFECFDF5), shape: BoxShape.circle),
              child: const Center(child: Text('🎉', style: TextStyle(fontSize: 32)))),
            const SizedBox(height: 16),
            const Text('Weekly Package Confirmed!',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: _ink)),
            const SizedBox(height: 10),
            Text('All 7 visits are booked with the same professional, '
                 'starting ${_prettyDate(_startDate!)}.',
                textAlign: TextAlign.center,
                style: const TextStyle(color: _muted, fontSize: 13.5, height: 1.5)),
            const SizedBox(height: 20),
            GestureDetector(
              onTap: () {
                Navigator.pop(ctx);
                context.go('/bookings');
              },
              child: Container(
                width: double.infinity, height: 50, alignment: Alignment.center,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                  borderRadius: BorderRadius.circular(14)),
                child: const Text('View My Bookings',
                    style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900)))),
          ]),
        ),
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [
        _buildHeader(),
        Expanded(child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 130),
          child: _step == 1 ? _buildAddressStep()
               : _step == 2 ? _buildDateTimeStep()
               : _buildConfirmStep(),
        )),
      ]),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    const stepLabels = ['Address', 'Date & Time', 'Confirm'];
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: _border))),
      child: SafeArea(bottom: false, child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
        child: Row(children: [
          GestureDetector(
            onTap: () {
              if (_step > 1) { setState(() => _step--); }
              else { Navigator.pop(context); }
            },
            child: Container(
              width: 40, height: 40,
              decoration: BoxDecoration(color: _cyanBg, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.arrow_back_ios_new_rounded, color: _cyanDk, size: 16))),
          const SizedBox(width: 12),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.repeat_rounded, color: _cyanDk, size: 18),
              SizedBox(width: 6),
              Text('Weekly Package',
                  style: TextStyle(color: _ink, fontSize: 17, fontWeight: FontWeight.w900)),
            ]),
            Text('${widget.serviceName} · Step $_step of 3: ${stepLabels[_step - 1]}',
                style: const TextStyle(color: _faint, fontSize: 11.5)),
          ])),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: _cyanBg, borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _cyanBg2)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text('₹$_totalAmount',
                  style: const TextStyle(color: _cyanDk, fontSize: 18, fontWeight: FontWeight.w900)),
              const Text('7 visits', style: TextStyle(color: _cyanDk, fontSize: 9.5, fontWeight: FontWeight.w700)),
            ])),
        ]),
      )),
    );
  }

  Widget _buildAddressStep() {
    return Column(children: [
      _card(
        icon: Icons.location_on_rounded,
        title: 'Service Address',
        sub: 'Same address for all 7 visits — pick this first, '
             'so we can check the same professional\'s availability',
        child: _addressesLoading
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 30),
                child: Center(child: CircularProgressIndicator(color: _cyanDk, strokeWidth: 2.4)))
            : _addresses.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  Icon(Icons.location_off_rounded, size: 34, color: _faint),
                  SizedBox(height: 10),
                  Text('No saved addresses',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF374151))),
                  SizedBox(height: 4),
                  Text('Add an address from your profile to continue.',
                      style: TextStyle(color: _faint, fontSize: 12)),
                ]))
            : Column(children: _addresses.map((addr) {
                final active = _selectedAddressId == addr['id'];
                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAddressId = addr['id'];
                      // Changing address invalidates any prior availability
                      // check — different address means a different worker
                      // pool entirely.
                      _availabilityChecked = false;
                      _conflicts = [];
                      _dayOverrides.clear();
                      _overridesVerified = null;
                      _slotGrid = {};
                    });
                    if (_startDate != null) _loadSlotGrid();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: active ? _cyanBg : _bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: active ? _cyan : _border, width: active ? 1.6 : 1)),
                    child: Row(children: [
                      Container(width: 38, height: 38,
                        decoration: BoxDecoration(
                          color: active ? Colors.white : _cyanBg,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: _border)),
                        child: const Icon(Icons.home_rounded, color: _cyanDk, size: 19)),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(addr['label'] ?? 'Address',
                            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
                        Text([addr['flat_no'], addr['building'], addr['area'], addr['city']]
                              .where((e) => e != null).join(', '),
                            maxLines: 1, overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: _faint, fontSize: 12)),
                      ])),
                      if (active) const Icon(Icons.check_circle_rounded, color: _cyan, size: 22),
                    ])));
              }).toList()),
      ),
      const SizedBox(height: 14),
      _card(
        icon: Icons.chat_bubble_outline_rounded,
        title: 'Special Instructions',
        sub: 'Applies to all 7 visits (optional)',
        child: TextField(
          controller: _notesCtrl, maxLines: 3,
          style: const TextStyle(fontSize: 14, color: _ink),
          decoration: InputDecoration(
            hintText: 'e.g. Ring bell twice, pet at home...',
            hintStyle: const TextStyle(color: _faint, fontSize: 13),
            filled: true, fillColor: _bg,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _border)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _cyan, width: 1.6))),
        ),
      ),
    ]);
  }

  Widget _buildDateTimeStep() {
    return Column(children: [
      _card(
        icon: Icons.event_rounded,
        title: 'Start Date',
        sub: 'Your package runs for 7 consecutive days',
        child: Column(children: [
          // Horizontal date-strip picker — same visual pattern as the
          // regular Schedule Booking flow's date row, replacing the old
          // "Choose a start date" button that opened a separate
          // showDatePicker calendar dialog.
          SizedBox(
            height: 92,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _startDateOptions.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (_, i) {
                final d = _startDateOptions[i];
                final active = _startDate != null &&
                    d.year == _startDate!.year &&
                    d.month == _startDate!.month &&
                    d.day == _startDate!.day;
                return GestureDetector(
                  onTap: () => _pickStartDate(d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 58,
                    decoration: BoxDecoration(
                      gradient: active
                          ? const LinearGradient(colors: [_cyan, _cyanDk])
                          : null,
                      color: active ? null : _bg,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: active ? _cyan : _border),
                      boxShadow: active
                          ? [BoxShadow(
                              color: _cyan.withValues(alpha: 0.36),
                              blurRadius: 12, offset: const Offset(0, 4))]
                          : []),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      Text(
                        ['Mon','Tue','Wed','Thu','Fri','Sat','Sun'][d.weekday - 1],
                        style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                            color: active ? const Color(0xFFDFFAFE) : _faint)),
                      Text('${d.day}',
                          style: TextStyle(fontSize: 22,
                              fontWeight: FontWeight.w900,
                              color: active ? Colors.white : _ink)),
                      Text(i == 0 ? 'TODAY' : '·',
                          style: TextStyle(fontSize: 8,
                              fontWeight: FontWeight.w900,
                              color: active
                                  ? Colors.white
                                  : (i == 0 ? _cyan : Colors.transparent))),
                    ]),
                  ),
                );
              },
            ),
          ),
          if (_startDate != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _cyanBg, borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _cyanBg2)),
              child: Row(children: [
                const Icon(Icons.info_outline_rounded, color: _cyanDk, size: 16),
                const SizedBox(width: 8),
                Expanded(child: Text(
                  'Runs ${_prettyDate(_startDate!)} → ${_prettyDate(_startDate!.add(const Duration(days: 6)))}',
                  style: const TextStyle(color: _cyanDk, fontSize: 12, fontWeight: FontWeight.w600))),
              ])),
          ],
        ]),
      ),
      const SizedBox(height: 14),
      _card(
        icon: Icons.access_time_rounded,
        title: 'Daily Time',
        sub: 'Same time every day for all 7 visits',
        child: Column(children: [
          if (_slotGridLoading) ...[
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _cyanDk)),
                SizedBox(width: 8),
                Text('Checking real availability…',
                    style: TextStyle(color: _faint, fontSize: 11.5)),
              ]),
            ),
            const SizedBox(height: 6),
          ] else if (_slotGrid.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(children: [
                _legendDot(_green, 'Fully free'),
                const SizedBox(width: 14),
                _legendDot(_amber, 'Partly free'),
                const SizedBox(width: 14),
                _legendDot(_faint, 'Not free'),
              ]),
            ),
          ],
          GridView.count(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisCount: 3,
            childAspectRatio: 2.4,
            crossAxisSpacing: 10, mainAxisSpacing: 10,
            children: _timeSlots.map((t) {
              final active = _selectedTime == t;
              // Status from the pre-fetched grid — purely a visual guide
              // ('full'/'partial'/'none'). Every slot stays TAPPABLE
              // regardless of status: 'partial' still leads into the
              // normal per-day alternate-time flow, and this grid is a
              // fast approximation, not the authoritative check (that's
              // still check_recurring_availability, run after picking).
              final status = _slotGrid[t];
              final dotColor = status == 'full' ? _green
                  : status == 'partial' ? _amber
                  : status == 'none' ? _faint.withValues(alpha: 0.5)
                  : null; // unknown/not-yet-loaded — no dot shown
              return GestureDetector(
                onTap: () {
                  setState(() {
                    _selectedTime = t;
                    _availabilityChecked = false;
                    _conflicts = [];
                    _dayOverrides.clear();
                    _overridesVerified = null;
                  });
                  HapticFeedback.selectionClick();
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  decoration: BoxDecoration(
                    gradient: active ? const LinearGradient(colors: [_cyan, _cyanDk]) : null,
                    color: active ? null : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: active ? _cyan : _border)),
                  child: Stack(alignment: Alignment.center, children: [
                    Center(child: Text(_pretty12h(t),
                        style: TextStyle(
                          fontSize: 11.5, fontWeight: FontWeight.w800,
                          color: active ? Colors.white : const Color(0xFF334155)))),
                    if (dotColor != null && !active)
                      Positioned(top: 5, right: 7,
                          child: Container(width: 6, height: 6,
                              decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle))),
                  ]),
                ));
            }).toList()),
        ]),
      ),
      if (_availabilityChecked && _conflicts.isNotEmpty) ...[
        const SizedBox(height: 14),
        _buildConflictsCard(),
      ],
      if (_availabilityChecked && _allDaysAvailable && _conflicts.isEmpty) ...[
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFECFDF5), borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF6EE7B7))),
          child: Row(children: [
            Container(width: 40, height: 40,
              decoration: BoxDecoration(color: _green, borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 22)),
            const SizedBox(width: 12),
            const Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('All 7 days available!',
                  style: TextStyle(color: Color(0xFF065F46), fontWeight: FontWeight.w900, fontSize: 14)),
              SizedBox(height: 2),
              Text('The same professional will handle every visit.',
                  style: TextStyle(color: Color(0xFF059669), fontSize: 11.5)),
            ])),
          ])),
      ],
      if (_error != null) ...[
        const SizedBox(height: 12),
        _errorBox(_error!),
      ],
    ]);
  }

  Widget _buildConflictsCard() {
    final allPicked = _conflicts.every((c) => _dayOverrides.containsKey(c['day'] as int));
    return _card(
      icon: Icons.event_busy_rounded,
      title: 'Some days need a different time',
      sub: 'Pick an alternate time for the days below',
      child: Column(children: [
        ..._conflicts.map((c) {
          final day = c['day'] as int;
          final date = DateTime.parse(c['date'] as String);
          final chosen = _dayOverrides[day];
          return Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: chosen != null ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: chosen != null
                  ? const Color(0xFF6EE7B7) : const Color(0xFFFED7AA))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(chosen != null ? Icons.check_circle_rounded : Icons.warning_amber_rounded,
                    color: chosen != null ? _greenDk : _amber, size: 18),
                const SizedBox(width: 8),
                Expanded(child: Text('Day $day · ${_prettyDate(date)}',
                    style: TextStyle(
                        color: chosen != null ? const Color(0xFF065F46) : const Color(0xFF92400E),
                        fontWeight: FontWeight.w800, fontSize: 13))),
                if (chosen != null)
                  Text(_pretty12h(chosen),
                      style: const TextStyle(color: _greenDk, fontWeight: FontWeight.w900, fontSize: 13)),
              ]),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _timeSlots.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final t = _timeSlots[i];
                    final active = chosen == t;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _dayOverrides[day] = t);
                        _verifyOverridesWork();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: active ? _cyanDk : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: active ? _cyanDk : _border)),
                        child: Text(_pretty12h(t),
                            style: TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w700,
                              color: active ? Colors.white : const Color(0xFF334155)))),
                    );
                  })),
            ]));
        }),
        if (allPicked) ...[
          const SizedBox(height: 4),
          if (_verifyingOverrides)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Row(children: [
                SizedBox(width: 14, height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _cyanDk)),
                SizedBox(width: 8),
                Text('Confirming a professional can cover this schedule…',
                    style: TextStyle(color: _faint, fontSize: 11.5)),
              ]),
            )
          else if (_overridesVerified == false)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFECACA))),
              child: const Text(
                'No single professional can cover all 7 days with this '
                'combination of times. Please try different alternate '
                'times for the conflicting days above.',
                style: TextStyle(color: Color(0xFFDC2626), fontSize: 12, height: 1.4)),
            )
          else if (_overridesVerified == true)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFECFDF5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFF6EE7B7))),
              child: const Text(
                '✓ Confirmed — one professional can cover all 7 days with these times.',
                style: TextStyle(color: Color(0xFF065F46), fontSize: 12, fontWeight: FontWeight.w700)),
            ),
        ],
      ]),
    );
  }

  Widget _buildConfirmStep() {
    final addr = _addresses.firstWhere((a) => a['id'] == _selectedAddressId,
        orElse: () => {});
    return Column(children: [
      _card(
        icon: Icons.repeat_rounded,
        title: 'Your 7 Visits',
        sub: 'Same professional, every day',
        child: Column(children: List.generate(7, (i) {
          final day = i + 1;
          final date = _startDate!.add(Duration(days: i));
          final time = _dayOverrides[day] ?? _selectedTime;
          final isAlt = _dayOverrides.containsKey(day);
          return Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(children: [
              Container(width: 30, height: 30,
                decoration: BoxDecoration(
                  color: _cyanBg, borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: _cyanBg2)),
                child: Center(child: Text('$day',
                    style: const TextStyle(color: _cyanDk, fontSize: 12, fontWeight: FontWeight.w900)))),
              const SizedBox(width: 12),
              Expanded(child: Text(_prettyDate(date),
                  style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: _ink))),
              Text(_pretty12h(time),
                  style: TextStyle(
                    fontSize: 13, fontWeight: FontWeight.w800,
                    color: isAlt ? _amber : _cyanDk)),
              if (isAlt) ...[
                const SizedBox(width: 4),
                const Icon(Icons.edit_rounded, color: _amber, size: 12),
              ],
            ]));
        })),
      ),
      const SizedBox(height: 14),
      _card(
        icon: Icons.receipt_long_rounded,
        title: 'Summary',
        sub: 'Review before payment',
        child: Column(children: [
          _row('Service', widget.serviceName),
          _row('Address', addr.isNotEmpty ? '${addr['area']}, ${addr['city']}' : '—'),
          _row('Duration', '~${widget.durationMins} min per visit'),
          _row('Price per visit', '₹${widget.pricePerVisit}'),
          _row('Visits', '7'),
          _row('Subtotal', '₹$_packageSubtotal'),
          _row('Platform Fee', '₹$_platformFee'),
          const Divider(color: _border, height: 22),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Total (paid now)',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900, color: _ink)),
            Text('₹$_totalAmount',
                style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: _cyanDk)),
          ]),
        ]),
      ),
      const SizedBox(height: 14),
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF7ED), borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFED7AA))),
        child: const Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_rounded, color: Color(0xFFEA580C), size: 20),
          SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Please note',
                style: TextStyle(color: Color(0xFF9A3412), fontSize: 13, fontWeight: FontWeight.w900)),
            SizedBox(height: 3),
            Text('The full package is paid upfront. If you cancel any single '
                 'day, that visit is forfeited and cannot be refunded or '
                 'rescheduled — the remaining visits continue as normal.\n\n'
                 'Our professionals do not carry cleaning equipment or '
                 'supplies. Please keep the required equipment available.',
                style: TextStyle(color: Color(0xFFB45309), fontSize: 12, height: 1.45)),
          ])),
        ])),
      if (_error != null) ...[
        const SizedBox(height: 12),
        _errorBox(_error!),
      ],
    ]);
  }

  Widget _row(String l, String v) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(l, style: const TextStyle(color: _faint, fontSize: 12.5)),
      Flexible(child: Text(v, textAlign: TextAlign.right,
          style: const TextStyle(color: _ink, fontSize: 13.5, fontWeight: FontWeight.w700))),
    ]));

  Widget _legendDot(Color color, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(width: 7, height: 7,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(color: _faint, fontSize: 10.5, fontWeight: FontWeight.w600)),
    ],
  );

  Widget _errorBox(String msg) => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFEF2F2), borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFECACA))),
    child: Text(msg,
        style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12.5, fontWeight: FontWeight.w600)));

  Widget _card({
    required IconData icon, required String title,
    required String sub, required Widget child,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: _border),
        boxShadow: [BoxShadow(
            color: const Color(0xFF0F172A).withValues(alpha: 0.04),
            blurRadius: 14, offset: const Offset(0, 6))]),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 14),
          child: Row(children: [
            Container(width: 38, height: 38,
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_cyan, _cyanDk]),
                borderRadius: BorderRadius.circular(12)),
              child: Icon(icon, color: Colors.white, size: 18)),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(
                  fontWeight: FontWeight.w800, fontSize: 14, color: _ink)),
              Text(sub, style: const TextStyle(color: _faint, fontSize: 11)),
            ])),
          ]),
        ),
        const Divider(height: 1, color: Color(0xFFF1F5F9)),
        Padding(padding: const EdgeInsets.all(16), child: child),
      ]),
    );
  }

  Widget _buildBottomBar() {
    final bottom = MediaQuery.of(context).padding.bottom;

    // Step 2 has three distinct states, in order:
    //   1. Date/time not both picked yet -> disabled "Continue"
    //   2. Both picked but not checked yet -> active "Check availability
    //      for all 7 days" (this now lives here instead of inline in the
    //      card, per product request)
    //   3. Checked and all 7 days confirmed available (with any needed
    //      per-day overrides chosen AND verified) -> active "Continue"
    final isCheckStep = _step == 2 &&
        _startDate != null && _selectedTime.isNotEmpty && !_availabilityChecked;

    // When conflicts exist but haven't all been resolved with an
    // alternate time yet, Continue stays disabled by design — but a
    // plain grey button gave no indication WHY, or what to actually do.
    // This computes exactly how many days still need a pick, so the
    // button can say that directly instead of leaving the customer
    // stuck tapping a dead button with no explanation.
    final unresolvedConflicts = _step == 2
        ? _conflicts.where((c) => !_dayOverrides.containsKey(c['day'] as int)).length
        : 0;
    final hasUnresolvedConflicts = unresolvedConflicts > 0;

    final canProceed = _step == 1 ? _canProceedFromAddressStep
                     : _step == 2 ? (isCheckStep ? true : _canProceedFromDateTimeStep)
                     : true;
    final isLast = _step == 3;

    String label;
    IconData? leadingIcon;
    VoidCallback? onTap;

    if (isCheckStep) {
      label = 'Check availability for all 7 days';
      leadingIcon = null;
      onTap = _checking ? null : _checkAvailability;
    } else if (hasUnresolvedConflicts) {
      // Distinct, actionable label instead of a silent disabled
      // "Continue" — tapping it scrolls up to the conflict card rather
      // than doing nothing, since that's genuinely the next required
      // action.
      label = unresolvedConflicts == 1
          ? 'Pick a time for 1 day above ↑'
          : 'Pick a time for $unresolvedConflicts days above ↑';
      leadingIcon = Icons.arrow_upward_rounded;
      onTap = () {
        HapticFeedback.selectionClick();
        // No dedicated ScrollController is wired up in this screen yet —
        // this at minimum gives tactile feedback confirming the tap
        // registered (rather than looking completely dead), while the
        // label itself tells them exactly where to look.
      };
    } else if (isLast) {
      label = 'Pay ₹$_totalAmount & Confirm';
      leadingIcon = Icons.payments_rounded;
      onTap = (canProceed && !_loading) ? _startPayment : null;
    } else {
      label = 'Continue';
      leadingIcon = null;
      onTap = (canProceed && !_loading) ? () => setState(() => _step++) : null;
    }

    final busy = isCheckStep ? _checking : _loading;
    final active = isCheckStep ? true : (hasUnresolvedConflicts ? false : canProceed);

    return Container(
      padding: EdgeInsets.fromLTRB(16, 14, 16, 14 + bottom),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.07),
            blurRadius: 22, offset: const Offset(0, -6))]),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          decoration: BoxDecoration(
            gradient: active ? const LinearGradient(colors: [_cyan, _cyanDk]) : null,
            color: active ? null : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(16)),
          child: Center(child: busy
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  if (leadingIcon != null) Icon(leadingIcon, color: Colors.white, size: 18),
                  if (leadingIcon != null) const SizedBox(width: 8),
                  Text(label,
                      style: TextStyle(
                        color: active ? Colors.white : _faint,
                        fontSize: 15, fontWeight: FontWeight.w900)),
                  if (!isCheckStep && !hasUnresolvedConflicts) ...[
                    const SizedBox(width: 8),
                    Icon(Icons.arrow_forward_rounded,
                        color: active ? Colors.white : _faint, size: 18),
                  ],
                ])),
        ),
      ),
    );
  }
}