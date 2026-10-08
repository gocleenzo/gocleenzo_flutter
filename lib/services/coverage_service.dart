// lib/services/coverage_service.dart
//
// "Can this address book?" — asks the database (check_serviceable),
// which applies the admin's rules: Whole pincode / Only inside zones /
// Blocked, drawn Service Zones, and 🚫 Excluded zones.
//
// If the check itself fails (no internet etc.) it lets the customer
// continue — the database still refuses an unpaid booking outside the
// area, so nothing slips through.
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CoverageResult {
  final bool ok;
  final String reason; // ok | excluded | blocked | outside_zone | not_serviceable | no_location | error
  final String message;
  final String? pincode;
  final String? area;
  const CoverageResult({
    required this.ok,
    required this.reason,
    required this.message,
    this.pincode,
    this.area,
  });
}

class CoverageService {
  static final _supabase = Supabase.instance.client;

  /// Ask the database whether this point/pincode can book.
  static Future<CoverageResult> check({
    double? lat,
    double? lng,
    String? pincode,
  }) async {
    try {
      final res = await _supabase.rpc('check_serviceable', params: {
        'p_lat': lat,
        'p_lng': lng,
        'p_pincode': pincode,
      });
      final m = Map<String, dynamic>.from(res as Map);
      return CoverageResult(
        ok: m['ok'] == true,
        reason: (m['reason'] ?? '').toString(),
        message: (m['message'] ?? '').toString(),
        pincode: m['pincode']?.toString(),
        area: m['area']?.toString(),
      );
    } catch (e) {
      debugPrint('coverage check failed: $e');
      return const CoverageResult(ok: true, reason: 'error', message: '');
    }
  }

  /// Checks, and if not serviceable shows the bottom sheet (with
  /// "Notify me"). Returns true only when the customer can book here.
  static Future<bool> ensureServiceable(
    BuildContext context, {
    double? lat,
    double? lng,
    String? pincode,
    String? fullAddress,
    String? area,
  }) async {
    final r = await check(lat: lat, lng: lng, pincode: pincode);
    if (r.ok) return true;
    if (!context.mounted) return false;
    await showNotServiceableSheet(
      context,
      result: r,
      lat: lat,
      lng: lng,
      pincode: pincode,
      fullAddress: fullAddress,
      area: area,
    );
    return false;
  }

  /// Saves a "Notify me when you start here" request.
  static Future<bool> notifyMe({
    double? lat,
    double? lng,
    String? pincode,
    String? fullAddress,
    String? area,
  }) async {
    try {
      String? userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        final prefs = await SharedPreferences.getInstance();
        userId = prefs.getString('app_user_id');
      }
      await _supabase.rpc('request_coverage', params: {
        'p_user_id': userId,
        'p_latitude': lat,
        'p_longitude': lng,
        'p_pincode': pincode,
        'p_area': area,
        'p_full_address': fullAddress,
        'p_name': null,
        'p_phone': null,
      });
      return true;
    } catch (e) {
      debugPrint('notify-me failed: $e');
      return false;
    }
  }

  static Future<void> showNotServiceableSheet(
    BuildContext context, {
    required CoverageResult result,
    double? lat,
    double? lng,
    String? pincode,
    String? fullAddress,
    String? area,
  }) {
    final noPin = result.reason == 'no_location';
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (sheetCtx) => _NotServiceableSheet(
        noPin: noPin,
        pincode: result.pincode ?? pincode,
        onNotify: () => notifyMe(
          lat: lat,
          lng: lng,
          pincode: pincode,
          fullAddress: fullAddress,
          area: area,
        ),
      ),
    );
  }
}

class _NotServiceableSheet extends StatefulWidget {
  final bool noPin;
  final String? pincode;
  final Future<bool> Function() onNotify;
  const _NotServiceableSheet({
    required this.noPin,
    required this.pincode,
    required this.onNotify,
  });

  @override
  State<_NotServiceableSheet> createState() => _NotServiceableSheetState();
}

class _NotServiceableSheetState extends State<_NotServiceableSheet> {
  bool _sending = false;
  bool _sent = false;

  static const _cyan = Color(0xFF00B1FC);
  static const _ink = Color(0xFF0F172A);
  static const _muted = Color(0xFF64748B);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 14, 22, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(4)),
            ),
            const SizedBox(height: 18),
            Text(widget.noPin ? '📍' : '😔', style: const TextStyle(fontSize: 44)),
            const SizedBox(height: 10),
            Text(
              widget.noPin
                  ? 'Please pin your exact location'
                  : "We don't serve this area yet",
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w800, color: _ink),
            ),
            const SizedBox(height: 6),
            Text(
              widget.noPin
                  ? 'Move the map pin to your building so we can check if we serve your address.'
                  : 'Cleenzo isn\'t available at this address${widget.pincode != null ? ' (${widget.pincode})' : ''} right now. '
                      'We\'re expanding fast — tap below and we\'ll tell you the day we start here.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: _muted, height: 1.4),
            ),
            const SizedBox(height: 20),
            if (!widget.noPin)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _sent || _sending
                      ? null
                      : () async {
                          setState(() => _sending = true);
                          final ok = await widget.onNotify();
                          if (!mounted) return;
                          setState(() {
                            _sending = false;
                            _sent = ok;
                          });
                          if (!ok) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Could not save. Please try again.')),
                            );
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _cyan,
                    disabledBackgroundColor: const Color(0xFFD1FAE5),
                    foregroundColor: Colors.white,
                    disabledForegroundColor: const Color(0xFF047857),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    _sent
                        ? "✓ Done — we'll notify you"
                        : _sending
                            ? 'Saving…'
                            : '🔔 Notify me when you start here',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.noPin ? 'OK' : 'Use a different address',
                  style: const TextStyle(fontWeight: FontWeight.w700, color: _muted)),
            ),
          ],
        ),
      ),
    );
  }
}
