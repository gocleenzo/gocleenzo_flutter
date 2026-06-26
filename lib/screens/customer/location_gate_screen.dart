import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:geolocator/geolocator.dart';

class LocationGateScreen extends StatefulWidget {
  const LocationGateScreen({super.key});
  @override
  State<LocationGateScreen> createState() => _LocationGateScreenState();
}

class _LocationGateScreenState extends State<LocationGateScreen>
    with SingleTickerProviderStateMixin {
  bool    _locLoading = false;
  String? _error;

  late AnimationController _pulseCtrl;
  late Animation<double>   _pulseAnim;

  static const _cyan   = Color(0xFF06B6D4);
  static const _cyanDk = Color(0xFF0891B2);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 1800))
      ..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(
            parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _useMyLocation() async {
    setState(() { _locLoading = true; _error = null; });
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() {
          _error      = 'Please turn on GPS / Location Services';
          _locLoading = false;
        });
        return;
      }
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) {
          setState(() {
            _error      = 'Location permission denied';
            _locLoading = false;
          });
          return;
        }
      }
      if (perm == LocationPermission.deniedForever) {
        setState(() {
          _error      = 'Enable location in Settings to continue';
          _locLoading = false;
        });
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best));
      if (mounted) {
        setState(() => _locLoading = false);
        context.push('/location-picker', extra: {
          'lat':          pos.latitude,
          'lng':          pos.longitude,
          'isOnboarding': true,
        });
      }
    } catch (_) {
      setState(() {
        _error      = 'Could not get location. Try again.';
        _locLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    final botPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Column(children: [

        // ── Gradient hero top ──────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C4A6E), _cyanDk, _cyan],
            ),
          ),
          child: Stack(children: [
            // Deco circles
            Positioned(top: -40, right: -40,
              child: Container(width: 180, height: 180,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle))),
            Positioned(top: 40, right: 30,
              child: Container(width: 80, height: 80,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  shape: BoxShape.circle))),

            SafeArea(
              bottom: false,
              child: Padding(
                padding: EdgeInsets.fromLTRB(20, topPad > 0 ? 10 : 20, 20, 36),
                child: Column(children: [
                  // Pulsing location icon
                  ScaleTransition(
                    scale: _pulseAnim,
                    child: Stack(alignment: Alignment.center, children: [
                      Container(width: 120, height: 120,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.08),
                          shape: BoxShape.circle)),
                      Container(width: 88, height: 88,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          shape: BoxShape.circle)),
                      Container(width: 64, height: 64,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.20),
                          shape: BoxShape.circle),
                        child: const Center(
                          child: Text('📍',
                              style: TextStyle(fontSize: 30)))),
                    ]),
                  ),
                  const SizedBox(height: 20),
                  const Text('Where should we clean?',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white,
                          fontSize: 22, fontWeight: FontWeight.w900,
                          height: 1.2)),
                  const SizedBox(height: 8),
                  Text('We serve Vile Parle, Juhu & Andheri',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.75),
                          fontSize: 13)),
                ]),
              ),
            ),

            // Wave bottom
            Positioned(left: 0, right: 0, bottom: 0,
              child: SizedBox(
                height: 28,
                child: CustomPaint(painter: _WavePainter()),
              )),
          ]),
        ),

        // ── Body ──────────────────────────────────────────────
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(20, 28, 20, botPad + 20),
            child: Column(children: [

              // Service area chips
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _border),
                  boxShadow: [BoxShadow(
                      color: Colors.black.withValues(alpha: 0.04),
                      blurRadius: 10, offset: const Offset(0, 3))]),
                child: Column(children: [
                  Row(children: [
                    Container(width: 6, height: 6,
                      decoration: const BoxDecoration(
                          color: Color(0xFF10B981),
                          shape: BoxShape.circle)),
                    const SizedBox(width: 8),
                    const Text('Currently serving',
                        style: TextStyle(color: Color(0xFF059669),
                            fontSize: 11, fontWeight: FontWeight.w700)),
                  ]),
                  const SizedBox(height: 12),
                  Row(children: [
                    _areaChip('📍', 'Vile Parle'),
                    const SizedBox(width: 8),
                    _areaChip('📍', 'Juhu'),
                    const SizedBox(width: 8),
                    _areaChip('📍', 'Andheri'),
                  ]),
                ]),
              ),

              const Spacer(),

              // Use GPS button
              GestureDetector(
                onTap: _locLoading ? null : _useMyLocation,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: double.infinity, height: 56,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [_cyan, _cyanDk]),
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: [BoxShadow(
                        color: _cyan.withValues(alpha: 0.35),
                        blurRadius: 16,
                        offset: const Offset(0, 6))]),
                  child: Center(
                    child: _locLoading
                        ? const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(width: 20, height: 20,
                                child: CircularProgressIndicator(
                                    color: Colors.white, strokeWidth: 2.5)),
                              SizedBox(width: 12),
                              Text('Detecting location…',
                                  style: TextStyle(color: Colors.white,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 15)),
                            ])
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.my_location_rounded,
                                  color: Colors.white, size: 20),
                              SizedBox(width: 10),
                              Text('Use My Current Location',
                                  style: TextStyle(color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 15)),
                            ]),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Divider with OR
              Row(children: [
                const Expanded(child: Divider(color: _border)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Text('OR',
                      style: TextStyle(color: _faint, fontSize: 11,
                          fontWeight: FontWeight.w700))),
                const Expanded(child: Divider(color: _border)),
              ]),

              const SizedBox(height: 12),

              // Search manually button
              GestureDetector(
                onTap: () => context.push(
                    '/location-search',
                    extra: {'isOnboarding': true}),
                child: Container(
                  width: double.infinity, height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border, width: 1.5),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 3))]),
                  child: const Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Icon(Icons.search_rounded, color: _ink, size: 20),
                    SizedBox(width: 10),
                    Text('Search My Address',
                        style: TextStyle(color: _ink,
                            fontWeight: FontWeight.w800, fontSize: 15)),
                  ]),
                ),
              ),

              // Error message
              if (_error != null) ...[
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCA5A5))),
                  child: Row(children: [
                    const Icon(Icons.error_outline,
                        color: Color(0xFFDC2626), size: 16),
                    const SizedBox(width: 8),
                    Expanded(child: Text(_error!,
                        style: const TextStyle(
                            color: Color(0xFFDC2626),
                            fontSize: 12,
                            fontWeight: FontWeight.w600))),
                  ]),
                ),
              ],

              const SizedBox(height: 16),

              // Skip
              GestureDetector(
                onTap: () => context.go('/services'),
                child: const Text('Skip for now',
                    style: TextStyle(color: _faint, fontSize: 13,
                        fontWeight: FontWeight.w500)),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _areaChip(String emoji, String label) => Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFECFEFF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFA5F3FC))),
      child: Column(children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(height: 3),
        Text(label, style: const TextStyle(
            color: _cyanDk, fontSize: 10,
            fontWeight: FontWeight.w700)),
      ]),
    ),
  );
}

class _WavePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFF8FAFC)
      ..style = PaintingStyle.fill;
    final path = Path()
      ..moveTo(0, size.height)
      ..quadraticBezierTo(size.width / 4, 0, size.width / 2, size.height / 2)
      ..quadraticBezierTo(size.width * 3 / 4, size.height, size.width, 0)
      ..lineTo(size.width, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) => false;
}