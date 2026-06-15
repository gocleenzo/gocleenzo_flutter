import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';

/// Full-screen map with draggable pin — like Zepto/Blinkit
/// Receives optional lat/lng from location gate or search screen
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
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  GoogleMapController? _mapController;

  LatLng _pinLocation = const LatLng(19.0760, 72.8777); // Mumbai default

  String _area        = '';
  String _city        = '';
  String _pincode     = '';
  String _fullAddress = '';
  bool   _geocoding   = false;
  bool   _mapReady    = false;

  @override
  void initState() {
    super.initState();
    // Use passed location if available
    if (widget.initialLat != null && widget.initialLng != null) {
      _pinLocation = LatLng(widget.initialLat!, widget.initialLng!);
      _area        = widget.initialArea        ?? '';
      _city        = widget.initialCity        ?? '';
      _pincode     = widget.initialPincode     ?? '';
      _fullAddress = widget.initialFullAddress ?? '';
      if (_area.isEmpty) _reverseGeocode(_pinLocation);
    } else {
      _detectAndMove();
    }
  }

  @override
  void dispose() {
    _mapController?.dispose();
    super.dispose();
  }

  Future<void> _detectAndMove() async {
    try {
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.high),
      );
      final latlng = LatLng(pos.latitude, pos.longitude);
      setState(() => _pinLocation = latlng);
      _mapController?.animateCamera(CameraUpdate.newLatLngZoom(latlng, 16));
      await _reverseGeocode(latlng);
    } catch (_) {}
  }

  Future<void> _reverseGeocode(LatLng latlng) async {
    setState(() => _geocoding = true);
    try {
      final placemarks = await placemarkFromCoordinates(
        latlng.latitude, latlng.longitude,
      );
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        setState(() {
          _area    = p.subLocality ?? p.locality ?? '';
          _city    = p.locality ?? p.administrativeArea ?? '';
          _pincode = p.postalCode ?? '';
          _fullAddress = [
            p.street, p.subLocality, p.locality,
            p.administrativeArea, p.postalCode,
          ].where((e) => e != null && e.isNotEmpty).join(', ');
        });
      }
    } catch (_) {}
    setState(() => _geocoding = false);
  }

  void _onConfirm() {
    // Pass data to confirm screen
    context.push('/address-confirm', extra: {
      'lat':          _pinLocation.latitude,
      'lng':          _pinLocation.longitude,
      'area':         _area,
      'city':         _city,
      'pincode':      _pincode,
      'full_address': _fullAddress,
      'isOnboarding': widget.isOnboarding,
    });
  }

  @override
  Widget build(BuildContext context) {
    final hasAddress = _area.isNotEmpty || _city.isNotEmpty;

    return Scaffold(
      body: Stack(children: [

        // ── Full screen map ────────────────────────────────────
        GoogleMap(
          initialCameraPosition: CameraPosition(target: _pinLocation, zoom: 15),
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            setState(() => _mapReady = true);
            ctrl.animateCamera(CameraUpdate.newLatLngZoom(_pinLocation, 16));
          },
          onCameraMove: (pos) => setState(() => _pinLocation = pos.target),
          onCameraIdle: () => _reverseGeocode(_pinLocation),
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          mapType: MapType.normal,
        ),

        // ── Center pin ─────────────────────────────────────────
        Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Pin shadow
              if (_geocoding)
                const SizedBox(
                  width: 24, height: 24,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: Color(0xFF06B6D4))),
              if (!_geocoding)
                Container(
                  width: 20, height: 20,
                  decoration: BoxDecoration(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                ),
              const Icon(Icons.location_pin, color: Color(0xFF06B6D4), size: 52),
              const SizedBox(height: 36), // push pin up to center tip
            ],
          ),
        ),

        // ── Top bar ────────────────────────────────────────────
        Positioned(
          top: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Color(0xFF0891B2), Colors.transparent]),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                      ),
                      child: const Icon(Icons.arrow_back_ios_new,
                          color: Color(0xFF0F172A), size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        boxShadow: [BoxShadow(
                            color: Colors.black.withValues(alpha: 0.1), blurRadius: 8)],
                      ),
                      child: const Row(children: [
                        Icon(Icons.search_rounded, color: Color(0xFF9CA3AF), size: 18),
                        SizedBox(width: 8),
                        Text('Drag map to adjust pin',
                            style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                      ]),
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),

        // ── My location button ─────────────────────────────────
        Positioned(
          right: 16,
          bottom: 220,
          child: GestureDetector(
            onTap: _detectAndMove,
            child: Container(
              width: 48, height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15), blurRadius: 10)],
              ),
              child: const Icon(Icons.my_location_rounded,
                  color: Color(0xFF06B6D4), size: 22),
            ),
          ),
        ),

        // ── Bottom address card ────────────────────────────────
        Positioned(
          bottom: 0, left: 0, right: 0,
          child: Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 20, offset: Offset(0, -4))],
            ),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              // Handle
              Container(
                margin: const EdgeInsets.only(top: 10),
                width: 40, height: 4,
                decoration: BoxDecoration(
                    color: const Color(0xFFE2E8F0),
                    borderRadius: BorderRadius.circular(2)),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.of(context).padding.bottom),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('DELIVER HERE',
                      style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 10,
                          fontWeight: FontWeight.w800, letterSpacing: 1.5)),
                  const SizedBox(height: 10),

                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: const Color(0xFFECFEFF),
                        borderRadius: BorderRadius.circular(14)),
                      child: const Center(child: Icon(Icons.location_on_rounded,
                          color: Color(0xFF06B6D4), size: 24)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _geocoding
                          ? const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text('Detecting address…',
                                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15,
                                      color: Color(0xFF64748B))),
                            ])
                          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(
                                _area.isNotEmpty ? _area : 'Move pin to select location',
                                style: const TextStyle(fontWeight: FontWeight.w800,
                                    fontSize: 16, color: Color(0xFF0F172A)),
                                maxLines: 1, overflow: TextOverflow.ellipsis,
                              ),
                              if (_fullAddress.isNotEmpty) ...[
                                const SizedBox(height: 3),
                                Text(_fullAddress,
                                    style: const TextStyle(color: Color(0xFF64748B), fontSize: 12),
                                    maxLines: 2, overflow: TextOverflow.ellipsis),
                              ],
                            ]),
                    ),
                  ]),

                  const SizedBox(height: 18),

                  // Confirm button
                  GestureDetector(
                    onTap: hasAddress && !_geocoding ? _onConfirm : null,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: double.infinity,
                      height: 54,
                      decoration: BoxDecoration(
                        gradient: hasAddress && !_geocoding
                            ? const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)])
                            : null,
                        color: hasAddress && !_geocoding ? null : const Color(0xFFE2E8F0),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: hasAddress && !_geocoding
                            ? [BoxShadow(
                                color: const Color(0xFF06B6D4).withValues(alpha: 0.4),
                                blurRadius: 16, offset: const Offset(0, 6))]
                            : [],
                      ),
                      child: Center(
                        child: Text(
                          _geocoding ? 'Detecting…' : 'Confirm Location',
                          style: TextStyle(
                            color: hasAddress && !_geocoding ? Colors.white : const Color(0xFF94A3B8),
                            fontWeight: FontWeight.w800, fontSize: 15),
                        ),
                      ),
                    ),
                  ),
                ]),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}