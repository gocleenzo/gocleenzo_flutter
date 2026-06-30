import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';

class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialArea;
  final String? initialCity;
  final String? initialPincode;
  final String? initialFullAddress;
  final bool    isOnboarding;

  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialArea,
    this.initialCity,
    this.initialPincode,
    this.initialFullAddress,
    this.isOnboarding = false,
  });

  @override
  State<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  GoogleMapController? _mapController;
  LatLng _pin = const LatLng(19.1136, 72.8697);

  String _area        = '';
  String _city        = '';
  String _pincode     = '';
  String _fullAddress = '';
  bool   _geocoding   = false;
  bool   _pinMoving   = false;

  // Serviceability
  bool   _isServiceable    = true;
  bool   _notifyLoading    = false;
  bool   _notifyDone       = false;

  // Pin bounce animation
  late AnimationController _bounceCtrl;
  late Animation<double>   _bounceAnim;

  // ── Colours ────────────────────────────────────────────────
  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _red    = Color(0xFFDC2626);
  static const _redLt  = Color(0xFFFEF2F2);
  static const _amber  = Color(0xFFD97706);
  static const _amberLt= Color(0xFFFFFBEB);

  // ── Allowed pincodes ───────────────────────────────────────
  static const _allowedPincodes = {
    '400056', '400057', // Vile Parle
    '400049',           // Juhu
    '400053', '400058', '400059', '400069', // Andheri
  };

  // Fallback area name check (when pincode not available)
  static const _allowedAreaKeywords = [
    'vile parle', 'vileparle',
    'juhu',
    'andheri',
  ];

  bool _checkServiceable(String pincode, String area) {
    if (pincode.isNotEmpty) {
      return _allowedPincodes.contains(pincode.trim());
    }
    // Fallback: area name check
    final lower = area.toLowerCase();
    return _allowedAreaKeywords.any((k) => lower.contains(k));
  }

  @override
  void initState() {
    super.initState();
    _bounceCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 350));
    _bounceAnim = Tween<double>(begin: 0, end: -12)
        .animate(CurvedAnimation(
            parent: _bounceCtrl, curve: Curves.easeOut));

    if (widget.initialLat != null && widget.initialLng != null) {
      _pin         = LatLng(widget.initialLat!, widget.initialLng!);
      _area        = widget.initialArea        ?? '';
      _city        = widget.initialCity        ?? '';
      _pincode     = widget.initialPincode     ?? '';
      _fullAddress = widget.initialFullAddress ?? '';
      if (_area.isEmpty) {
        _reverseGeocode(_pin);
      } else {
        _isServiceable = _checkServiceable(_pincode, _area);
      }
    } else {
      _detectAndMove();
    }
  }

  @override
  void dispose() {
    _bounceCtrl.dispose();
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _detectAndMove() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high));
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() => _pin = latlng);
      _mapController?.animateCamera(
          CameraUpdate.newLatLngZoom(latlng, 16));
      await _reverseGeocode(latlng);
    } catch (_) {}
  }

  Future<void> _reverseGeocode(LatLng latlng) async {
    setState(() { _geocoding = true; _notifyDone = false; });
    try {
      final placemarks = await placemarkFromCoordinates(
          latlng.latitude, latlng.longitude);
      if (placemarks.isNotEmpty && mounted) {
        final p = placemarks.first;
        final area    = p.subLocality ?? p.locality ?? '';
        final city    = p.locality ?? p.administrativeArea ?? '';
        final pincode = p.postalCode ?? '';
        final full    = [
          p.street, p.subLocality, p.locality,
          p.administrativeArea, p.postalCode,
        ].where((e) => e != null && e!.isNotEmpty).join(', ');

        setState(() {
          _area        = area;
          _city        = city;
          _pincode     = pincode;
          _fullAddress = full;
          _isServiceable = _checkServiceable(pincode, area);
          _pinMoving   = false;
          _geocoding   = false;
        });

        // Bounce pin
        _bounceCtrl.forward(from: 0)
            .then((_) => _bounceCtrl.reverse());
      }
    } catch (_) {
      if (mounted) setState(() { _geocoding = false; _pinMoving = false; });
    }
  }

  Future<void> _notifyMe() async {
    if (_notifyDone) return;
    setState(() => _notifyLoading = true);
    HapticFeedback.mediumImpact();

    try {
      final userId = await SupabaseService.loadCachedUserId() ??
          SupabaseService.currentUserId;
      String? phone;
      if (userId != null) {
        final profile = await _supabase
            .from('users')
            .select('phone')
            .eq('id', userId)
            .maybeSingle();
        phone = profile?['phone'] as String?;
      }

      await _supabase.from('launch_interest').upsert({
        'phone':   phone ?? '',
        'area':    _area,
        'pincode': _pincode,
        'lat':     _pin.latitude,
        'lng':     _pin.longitude,
      });

      if (mounted) {
        setState(() {
          _notifyLoading = false;
          _notifyDone    = true;
        });
        HapticFeedback.heavyImpact();
      }
    } catch (e) {
      debugPrint('Notify me error: $e');
      if (mounted) setState(() => _notifyLoading = false);
    }
  }

  void _onConfirm() {
    HapticFeedback.mediumImpact();
    context.push('/address-confirm', extra: {
      'lat':          _pin.latitude,
      'lng':          _pin.longitude,
      'area':         _area,
      'city':         _city,
      'pincode':      _pincode,
      'full_address': _fullAddress,
      'isOnboarding': widget.isOnboarding,
    });
  }

  // ── BUILD ─────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final botPad  = MediaQuery.of(context).padding.bottom;
    final hasAddr = _area.isNotEmpty || _city.isNotEmpty;

    return Scaffold(
      body: Stack(children: [

        // ── Map ──────────────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(
              target: _pin, zoom: 15),
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            ctrl.animateCamera(
                CameraUpdate.newLatLngZoom(_pin, 16));
          },
          onCameraMove: (pos) => setState(() {
            _pin       = pos.target;
            _pinMoving = true;
          }),
          onCameraIdle: () => _reverseGeocode(_pin),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          mapType: MapType.normal,
          padding: const EdgeInsets.only(bottom: 240),
        ),

        // ── Centre pin ────────────────────────────────────────
        Center(
          child: AnimatedBuilder(
            animation: _bounceAnim,
            builder: (_, child) => Transform.translate(
                offset: Offset(0, _bounceAnim.value),
                child: child),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Shadow
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width:  _pinMoving ? 14 : 22,
                height: _pinMoving ? 5  : 7,
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10))),
              // Pin
              Icon(Icons.location_pin,
                  color: _isServiceable ? _cyan : _red,
                  size: _pinMoving ? 42 : 52,
                  shadows: [Shadow(
                      color: Colors.black.withValues(alpha: 0.18),
                      blurRadius: 8,
                      offset: const Offset(0, 4))]),
              const SizedBox(height: 52),
            ]),
          ),
        ),

        // ── Top bar ───────────────────────────────────────────
        Positioned(top: 0, left: 0, right: 0,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  const Color(0xFF0C4A6E).withValues(alpha: 0.95),
                  Colors.transparent,
                ]),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.12),
                            blurRadius: 8)]),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: _ink, size: 16))),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.10),
                            blurRadius: 10)]),
                      child: Row(children: [
                        Icon(Icons.touch_app_rounded,
                            color: _isServiceable ? _cyan : _red,
                            size: 16),
                        const SizedBox(width: 8),
                        Text(
                          _pinMoving
                              ? 'Drag to adjust…'
                              : 'Move map to set location',
                          style: const TextStyle(
                              color: _muted, fontSize: 13)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),

        // ── My location FAB ───────────────────────────────────
        Positioned(right: 16, bottom: 260,
          child: Column(children: [
            _fab(Icons.my_location_rounded, _detectAndMove),
            const SizedBox(height: 8),
            _fab(Icons.add, () => _mapController
                ?.animateCamera(CameraUpdate.zoomIn())),
            const SizedBox(height: 4),
            _fab(Icons.remove, () => _mapController
                ?.animateCamera(CameraUpdate.zoomOut())),
          ]),
        ),

        // ── Bottom card ───────────────────────────────────────
        Positioned(bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                  top: Radius.circular(24)),
              boxShadow: [BoxShadow(
                  color: Colors.black12, blurRadius: 20,
                  offset: Offset(0, -4))]),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2))),

              Padding(
                padding: EdgeInsets.fromLTRB(
                    20, 14, 20, 14 + botPad),
                child: _geocoding || _pinMoving
                    ? _buildLoadingCard()
                    : _isServiceable
                        ? _buildServiceableCard(hasAddr)
                        : _buildNotServiceableCard(),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Loading skeleton ──────────────────────────────────────
  Widget _buildLoadingCard() {
    return Column(children: [
      Row(children: [
        Container(width: 44, height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14))),
        const SizedBox(width: 12),
        Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Container(height: 14, width: 140,
            decoration: BoxDecoration(
              color: const Color(0xFFF1F5F9),
              borderRadius: BorderRadius.circular(4))),
          const SizedBox(height: 6),
          Container(height: 10, width: 200,
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(4))),
        ]),
      ]),
      const SizedBox(height: 16),
      Container(height: 54, width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFE2E8F0),
          borderRadius: BorderRadius.circular(16))),
    ]);
  }

  // ── Serviceable card ──────────────────────────────────────
  Widget _buildServiceableCard(bool hasAddr) {
    return Column(children: [
      // Address row
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
                colors: [_cyan, _cyanDk]),
            borderRadius: BorderRadius.circular(14)),
          child: const Icon(Icons.location_on_rounded,
              color: Colors.white, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // Serviceable badge
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFFECFDF5),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: const Color(0xFF6EE7B7))),
            child: Row(mainAxisSize: MainAxisSize.min,
                children: [
              Container(width: 5, height: 5,
                decoration: const BoxDecoration(
                    color: Color(0xFF10B981),
                    shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('Service available here',
                  style: TextStyle(
                      color: Color(0xFF059669),
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ])),
          Text(
            _area.isNotEmpty ? _area : 'Move pin to select',
            style: const TextStyle(fontWeight: FontWeight.w900,
                fontSize: 16, color: _ink),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          if (_fullAddress.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(_fullAddress,
                style: const TextStyle(
                    color: _muted, fontSize: 12),
                maxLines: 2,
                overflow: TextOverflow.ellipsis),
          ],
          if (_pincode.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('📮 $_pincode',
                style: const TextStyle(
                    color: _faint, fontSize: 11)),
          ],
        ])),
      ]),

      const SizedBox(height: 16),

      // Confirm button
      GestureDetector(
        onTap: hasAddr ? _onConfirm : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          width: double.infinity, height: 54,
          decoration: BoxDecoration(
            gradient: hasAddr
                ? const LinearGradient(
                    colors: [_cyan, _cyanDk]) : null,
            color: hasAddr ? null : const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(16),
            boxShadow: hasAddr
                ? [BoxShadow(
                    color: _cyan.withValues(alpha: 0.35),
                    blurRadius: 14,
                    offset: const Offset(0, 5))]
                : []),
          child: Center(
            child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
              Icon(Icons.check_circle_outline_rounded,
                  color: hasAddr ? Colors.white : _faint,
                  size: 18),
              const SizedBox(width: 8),
              Text('Confirm Location',
                  style: TextStyle(
                    color: hasAddr ? Colors.white : _faint,
                    fontWeight: FontWeight.w900,
                    fontSize: 15)),
            ]),
          ),
        ),
      ),
    ]);
  }

  // ── Not serviceable card ──────────────────────────────────
  Widget _buildNotServiceableCard() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [

      // Area + not serviceable badge
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44, height: 44,
          decoration: BoxDecoration(
            color: _redLt,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: _red.withValues(alpha: 0.25))),
          child: const Icon(Icons.location_off_rounded,
              color: _red, size: 22)),
        const SizedBox(width: 12),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(
                horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: _redLt,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                  color: _red.withValues(alpha: 0.30))),
            child: Row(mainAxisSize: MainAxisSize.min,
                children: [
              Container(width: 5, height: 5,
                decoration: const BoxDecoration(
                    color: _red, shape: BoxShape.circle)),
              const SizedBox(width: 5),
              const Text('Not available yet',
                  style: TextStyle(color: _red,
                      fontSize: 10,
                      fontWeight: FontWeight.w700)),
            ])),
          Text(
            _area.isNotEmpty ? _area : 'This location',
            style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16, color: _ink),
            maxLines: 1, overflow: TextOverflow.ellipsis),
          if (_pincode.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text('📮 $_pincode',
                style: const TextStyle(
                    color: _faint, fontSize: 11)),
          ],
        ])),
      ]),

      const SizedBox(height: 12),

      // Coming soon info
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _amberLt,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: _amber.withValues(alpha: 0.30))),
        child: Row(children: [
          const Text('🚀', style: TextStyle(fontSize: 20)),
          const SizedBox(width: 10),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
            const Text('Launching here soon!',
                style: TextStyle(color: _amber,
                    fontSize: 12, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(
              'We currently serve Vile Parle, Juhu & Andheri. '
              'Get notified when we launch in ${_area.isNotEmpty ? _area : 'your area'}!',
              style: const TextStyle(
                  color: _muted, fontSize: 11, height: 1.4)),
          ])),
        ]),
      ),

      const SizedBox(height: 12),

      // Two buttons: Notify me + Change location
      Row(children: [
        // Notify me
        Expanded(
          flex: 3,
          child: GestureDetector(
            onTap: _notifyDone ? null : _notifyMe,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 52,
              decoration: BoxDecoration(
                gradient: _notifyDone
                    ? null
                    : const LinearGradient(
                        colors: [Color(0xFF10B981),
                            Color(0xFF059669)]),
                color: _notifyDone
                    ? const Color(0xFFECFDF5) : null,
                borderRadius: BorderRadius.circular(14),
                border: _notifyDone
                    ? Border.all(
                        color: const Color(0xFF6EE7B7)) : null,
                boxShadow: _notifyDone
                    ? []
                    : [BoxShadow(
                        color: const Color(0xFF10B981)
                            .withValues(alpha: 0.30),
                        blurRadius: 12,
                        offset: const Offset(0, 4))]),
              child: Center(
                child: _notifyLoading
                    ? const SizedBox(width: 20, height: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5))
                    : Row(
                        mainAxisAlignment:
                            MainAxisAlignment.center,
                        children: [
                        Text(
                          _notifyDone
                              ? '✓ You\'re on the list!'
                              : '🔔 Notify Me',
                          style: TextStyle(
                            color: _notifyDone
                                ? const Color(0xFF059669)
                                : Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w800)),
                      ]),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Change location
        Expanded(
          flex: 2,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border, width: 1.5)),
              child: const Center(
                child: Text('Change',
                    style: TextStyle(color: _ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w800))),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _fab(IconData icon, VoidCallback onTap) =>
      GestureDetector(
        onTap: () { HapticFeedback.lightImpact(); onTap(); },
        child: Container(
          width: 42, height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [BoxShadow(
                color: Colors.black.withValues(alpha: 0.12),
                blurRadius: 10,
                offset: const Offset(0, 3))]),
          child: Icon(icon, size: 20, color: _ink)),
      );
}