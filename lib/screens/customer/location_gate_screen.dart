import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shown after login if user has no saved address.
/// Two options: Use my location OR Search manually
class LocationGateScreen extends StatefulWidget {
  const LocationGateScreen({super.key});

  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

class _LocationGateScreenState extends State<LocationGateScreen> {
  bool _locLoading = false;
  String? _error;

  Future<void> _useMyLocation() async {
    setState(() { _locLoading = true; _error = null; });

    try {
      // 1. Check if service enabled
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error = 'Please turn on GPS / Location Services';
          _locLoading = false;
        });
        return;
      }

      // 2. Check permission
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          setState(() { _error = 'Location permission denied'; _locLoading = false; });
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() { _error = 'Location permission permanently denied. Enable in Settings.'; _locLoading = false; });
        return;
      }

      // 3. Get position
      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(accuracy: LocationAccuracy.best),
      );

      if (mounted) {
        setState(() => _locLoading = false);
        // Go to map picker with current location
        context.push('/location-picker', extra: {
          'lat': pos.latitude,
          'lng': pos.longitude,
          'isOnboarding': true,
        });
      }
    } catch (e) {
      setState(() { _error = 'Could not get location. Try again.'; _locLoading = false; });
    }
  }

  void _searchManually() {
    context.push('/location-search', extra: {'isOnboarding': true});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(children: [
            const Spacer(),

            // Illustration
            Container(
              width: 140, height: 140,
              decoration: BoxDecoration(
                color: const Color(0xFFECFEFF),
                shape: BoxShape.circle,
                boxShadow: [BoxShadow(
                  color: const Color(0xFF06B6D4).withValues(alpha: 0.15),
                  blurRadius: 30, spreadRadius: 5)],
              ),
              child: const Center(child: Text('📍', style: TextStyle(fontSize: 60))),
            ),
            const SizedBox(height: 32),

            const Text('Where should we clean?',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
            const SizedBox(height: 12),
            const Text(
              'Set your location so we can\nassign the nearest cleaner',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, color: Color(0xFF64748B), height: 1.5)),

            const Spacer(),

            // Use my location button
            GestureDetector(
              onTap: _locLoading ? null : _useMyLocation,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                height: 58,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [BoxShadow(
                    color: const Color(0xFF06B6D4).withValues(alpha: 0.4),
                    blurRadius: 16, offset: const Offset(0, 6))],
                ),
                child: Center(
                  child: _locLoading
                      ? const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          SizedBox(width: 20, height: 20,
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5)),
                          SizedBox(width: 12),
                          Text('Detecting location…',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15)),
                        ])
                      : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          Icon(Icons.my_location_rounded, color: Colors.white, size: 22),
                          SizedBox(width: 10),
                          Text('Use My Current Location',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                        ]),
                ),
              ),
            ),

            const SizedBox(height: 14),

            // Search manually button
            GestureDetector(
              onTap: _searchManually,
              child: Container(
                width: double.infinity,
                height: 58,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.search_rounded, color: Color(0xFF0F172A), size: 22),
                  SizedBox(width: 10),
                  Text('Search My Address',
                      style: TextStyle(color: Color(0xFF0F172A), fontWeight: FontWeight.w800, fontSize: 15)),
                ]),
              ),
            ),

            if (_error != null) ...[
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFCA5A5)),
                ),
                child: Row(children: [
                  const Icon(Icons.error_outline, color: Color(0xFFDC2626), size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(_error!,
                      style: const TextStyle(color: Color(0xFFDC2626), fontSize: 12, fontWeight: FontWeight.w600))),
                ]),
              ),
            ],

            const SizedBox(height: 16),
            TextButton(
              onPressed: () => context.go('/home'),
              child: const Text('Skip for now',
                  style: TextStyle(color: Color(0xFF94A3B8), fontSize: 13)),
            ),
            const SizedBox(height: 8),
          ]),
        ),
      ),
    );
  }
}