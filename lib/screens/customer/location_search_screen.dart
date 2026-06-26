import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class LocationSearchScreen extends StatefulWidget {
  final bool isOnboarding;
  const LocationSearchScreen({super.key, this.isOnboarding = false});
  @override
  State<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends State<LocationSearchScreen>
    with SingleTickerProviderStateMixin {
  final _searchCtrl = TextEditingController();
  final _focus      = FocusNode();

  List<Map<String, dynamic>> _predictions = [];
  bool   _searching    = false;
  bool   _selecting    = false;
  String _sessionToken = '';

  static const _apiKey  = 'AIzaSyCr_DDF-1Aro_QuNAlzZRMOnrjKhiR20Ic';
  static const _cyan    = Color(0xFF06B6D4);
  static const _cyanDk  = Color(0xFF0891B2);
  static const _ink     = Color(0xFF0F172A);
  static const _muted   = Color(0xFF64748B);
  static const _faint   = Color(0xFF94A3B8);
  static const _border  = Color(0xFFE2E8F0);
  static const _bg      = Color(0xFFF8FAFC);

  // Recent searches (in-memory for session)
  final List<String> _recents = [
    'Vile Parle East, Mumbai',
    'Juhu, Mumbai',
    'Andheri West, Mumbai',
  ];

  @override
  void initState() {
    super.initState();
    _sessionToken =
        DateTime.now().millisecondsSinceEpoch.toString();
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _focus.requestFocus());
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _search(String query) async {
    if (query.trim().length < 3) {
      setState(() => _predictions = []);
      return;
    }
    setState(() => _searching = true);
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/autocomplete/json'
        '?input=${Uri.encodeComponent(query)}'
        '&key=$_apiKey'
        '&sessiontoken=$_sessionToken'
        '&components=country:in'
        '&location=19.1136,72.8697'
        '&radius=15000'
        '&types=geocode|establishment',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK') {
          setState(() {
            _predictions =
                (data['predictions'] as List).map((p) => {
                  'place_id':  p['place_id'],
                  'description': p['description'],
                  'main_text': p['structured_formatting']
                          ?['main_text'] ??
                      p['description'],
                  'secondary': p['structured_formatting']
                          ?['secondary_text'] ??
                      '',
                }).toList();
          });
        } else {
          setState(() => _predictions = []);
        }
      }
    } catch (_) {
      setState(() => _predictions = []);
    }
    setState(() => _searching = false);
  }

  Future<void> _selectPlace(Map<String, dynamic> place) async {
    setState(() => _selecting = true);
    HapticFeedback.selectionClick();
    try {
      final url = Uri.parse(
        'https://maps.googleapis.com/maps/api/place/details/json'
        '?place_id=${place['place_id']}'
        '&key=$_apiKey'
        '&sessiontoken=$_sessionToken'
        '&fields=geometry,formatted_address,address_components',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK') {
          final result  = data['result'];
          final lat     = result['geometry']['location']['lat'] as double;
          final lng     = result['geometry']['location']['lng'] as double;
          final fmtAddr = result['formatted_address'] as String? ?? '';

          String area = '', city = '', pincode = '';
          for (final comp in (result['address_components'] as List)) {
            final types = (comp['types'] as List).cast<String>();
            if (types.contains('sublocality_level_1') ||
                types.contains('sublocality')) {
              area = comp['long_name'];
            }
            if (types.contains('locality')) city = comp['long_name'];
            if (types.contains('postal_code')) {
              pincode = comp['long_name'];
            }
          }

          if (mounted) {
            setState(() => _selecting = false);
            context.pushReplacement('/location-picker', extra: {
              'lat':          lat,
              'lng':          lng,
              'area':         area,
              'city':         city,
              'pincode':      pincode,
              'full_address': fmtAddr,
              'isOnboarding': widget.isOnboarding,
            });
          }
        }
      }
    } catch (_) {
      if (mounted) setState(() => _selecting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: _bg,
      body: Column(children: [

        // ── Header ────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFF0C4A6E), _cyanDk, _cyan],
            ),
          ),
          child: Stack(children: [
            Positioned(top: -30, right: -30,
              child: Container(width: 140, height: 140,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.05),
                  shape: BoxShape.circle))),
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  // Back + title
                  Row(children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 36, height: 36,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.25))),
                        child: const Icon(Icons.arrow_back_ios_new,
                            color: Colors.white, size: 16)),
                    ),
                    const SizedBox(width: 12),
                    const Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                      Text('Search Location',
                          style: TextStyle(color: Colors.white,
                              fontSize: 17, fontWeight: FontWeight.w900)),
                      Text('Find your area or building',
                          style: TextStyle(color: Colors.white70,
                              fontSize: 11)),
                    ]),
                  ]),
                  const SizedBox(height: 16),

                  // Search bar
                  Container(
                    height: 50,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(
                          color: Colors.black.withValues(alpha: 0.10),
                          blurRadius: 16, offset: const Offset(0, 4))]),
                    child: Row(children: [
                      const SizedBox(width: 14),
                      const Icon(Icons.search_rounded,
                          color: _cyan, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _focus,
                          onChanged: _search,
                          style: const TextStyle(
                              fontSize: 14, color: _ink),
                          decoration: InputDecoration(
                            hintText:
                                'Area, building, landmark…',
                            hintStyle: TextStyle(
                                color: _faint, fontSize: 13),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero),
                        ),
                      ),
                      if (_searchCtrl.text.isNotEmpty)
                        GestureDetector(
                          onTap: () {
                            _searchCtrl.clear();
                            setState(() => _predictions = []);
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 8),
                            width: 28, height: 28,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded,
                                size: 14, color: _muted))),
                      if (_searching)
                        const Padding(
                          padding: EdgeInsets.only(right: 12),
                          child: SizedBox(width: 16, height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _cyan))),
                    ]),
                  ),
                ]),
              ),
            ),
          ]),
        ),

        // ── Results / suggestions ─────────────────────────────
        Expanded(
          child: _selecting
              ? Center(child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                  const CircularProgressIndicator(color: _cyan),
                  const SizedBox(height: 16),
                  Text('Loading location…',
                      style: TextStyle(color: _faint, fontSize: 13)),
                ]))
              : ListView(
                  padding: EdgeInsets.zero,
                  children: [

                    // ── GPS option ─────────────────────────────
                    _listTile(
                      leading: Container(
                        width: 44, height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                              colors: [_cyan, _cyanDk]),
                          borderRadius: BorderRadius.circular(14)),
                        child: const Icon(Icons.my_location_rounded,
                            color: Colors.white, size: 20)),
                      title: 'Use current location',
                      subtitle: 'Auto-detect via GPS',
                      onTap: () => Navigator.pop(context),
                      isFirst: true,
                    ),

                    // ── Predictions ────────────────────────────
                    if (_predictions.isNotEmpty) ...[
                      _sectionLabel('SEARCH RESULTS'),
                      ..._predictions.asMap().entries.map((e) {
                        final i = e.key;
                        final p = e.value;
                        return _listTile(
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFF1F5F9),
                              borderRadius: BorderRadius.circular(14)),
                            child: const Icon(
                                Icons.location_on_outlined,
                                color: _muted, size: 20)),
                          title: p['main_text'],
                          subtitle: p['secondary'],
                          onTap: () => _selectPlace(p),
                          isFirst: i == 0,
                          showDivider: i < _predictions.length - 1,
                        );
                      }),
                    ],

                    // ── No results ─────────────────────────────
                    if (_predictions.isEmpty &&
                        _searchCtrl.text.length >= 3 &&
                        !_searching)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: 60),
                        child: Column(children: [
                          Container(
                            width: 72, height: 72,
                            decoration: BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: _border)),
                            child: const Center(
                              child: Text('🔍',
                                  style: TextStyle(fontSize: 32)))),
                          const SizedBox(height: 16),
                          const Text('No results found',
                              style: TextStyle(color: _ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800)),
                          const SizedBox(height: 4),
                          const Text('Try a different search',
                              style: TextStyle(
                                  color: _faint, fontSize: 13)),
                        ]),
                      ),

                    // ── Recent searches (when no query) ────────
                    if (_searchCtrl.text.isEmpty) ...[
                      _sectionLabel('SUGGESTED AREAS'),
                      ..._recents.asMap().entries.map((e) {
                        final i = e.key;
                        final r = e.value;
                        return _listTile(
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFEFF),
                              borderRadius: BorderRadius.circular(14)),
                            child: const Icon(
                                Icons.location_city_rounded,
                                color: _cyan, size: 20)),
                          title: r.split(',').first,
                          subtitle: r,
                          onTap: () => _search(r.split(',').first),
                          showDivider: i < _recents.length - 1,
                        );
                      }),

                      // Service area info
                      Container(
                        margin: const EdgeInsets.fromLTRB(
                            16, 20, 16, 16),
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: const Color(0xFFECFEFF),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                              color: const Color(0xFFA5F3FC))),
                        child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment.start,
                            children: [
                          const Row(children: [
                            Text('🗺️',
                                style: TextStyle(fontSize: 16)),
                            SizedBox(width: 8),
                            Text('Service Areas',
                                style: TextStyle(color: _cyanDk,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800)),
                          ]),
                          const SizedBox(height: 8),
                          const Text(
                            'We currently serve Vile Parle, Juhu '
                            'and Andheri areas in Mumbai. '
                            'More areas coming soon!',
                            style: TextStyle(color: _muted,
                                fontSize: 12, height: 1.5)),
                        ]),
                      ),
                    ],
                  ],
                ),
        ),
      ]),
    );
  }

  Widget _sectionLabel(String label) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(label,
        style: const TextStyle(
            color: Color(0xFF9CA3AF), fontSize: 10,
            fontWeight: FontWeight.w800, letterSpacing: 1.5)),
  );

  Widget _listTile({
    required Widget leading,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isFirst = false,
    bool showDivider = true,
  }) {
    return Column(children: [
      if (!isFirst)
        const Divider(height: 1, indent: 74, color: _border),
      ListTile(
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 16, vertical: 6),
        leading: leading,
        title: Text(title,
            style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14, color: _ink),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: subtitle.isNotEmpty
            ? Text(subtitle,
                style: const TextStyle(
                    fontSize: 12, color: _muted),
                maxLines: 1, overflow: TextOverflow.ellipsis)
            : null,
        onTap: onTap,
        tileColor: Colors.white,
      ),
    ]);
  }
}