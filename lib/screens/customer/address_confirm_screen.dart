import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import '../../services/coverage_service.dart';

/// Saving an address here does NOT check serviceability anymore — a
/// customer can save an address anywhere. Whether that address can
/// actually be used to BOOK a service is checked later, at booking
/// confirmation time (see booking_flow_screen.dart), against the
/// admin-managed `service_areas` table. This matches the product
/// decision: browsing/saving addresses is always allowed; booking is
/// what's gated by service area.
///
/// UPDATED: added a draggable-pin map. Whatever coordinates got here
/// (from a text search result or GPS auto-location) were previously
/// saved exactly as-is, shown only as plain text with no way to verify
/// or correct them — search results often return a street/area center
/// rather than the exact building, and GPS drifts indoors, so workers
/// were repeatedly getting sent to the wrong spot. The customer now
/// sees the pin on an actual map and can drag it onto their real
/// building before saving; dragging re-reverse-geocodes so the
/// displayed address text stays consistent with wherever the pin
/// actually ends up.
class AddressConfirmScreen extends StatefulWidget {
  final double lat;
  final double lng;
  final String area;
  final String city;
  final String pincode;
  final String fullAddress;
  final bool   isOnboarding;
  // NEW: when set, this screen edits the existing address with this id
  // (an UPDATE) instead of creating a new one (an INSERT) — used by
  // "Edit Location" on the Saved Addresses screen, so a customer can
  // drag the pin to correct an address they already saved, without
  // losing its booking history by deleting and re-adding it.
  final String? editAddressId;
  final String? initialLabel;
  final String? initialFlatNo;
  final String? initialBuilding;
  final String? initialLandmark;

  const AddressConfirmScreen({
    super.key,
    required this.lat,
    required this.lng,
    required this.area,
    required this.city,
    required this.pincode,
    required this.fullAddress,
    this.isOnboarding = false,
    this.editAddressId,
    this.initialLabel,
    this.initialFlatNo,
    this.initialBuilding,
    this.initialLandmark,
  });

  @override
  State<AddressConfirmScreen> createState() => _AddressConfirmScreenState();
}

class _AddressConfirmScreenState extends State<AddressConfirmScreen> {
  final _supabase     = Supabase.instance.client;
  final _flatCtrl     = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _landmarkCtrl = TextEditingController();

  // Same mobile Maps key used elsewhere in the Cleenzo apps. If the
  // customer app uses a DIFFERENT key than the worker/admin ones,
  // replace this with the correct one.
  static const String _mapsKey = 'AIzaSyCwm6IDpINuP3K7XH9Zy9sL7C-ACR_UgWU';

  bool get _isEditing => widget.editAddressId != null;

  late String  _label  = widget.initialLabel ?? 'Home';
  bool    _saving = false;
  String? _error;

  // NEW: mutable copies of the incoming location/address — dragging the
  // pin updates these, while widget.* stays the original starting point.
  late double _lat = widget.lat;
  late double _lng = widget.lng;
  late String _area = widget.area;
  late String _city = widget.city;
  late String _pincode = widget.pincode;
  late String _fullAddress = widget.fullAddress;

  GoogleMapController? _map;
  bool _reverseGeocoding = false;
  // Shown once if the pin has never actually been dragged, so a
  // customer doesn't miss that adjusting it is possible.
  bool _pinMoved = false;

  // NEW: live "can we serve here?" result for wherever the pin is now,
  // using the same server rule as booking (check_serviceable). Saving
  // is still always allowed; this just tells the customer up front.
  CoverageResult? _coverage;
  bool _checkingCoverage = false;
  int _coverageSeq = 0;

  @override
  void initState() {
    super.initState();
    if (widget.initialFlatNo != null) _flatCtrl.text = widget.initialFlatNo!;
    if (widget.initialBuilding != null) _buildingCtrl.text = widget.initialBuilding!;
    if (widget.initialLandmark != null) _landmarkCtrl.text = widget.initialLandmark!;
    _checkCoverage();
  }

  Future<void> _checkCoverage() async {
    final seq = ++_coverageSeq;
    setState(() => _checkingCoverage = true);
    final r = await CoverageService.check(
        lat: _lat, lng: _lng, pincode: _pincode.isEmpty ? null : _pincode);
    if (!mounted || seq != _coverageSeq) return; // a newer pin position won
    setState(() {
      _coverage = r;
      _checkingCoverage = false;
    });
  }

  @override
  void dispose() {
    _flatCtrl.dispose();
    _buildingCtrl.dispose();
    _landmarkCtrl.dispose();
    super.dispose();
  }

  // NEW: reverse-geocodes whatever coordinate the pin was dropped at,
  // so the address text shown (and saved) matches where the customer
  // actually says their building is — not wherever the original
  // search/GPS guess landed.
  Future<void> _reverseGeocode(double lat, double lng) async {
    setState(() => _reverseGeocoding = true);
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/geocode/json'
        '?latlng=$lat,$lng&key=$_mapsKey',
      );
      final res = await http.get(url).timeout(const Duration(seconds: 8));
      final data = jsonDecode(res.body) as Map<String, dynamic>;
      if (data['status'] == 'OK') {
        final results = data['results'] as List;
        if (results.isNotEmpty) {
          final result = results[0] as Map<String, dynamic>;
          final components = (result['address_components'] as List)
              .cast<Map<String, dynamic>>();
          String comp(String type) {
            for (final c in components) {
              if ((c['types'] as List).contains(type)) {
                return c['long_name']?.toString() ?? '';
              }
            }
            return '';
          }
          final area = comp('sublocality_level_1').isNotEmpty
              ? comp('sublocality_level_1')
              : comp('locality');
          final city = comp('locality').isNotEmpty ? comp('locality') : comp('administrative_area_level_2');
          final pincode = comp('postal_code');
          final formatted = result['formatted_address']?.toString() ?? _fullAddress;
          if (mounted) {
            setState(() {
              if (area.isNotEmpty) _area = area;
              if (city.isNotEmpty) _city = city;
              if (pincode.isNotEmpty) _pincode = pincode;
              _fullAddress = formatted;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Reverse geocode failed: $e');
      // Keep whatever address text was already showing — the pin
      // location (the part that actually matters for navigation) is
      // still updated regardless of whether the text refresh worked.
    } finally {
      if (mounted) setState(() => _reverseGeocoding = false);
    }
    // re-check coverage for the new pin position + pincode
    if (mounted) _checkCoverage();
  }

  void _onPinDragEnd(LatLng pos) {
    setState(() {
      _lat = pos.latitude;
      _lng = pos.longitude;
      _pinMoved = true;
    });
    _reverseGeocode(pos.latitude, pos.longitude);
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });

    final userId = await SupabaseService.loadCachedUserId() ??
        SupabaseService.currentUserId;
    if (userId == null) {
      if (mounted) context.go('/login');
      return;
    }

    try {
      // Shared fields between insert and update — everything about
      // WHERE and WHAT the address is, but not ownership/default
      // status, which only matters for a brand-new row.
      final fields = {
        'label':        _label,
        'flat_no':      _flatCtrl.text.trim().isEmpty ? null : _flatCtrl.text.trim(),
        'building':     _buildingCtrl.text.trim().isEmpty ? null : _buildingCtrl.text.trim(),
        'area':         _area,
        'city':         _city,
        'pincode':      _pincode,
        'full_address': _fullAddress,
        'latitude':     _lat,
        'longitude':    _lng,
        'landmark':     _landmarkCtrl.text.trim().isEmpty ? null : _landmarkCtrl.text.trim(),
      };

      if (_isEditing) {
        // NEW: editing an existing address — UPDATE in place, keeping
        // its id (and therefore its booking history) intact, and
        // deliberately NOT touching is_default, since editing an
        // address's location shouldn't silently change which one is
        // the customer's default.
        await _supabase
            .from('addresses')
            .update(fields)
            .eq('id', widget.editAddressId!)
            .eq('user_id', userId);
      } else {
        final existing = await _supabase
            .from('addresses')
            .select('id')
            .eq('user_id', userId)
            .eq('is_deleted', false)
            .limit(1);

        final isFirst = (existing as List).isEmpty;

        // FIXED: now saves the (possibly customer-adjusted) _lat/_lng
        // and address fields, not the original widget.* values — so if
        // the customer dragged the pin onto their actual building,
        // that's what gets stored, not the original approximate
        // search/GPS coordinate.
        await _supabase.from('addresses').insert({
          'user_id': userId,
          ...fields,
          'is_default': isFirst,
        });
      }

      // NEW: saved — but if we don't serve this spot, say so now (with
      // 🔔 Notify me) instead of the customer only finding out at booking.
      if (mounted && _coverage != null && !_coverage!.ok && _coverage!.reason != 'error') {
        await CoverageService.showNotServiceableSheet(
          context,
          result: _coverage!,
          lat: _lat,
          lng: _lng,
          pincode: _pincode.isEmpty ? null : _pincode,
          fullAddress: _fullAddress,
          area: _area,
        );
      }

      if (mounted) {
        if (widget.isOnboarding) {
          context.go('/services'); // ← go to services after onboarding
        } else {
          Navigator.pop(context, true); // ← back to account screen
        }
      }
    } catch (e) {
      debugPrint('Save address error: $e');
      setState(() {
        _error = 'Failed to save address. Try again.';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(children: [

        // ── Header ────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
                colors: [Color(0xFF00B1FC), Color(0xFF00B1FC)]),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Row(children: [
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    width: 36, height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.arrow_back_ios_new,
                        color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Text(_isEditing ? 'Edit Location' : 'Confirm Address',
                    style: TextStyle(color: Colors.white,
                        fontSize: 18, fontWeight: FontWeight.w900)),
              ]),
            ),
          ),
        ),

        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start,
                children: [

              // NEW: draggable-pin map — the actual fix. Lets the
              // customer see exactly where the pin landed and correct
              // it onto their real building before anything is saved.
              const Text('DRAG THE PIN TO YOUR EXACT LOCATION',
                  style: TextStyle(
                      color: Color(0xFF9CA3AF), fontSize: 10,
                      fontWeight: FontWeight.w800, letterSpacing: 1.2)),
              const SizedBox(height: 10),
              Container(
                height: 220,
                margin: const EdgeInsets.only(bottom: 8),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8EDF2)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Stack(
                  children: [
                    GoogleMap(
                      initialCameraPosition: CameraPosition(
                        target: LatLng(_lat, _lng), zoom: 17,
                      ),
                      onMapCreated: (c) => _map = c,
                      markers: {
                        Marker(
                          markerId: const MarkerId('pin'),
                          position: LatLng(_lat, _lng),
                          draggable: true,
                          onDragEnd: _onPinDragEnd,
                        ),
                      },
                      myLocationButtonEnabled: false,
                      zoomControlsEnabled: false,
                      mapToolbarEnabled: false,
                    ),
                    if (_reverseGeocoding)
                      Positioned(
                        top: 10, right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 6)],
                          ),
                          child: const SizedBox(
                            width: 14, height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B1FC)),
                          ),
                        ),
                      ),
                    if (!_pinMoved)
                      Positioned(
                        left: 10, right: 10, bottom: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Row(
                            children: [
                              Icon(Icons.touch_app_rounded, color: Colors.white, size: 14),
                              SizedBox(width: 6),
                              Expanded(
                                child: Text('Not quite right? Drag the pin to your building',
                                    style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600)),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              // NEW: live coverage status for the current pin
              _coverageChip(),
              const SizedBox(height: 16),

              // Detected address card
              Container(
                padding: const EdgeInsets.all(16),
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE8EDF2)),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 8)],
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: const Color(0xFF00B1FC),
                      borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.location_on_rounded,
                        color: Color(0xFF00B1FC), size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(
                      _area.isNotEmpty ? _area : _city,
                      style: const TextStyle(fontWeight: FontWeight.w800,
                          fontSize: 15, color: Color(0xFF0F172A)),
                    ),
                    const SizedBox(height: 3),
                    Text(_fullAddress,
                        style: const TextStyle(
                            color: Color(0xFF64748B), fontSize: 12),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    if (_pincode.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text('📮 $_pincode',
                          style: const TextStyle(
                              color: Color(0xFF94A3B8), fontSize: 11)),
                    ],
                  ])),
                ]),
              ),

              // Label selector
              const Text('SAVE AS', style: TextStyle(
                  color: Color(0xFF9CA3AF), fontSize: 10,
                  fontWeight: FontWeight.w800, letterSpacing: 1.5)),
              const SizedBox(height: 10),
              Row(
                children: ['Home', 'Office', 'Other'].map((lbl) {
                  final icons = {'Home': '🏠', 'Office': '🏢', 'Other': '📍'};
                  final active = _label == lbl;
                  return Expanded(child: Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: GestureDetector(
                      onTap: () => setState(() => _label = lbl),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        decoration: BoxDecoration(
                          color: active
                              ? const Color(0xFF00B1FC) : Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: active
                                ? const Color(0xFF00B1FC)
                                : const Color(0xFFE8EDF2),
                            width: active ? 1.5 : 1),
                        ),
                        child: Column(children: [
                          Text(icons[lbl]!,
                              style: const TextStyle(fontSize: 22)),
                          const SizedBox(height: 4),
                          Text(lbl, style: TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w700,
                            color: active
                                ? const Color(0xFF00B1FC)
                                : const Color(0xFF64748B),
                          )),
                        ]),
                      ),
                    ),
                  ));
                }).toList(),
              ),

              const SizedBox(height: 20),
              _field(controller: _flatCtrl,
                  label: 'FLAT / HOUSE NO.',
                  hint: 'e.g. 304, A Wing (optional)'),
              const SizedBox(height: 14),
              _field(controller: _buildingCtrl,
                  label: 'BUILDING / SOCIETY',
                  hint: 'e.g. Lotus Heights (optional)'),
              const SizedBox(height: 14),
              _field(controller: _landmarkCtrl,
                  label: 'NEARBY LANDMARK',
                  hint: 'e.g. Near SBI Bank (optional)'),
              const SizedBox(height: 24),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5)),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFDC2626),
                          fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ],

              // Save button
              GestureDetector(
                onTap: _saving ? null : _save,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [Color(0xFF00B1FC), Color(0xFF00B1FC)]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                      color: const Color(0xFF00B1FC).withValues(alpha: 0.4),
                      blurRadius: 16, offset: const Offset(0, 6))],
                  ),
                  child: Center(
                    child: _saving
                        ? const SizedBox(width: 22, height: 22,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.check_circle_outline_rounded,
                                  color: Colors.white, size: 20),
                              const SizedBox(width: 10),
                              Text(_isEditing ? 'Save Changes' : 'Save Address',
                                  style: const TextStyle(color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ]),
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _coverageChip() {
    final r = _coverage;
    if (_checkingCoverage || r == null) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          SizedBox(width: 14, height: 14,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00B1FC))),
          SizedBox(width: 8),
          Text('Checking if we serve this location…',
              style: TextStyle(color: Color(0xFF94A3B8), fontSize: 12)),
        ]),
      );
    }
    if (r.reason == 'error') return const SizedBox.shrink();
    final ok = r.ok;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: ok ? const Color(0xFFECFDF5) : const Color(0xFFFFF7ED),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: ok ? const Color(0xFFA7F3D0) : const Color(0xFFFED7AA)),
      ),
      child: Row(children: [
        Text(ok ? '✅' : '😔', style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            ok
                ? 'Great — Cleenzo serves this location'
                : r.reason == 'no_location'
                    ? 'Drag the pin onto your building so we can check'
                    : "We don't serve this location yet — you can still save it",
            style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: ok ? const Color(0xFF047857) : const Color(0xFFC2410C)),
          ),
        ),
      ]),
    );
  }

  Widget _field({required TextEditingController controller,
      required String label, required String hint}) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(
          color: Color(0xFF9CA3AF), fontSize: 10,
          fontWeight: FontWeight.w800, letterSpacing: 1.5)),
      const SizedBox(height: 8),
      TextField(
        controller: controller,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(color: Color(0xFFD1D5DB), fontSize: 13),
          filled: true, fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8EDF2))),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: Color(0xFFE8EDF2))),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(
                color: Color(0xFF00B1FC), width: 1.5)),
          contentPadding: const EdgeInsets.symmetric(
              horizontal: 16, vertical: 14),
        ),
      ),
    ]);
  }
}