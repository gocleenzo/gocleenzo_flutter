import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

/// Manual address search using Google Places Autocomplete API
class LocationSearchScreen extends StatefulWidget {
  final bool isOnboarding;
  const LocationSearchScreen({super.key, this.isOnboarding = false});

  @override
  State<LocationSearchScreen> createState() => _LocationSearchScreenState();
}

class _LocationSearchScreenState extends State<LocationSearchScreen> {
  final _searchCtrl = TextEditingController();
  final _focus      = FocusNode();

  List<Map<String, dynamic>> _predictions = [];
  bool   _searching = false;
  String _sessionToken = '';

  // !! Replace with your key !!
  static const _apiKey = 'AIzaSyCr_DDF-1Aro_QuNAlzZRMOnrjKhiR20Ic';

  @override
  void initState() {
    super.initState();
    _sessionToken = DateTime.now().millisecondsSinceEpoch.toString();
    WidgetsBinding.instance.addPostFrameCallback((_) => _focus.requestFocus());
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
        '&types=geocode|establishment',
      );
      final res = await http.get(url);
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        if (data['status'] == 'OK') {
          setState(() {
            _predictions = (data['predictions'] as List).map((p) => {
              'place_id':    p['place_id'],
              'description': p['description'],
              'main_text':   p['structured_formatting']?['main_text'] ?? p['description'],
              'secondary':   p['structured_formatting']?['secondary_text'] ?? '',
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
    setState(() => _searching = true);

    try {
      // Get lat/lng from place_id
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
          final result   = data['result'];
          final lat      = result['geometry']['location']['lat'] as double;
          final lng      = result['geometry']['location']['lng'] as double;
          final fmtAddr  = result['formatted_address'] as String? ?? '';

          // Parse address components
          String area = '', city = '', pincode = '';
          for (final comp in (result['address_components'] as List)) {
            final types = (comp['types'] as List).cast<String>();
            if (types.contains('sublocality_level_1') || types.contains('sublocality')) {
              area = comp['long_name'];
            }
            if (types.contains('locality')) city = comp['long_name'];
            if (types.contains('postal_code')) pincode = comp['long_name'];
          }

          if (mounted) {
            setState(() => _searching = false);
            // Go to map picker with selected location
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
    } catch (e) {
      setState(() => _searching = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      body: Column(children: [

        // ── Header + Search Bar ────────────────────────────────
        Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(colors: [Color(0xFF06B6D4), Color(0xFF0891B2)]),
          ),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(children: [
                Row(children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12)),
                      child: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text('Search Address',
                      style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w900)),
                ]),
                const SizedBox(height: 14),
                // Search input
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08), blurRadius: 12)],
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    focusNode: _focus,
                    onChanged: _search,
                    style: const TextStyle(fontSize: 14, color: Color(0xFF0F172A)),
                    decoration: InputDecoration(
                      hintText: 'Search area, building, landmark…',
                      hintStyle: const TextStyle(color: Color(0xFF9CA3AF), fontSize: 14),
                      prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF06B6D4)),
                      suffixIcon: _searchCtrl.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFF9CA3AF), size: 18),
                              onPressed: () {
                                _searchCtrl.clear();
                                setState(() => _predictions = []);
                              })
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    ),
                  ),
                ),
              ]),
            ),
          ),
        ),

        // ── Results ───────────────────────────────────────────
        Expanded(
          child: _searching
              ? const Center(child: CircularProgressIndicator(color: Color(0xFF06B6D4)))
              : _predictions.isEmpty && _searchCtrl.text.length >= 3
                  ? const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text('🔍', style: TextStyle(fontSize: 40)),
                      SizedBox(height: 12),
                      Text('No results found', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
                      SizedBox(height: 4),
                      Text('Try a different search term', style: TextStyle(color: Color(0xFF9CA3AF), fontSize: 13)),
                    ]))
                  : ListView(
                      children: [
                        // Use current location option at top
                        ListTile(
                          leading: Container(
                            width: 44, height: 44,
                            decoration: BoxDecoration(
                              color: const Color(0xFFECFEFF),
                              borderRadius: BorderRadius.circular(12)),
                            child: const Icon(Icons.my_location_rounded,
                                color: Color(0xFF06B6D4), size: 22),
                          ),
                          title: const Text('Use current location',
                              style: TextStyle(fontWeight: FontWeight.w700, fontSize: 14)),
                          subtitle: const Text('Automatically detect via GPS',
                              style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                          onTap: () {
                            Navigator.pop(context);
                            // This will trigger GPS detection on gate screen
                          },
                        ),
                        const Divider(height: 1),

                        // Search predictions
                        ..._predictions.map((p) => Column(children: [
                          ListTile(
                            leading: Container(
                              width: 44, height: 44,
                              decoration: BoxDecoration(
                                color: const Color(0xFFF8FAFC),
                                borderRadius: BorderRadius.circular(12)),
                              child: const Icon(Icons.location_on_outlined,
                                  color: Color(0xFF64748B), size: 22),
                            ),
                            title: Text(p['main_text'],
                                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(p['secondary'],
                                style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            onTap: () => _selectPlace(p),
                          ),
                          const Divider(height: 1, indent: 70),
                        ])),
                      ],
                    ),
        ),
      ]),
    );
  }
}