import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../services/supabase_service.dart';
import 'geofence_service.dart';

class LocationPickerScreen extends StatefulWidget {
  final double? initialLat;
  final double? initialLng;
  final String? initialArea;
  final String? initialCity;
  final String? initialPincode;
  final String? initialFullAddress;
  final bool    isOnboarding;
  // Present only when arriving from a search result — used to detect and
  // offer saving a correction if the customer drags meaningfully far
  // from where Google originally placed this result.
  final String? placeId;
  final String? searchLabel;
  final double? originalLat;
  final double? originalLng;

  const LocationPickerScreen({
    super.key,
    this.initialLat,
    this.initialLng,
    this.initialArea,
    this.initialCity,
    this.initialPincode,
    this.initialFullAddress,
    this.isOnboarding = false,
    this.placeId,
    this.searchLabel,
    this.originalLat,
    this.originalLng,
  });

  @override
  State<LocationPickerScreen> createState() =>
      _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen>
    with SingleTickerProviderStateMixin {
  final _supabase = Supabase.instance.client;

  GoogleMapController? _mapController;
  // Fraction of raw finger movement the camera actually pans by — see
  // the GestureDetector wrapping GoogleMap below. 1.0 = matches native
  // behavior (no damping). 0.5 = half as fast (map moves half as far
  // as your finger travels). Tune this single number if it still feels
  // too fast/slow after testing — no other code needs to change.
  static const double _dragDampFactor = 0.5;
  LatLng _pin = const LatLng(19.1136, 72.8697);

  String _area        = '';
  String _city        = '';
  String _pincode     = '';
  String _fullAddress = '';
  bool   _geocoding   = false;
  bool   _pinMoving   = false;
  // Set right before a programmatic camera move (e.g. landing here from a
  // search result). Google Maps fires onCameraIdle for BOTH user drags AND
  // programmatic animateCamera() calls — without this guard, the correct
  // forward-geocoded search result (place name -> coordinates) was being
  // immediately overwritten by a reverse-geocode (coordinates -> nearest
  // address) the moment our own animateCamera() call settled, and reverse
  // geocoding commonly snaps to the nearest ROAD rather than the exact
  // building — producing the "right area, wrong street" symptom even
  // though the pin itself was sitting at the correct coordinates.
  bool   _suppressNextCameraIdle = false;

  // Serviceability — NOTE: this no longer blocks saving the address. It's
  // now purely informational (shows a "not bookable yet" banner + still
  // lets the customer save the address and continue browsing). The actual
  // booking gate lives in booking_flow_screen.dart.
  bool   _isServiceable    = true;
  bool   _notifyLoading    = false;
  bool   _notifyDone       = false;

  // Active service ZONES (polygons), fetched ONCE (not per pin-drag) from
  // the admin-managed `service_zones` table. This REPLACES the old
  // pincode-based `_activePincodes` set — a pincode is a big, fixed
  // government boundary that can't distinguish a well-mapped society from
  // a chawl sitting in the same pincode. Polygons are admin-drawn shapes,
  // so coverage can be traced exactly around the buildings/streets that
  // are actually meant to be served, and the same "point inside shape?"
  // check is done locally against this cached list every time the pin
  // settles — same pattern as before, just a richer shape than a flat set.
  List<ServiceZone> _activeZones = [];
  bool _areasLoaded = false;

  // Pin bounce animation
  late AnimationController _bounceCtrl;
  late Animation<double>   _bounceAnim;

  // ── Map padding ────────────────────────────────────────────
  // GoogleMap's `padding` tells the SDK's own camera/target logic to
  // treat this many px at the bottom as reserved (for the bottom sheet),
  // which shifts what the SDK considers the *visual center* of the map
  // upward by half this amount. Our fixed center-pin overlay MUST use
  // this exact same value (see the `Center` + `Padding` combo in build())
  // or the two disagree about where "center" is: the map renders the
  // camera target ~ (bottomPadding / 2) px higher on screen than a plain
  // `Center()` widget would place a fixed overlay. At typical zoom levels
  // that mismatch alone is tens of meters on the ground — this was the
  // root cause of the "right street, wrong building" symptom, entirely
  // independent of any coordinate/data bug.
  static const double _mapBottomPadding = 240;

  // ── Colours ────────────────────────────────────────────────
  static const _cyan   = Color(0xFF00B1FC);
  static const _cyanDk = Color(0xFF00B1FC);
  static const _ink    = Color(0xFF0F172A);
  static const _muted  = Color(0xFF64748B);
  static const _faint  = Color(0xFF94A3B8);
  static const _border = Color(0xFFE2E8F0);
  static const _red    = Color(0xFFDC2626);
  static const _redLt  = Color(0xFFFEF2F2);
  static const _amber  = Color(0xFFD97706);
  static const _amberLt= Color(0xFFFFFBEB);

  /// Polygon-based match — replaces the old flat pincode-set lookup.
  /// Checks whether [point] falls inside ANY admin-drawn service zone.
  /// Fails open (returns true) if no zones are configured, same
  /// behaviour as before when `_activePincodes` was empty — so a fresh
  /// install with nothing drawn yet doesn't block every customer.
  bool _checkServiceable(LatLng point) =>
      GeofenceService.isServiceable(point, _activeZones);

  Future<void> _loadActiveAreas() async {
    try {
      _activeZones = await GeofenceService.loadActiveZones();
    } catch (e) {
      debugPrint('Load active zones error: $e');
      _activeZones = [];
    } finally {
      _areasLoaded = true;
    }
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

    _init();
  }

  Future<void> _init() async {
    await _loadActiveAreas();
    if (!mounted) return;

    if (widget.initialLat != null && widget.initialLng != null) {
      debugPrint('[LOCPICKER] received initialLat=${widget.initialLat} '
          'initialLng=${widget.initialLng} pincode=${widget.initialPincode} '
          'fullAddress=${widget.initialFullAddress}');
      _pin         = LatLng(widget.initialLat!, widget.initialLng!);
      _area        = widget.initialArea        ?? '';
      _city        = widget.initialCity        ?? '';
      _pincode     = widget.initialPincode     ?? '';
      _fullAddress = widget.initialFullAddress ?? '';
      // The map's camera was already positioned (at a stale default) by
      // onMapCreated before this async init finished — setting _pin alone
      // doesn't move the already-rendered camera. Without this explicit
      // animate call, the map kept showing wherever it first rendered
      // while the address text correctly showed the searched location —
      // exactly the "map shows something different" bug. _detectAndMove()
      // (the GPS path) already did this correctly; this branch didn't.
      if (mounted) {
        setState(() {
          // Serviceability is coordinate-based now, so it can be
          // computed immediately — no need to wait on reverse geocoding
          // just to know if this pin can be booked.
          _isServiceable = _checkServiceable(_pin);
        });
        debugPrint('[LOCPICKER] animating camera to _pin=$_pin');
        _suppressNextCameraIdle = true;
        _mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(_pin, 16));
      }
      // Reverse geocode is still needed if we don't already have a
      // pincode/area to DISPLAY — but it no longer decides
      // serviceability, that's already been set above from the polygon.
      if (_pincode.isEmpty) {
        _reverseGeocode(_pin);
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
      setState(() {
        _pin = latlng;
        _isServiceable = _checkServiceable(latlng);
      });
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
        ].where((e) => e != null && e.isNotEmpty).join(', ');

        setState(() {
          _area        = area;
          _city        = city;
          _pincode     = pincode;
          _fullAddress = full;
          // Serviceability is decided by polygon, checked against the
          // exact coordinate — pincode here is purely for display now.
          _isServiceable = _checkServiceable(latlng);
          _pinMoving   = false;
          _geocoding   = false;
        });

        // Bounce pin
        _bounceCtrl.forward(from: 0)
            .then((_) => _bounceCtrl.reverse());
      } else if (mounted) {
        // No placemark resolved for text display, but we can still know
        // whether this exact point is servable from the polygon alone.
        setState(() {
          _isServiceable = _checkServiceable(latlng);
          _pinMoving = false;
          _geocoding = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isServiceable = _checkServiceable(latlng);
          _geocoding = false;
          _pinMoving = false;
        });
      }
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

  // If this came from a search result and the customer dragged the pin
  // meaningfully far (>30m) from where Google originally placed it,
  // submit that as a pending correction for admin review. Runs silently
  // in the background — never blocks or delays confirming the address,
  // since this is a nice-to-have data-quality signal, not something the
  // customer should ever have to wait on or see fail.
  Future<void> _maybeSubmitCorrection() async {
    debugPrint('[CORRECTION] checking — placeId=${widget.placeId} '
        'originalLat=${widget.originalLat} originalLng=${widget.originalLng} '
        'currentPin=$_pin');
    if (widget.placeId == null ||
        widget.originalLat == null ||
        widget.originalLng == null) {
      debugPrint('[CORRECTION] skipped — no placeId/original coords '
          '(this pin didn\'t come from a search result)');
      return;
    }
    final movedMeters = Geolocator.distanceBetween(
      widget.originalLat!, widget.originalLng!,
      _pin.latitude, _pin.longitude,
    );
    debugPrint('[CORRECTION] moved ${movedMeters.toStringAsFixed(1)}m '
        'from original Google result');
    if (movedMeters < 30) {
      debugPrint('[CORRECTION] skipped — under 30m threshold, treated as '
          'minor fine-tuning not a real correction');
      return;
    }

    try {
      await _supabase.from('location_corrections').insert({
        'place_id':              widget.placeId,
        'search_label':          widget.searchLabel ?? _fullAddress,
        'original_lat':          widget.originalLat,
        'original_lng':          widget.originalLng,
        'corrected_lat':         _pin.latitude,
        'corrected_lng':         _pin.longitude,
        'corrected_area':        _area,
        'corrected_city':        _city,
        'corrected_pincode':     _pincode,
        'corrected_full_address': _fullAddress,
      });
      debugPrint('[CORRECTION] submitted for place_id=${widget.placeId}, '
          'moved ${movedMeters.toStringAsFixed(0)}m');
    } catch (e) {
      debugPrint('[CORRECTION] submit failed (non-fatal): $e');
    }
  }

  void _onConfirm() {
    HapticFeedback.mediumImpact();
    _maybeSubmitCorrection(); // fire-and-forget, don't await
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
        // Native map dragging is disabled below (scrollGesturesEnabled:
        // false) and replaced with this GestureDetector, which moves the
        // camera by only a FRACTION (_dragDampFactor) of the actual
        // finger movement. The Maps SDK itself has no built-in "pan
        // sensitivity" setting — dragging always tracks the finger 1:1
        // in screen pixels regardless of zoom level, which is what felt
        // "too fast/jumpy" for precise pin placement. This is the only
        // way to genuinely slow that down.
        //
        // NOTE ON DIRECTION: CameraUpdate.scrollBy's sign convention
        // couldn't be verified interactively while writing this — the
        // values below assume standard "content follows your finger"
        // behavior (matching Google Maps' own app). If dragging feels
        // INVERTED (map moves opposite to your finger) once tested,
        // simply flip both signs in the scrollBy() call below — that's
        // the only change needed, nothing else is affected.
        GestureDetector(
          onPanUpdate: (details) {
            if (_mapController == null) return;
            _mapController!.moveCamera(
              CameraUpdate.scrollBy(
                -details.delta.dx * _dragDampFactor,
                -details.delta.dy * _dragDampFactor,
              ),
            );
          },
          child: GoogleMap(
          initialCameraPosition: CameraPosition(
              target: _pin, zoom: 15),
          onMapCreated: (ctrl) {
            _mapController = ctrl;
            _suppressNextCameraIdle = true;
            ctrl.animateCamera(
                CameraUpdate.newLatLngZoom(_pin, 16));
          },
          onCameraMove: (pos) => setState(() {
            _pin       = pos.target;
            _pinMoving = true;
          }),
          onCameraIdle: () {
            if (_suppressNextCameraIdle) {
              debugPrint('[LOCPICKER] onCameraIdle suppressed (programmatic move)');
              _suppressNextCameraIdle = false;
              return;
            }
            _reverseGeocode(_pin);
          },
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          mapType: MapType.normal,
          padding: const EdgeInsets.only(bottom: _mapBottomPadding),
          // Native drag is off — our GestureDetector above handles
          // panning manually, at a damped rate. Pinch-zoom stays native
          // (zoomGesturesEnabled defaults to true) since that wasn't
          // reported as a problem.
          scrollGesturesEnabled: false,
          ),
        ),

        // ── Centre pin ────────────────────────────────────────
        // The pin icon's pointy TIP (not its visual center) marks the
        // actual coordinate — for a standard teardrop marker icon, that
        // tip sits at the very bottom of the icon's bounding box. So the
        // icon needs to be shifted straight up by exactly half its own
        // size to align the tip with the true screen center (where the
        // map camera's target actually is). The previous approach used
        // an empty SizedBox below the icon to try to achieve this
        // indirectly, but the box height didn't precisely match — small
        // pixel misalignment here translates directly into a
        // real-world "few meters off" offset once decoded from the map.
        //
        // CRITICAL: this Center() must ALSO be wrapped in the same
        // bottom Padding as the GoogleMap's own `padding` property above.
        // GoogleMap's `padding` shifts the SDK's internal notion of the
        // map's visual center upward by half of `_mapBottomPadding` (to
        // account for the bottom sheet covering part of the screen) —
        // but a bare `Center()` on this overlay has no idea that
        // happened, and keeps centering on the full, unpadded screen.
        // That mismatch (half of 240px ≈ 120px on screen) is what was
        // silently offsetting the fixed pin icon from where the map's
        // camera target (i.e. the coordinate actually being used) was
        // rendered — independent of any bug in the lat/lng data itself.
        // Wrapping in the identical padding here makes both agree on
        // where "center" is.
        Padding(
          padding: const EdgeInsets.only(bottom: _mapBottomPadding),
          child: Center(
            child: Builder(builder: (_) {
              final pinSize = _pinMoving ? 42.0 : 52.0;
              return Transform.translate(
                offset: Offset(0, -pinSize / 2),
                child: AnimatedBuilder(
                  animation: _bounceAnim,
                  builder: (_, child) => Transform.translate(
                      offset: Offset(0, _bounceAnim.value),
                      child: child),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.location_pin,
                        color: _isServiceable ? _cyan : _red,
                        size: pinSize,
                        shadows: [Shadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 8,
                            offset: const Offset(0, 4))]),
                    // Ground shadow — sits right at the tip's contact
                    // point, not floating above the pin.
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width:  _pinMoving ? 14 : 22,
                      height: _pinMoving ? 5  : 7,
                      margin: const EdgeInsets.only(top: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10))),
                  ]),
                ),
              );
            }),
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
                // Show the loading skeleton ONLY before we've ever resolved
                // an address at all (true first load). Once _fullAddress
                // has a real value, keep showing the actual card during
                // every subsequent drag — it just displays the previous
                // (slightly stale) address until the new one resolves,
                // instead of flashing to a blank skeleton on every single
                // drag. This is what makes "Confirm Location" feel present
                // the whole time, not something that only "appears after
                // you finish dragging".
                child: (_fullAddress.isEmpty &&
                        (_geocoding || _pinMoving || !_areasLoaded))
                    ? _buildLoadingCard()
                    : _isServiceable
                        ? _buildServiceableCard(hasAddr)
                        : _buildNotServiceableCard(hasAddr),
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
                    color: Colors.black.withValues(alpha: 0.35),
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

  // ── Not (yet) serviceable card ─────────────────────────────
  // Informational only — the customer can still save this address and
  // browse the app. Only actually BOOKING is blocked, and that check
  // happens later in booking_flow_screen.dart.
  Widget _buildNotServiceableCard(bool hasAddr) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start,
        children: [

      // Area + not-yet-bookable badge
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
              const Text('Not bookable yet',
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

      // Coming soon info — no hardcoded area names anymore
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
              'You can still save this address — you just won\'t be able to '
              'book a service here until we launch in '
              '${_area.isNotEmpty ? _area : 'your area'}.',
              style: const TextStyle(
                  color: _muted, fontSize: 11, height: 1.4)),
          ])),
        ]),
      ),

      const SizedBox(height: 12),

      // Notify me + Change (secondary actions)
      Row(children: [
        Expanded(
          child: GestureDetector(
            onTap: _notifyDone ? null : _notifyMe,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              height: 48,
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
                        color: const Color(0xFF6EE7B7)) : null),
              child: Center(
                child: _notifyLoading
                    ? const SizedBox(width: 18, height: 18,
                        child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5))
                    : Text(
                        _notifyDone
                            ? '✓ On the list!'
                            : '🔔 Notify Me',
                        style: TextStyle(
                            color: _notifyDone
                                ? const Color(0xFF059669)
                                : Colors.white,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w800)),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _border, width: 1.5)),
              child: const Center(
                child: Text('Change',
                    style: TextStyle(color: _ink,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800))),
            ),
          ),
        ),
      ]),

      const SizedBox(height: 10),

      // Save address anyway — the actual path forward. Booking itself
      // stays gated later; this just lets them save the address and keep
      // browsing the app.
      GestureDetector(
        onTap: hasAddr ? _onConfirm : null,
        child: Container(
          width: double.infinity, height: 48,
          decoration: BoxDecoration(
            color: hasAddr ? _cyanBgSoft : const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: hasAddr ? _cyan.withValues(alpha: 0.4) : _border)),
          child: Center(
            child: Text('Save Address Anyway',
                style: TextStyle(
                    color: hasAddr ? _cyanDk : _faint,
                    fontSize: 13,
                    fontWeight: FontWeight.w800)),
          ),
        ),
      ),
    ]);
  }

  static const _cyanBgSoft = Color(0xFFECFEFF);

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