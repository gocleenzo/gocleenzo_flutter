// geofence_service.dart
//
// Replaces pincode-based serviceability with polygon-based "geofencing".
// Instead of matching a customer's pincode against a flat list of served
// pincodes, this checks whether their exact lat/lng falls inside any
// admin-drawn polygon — letting you serve a well-mapped society while
// excluding a chawl sitting right next door in the same pincode.

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceZone {
  final String id;
  final String name;
  final List<LatLng> polygon;

  ServiceZone({required this.id, required this.name, required this.polygon});

  factory ServiceZone.fromRow(Map<String, dynamic> row) {
    final points = (row['polygon'] as List)
        .map((p) => LatLng(
              (p['lat'] as num).toDouble(),
              (p['lng'] as num).toDouble(),
            ))
        .toList();
    return ServiceZone(
      id: row['id'] as String,
      name: row['name'] as String? ?? '',
      polygon: points,
    );
  }
}

class GeofenceService {
  /// Fetch all active zones ONCE (same pattern as the old
  /// `_loadActiveAreas` pincode fetch) — not per pin-drag.
  static Future<List<ServiceZone>> loadActiveZones() async {
    try {
      final rows = await Supabase.instance.client
          .from('service_zones')
          .select('id, name, polygon')
          .eq('is_active', true);
      return (rows as List)
          .map((r) => ServiceZone.fromRow(r as Map<String, dynamic>))
          .where((z) => z.polygon.length >= 3) // a polygon needs 3+ points
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// True if [point] falls inside ANY of [zones].
  /// Fails open (returns true) if no zones are configured at all, so a
  /// fresh install with zero zones drawn doesn't accidentally block
  /// every single customer — matches the old pincode behaviour.
  static bool isServiceable(LatLng point, List<ServiceZone> zones) {
    if (zones.isEmpty) return true;
    for (final zone in zones) {
      if (_pointInPolygon(point, zone.polygon)) return true;
    }
    return false;
  }

  /// Standard ray-casting point-in-polygon test. Counts how many times a
  /// horizontal ray from the point crosses the polygon's edges — an odd
  /// number of crossings means the point is inside.
  static bool _pointInPolygon(LatLng point, List<LatLng> polygon) {
    bool inside = false;
    final n = polygon.length;
    for (int i = 0, j = n - 1; i < n; j = i++) {
      final xi = polygon[i].longitude, yi = polygon[i].latitude;
      final xj = polygon[j].longitude, yj = polygon[j].latitude;
      final intersects = ((yi > point.latitude) != (yj > point.latitude)) &&
          (point.longitude <
              (xj - xi) * (point.latitude - yi) / (yj - yi) + xi);
      if (intersects) inside = !inside;
    }
    return inside;
  }
}