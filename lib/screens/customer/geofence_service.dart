// geofence_service.dart
//
// Polygon-based serviceability check, matching try_claim_slot's actual
// server-side logic exactly:
//   - A point inside an EXCLUSION zone (is_exclusion = true) is NEVER
//     bookable, no matter what.
//   - Coverage zones (is_exclusion = false) do NOT currently gate
//     anything on the server side — try_claim_slot never requires a
//     point to be inside one. So this client-side check mirrors that:
//     only exclusion zones can make a point unserviceable; everything
//     else defaults to serviceable.
//
// FIXED BUG: the previous version fetched ALL active zones (coverage
// AND exclusion) with no way to distinguish them, and treated "inside
// ANY zone" as serviceable = true. That's backwards for an exclusion
// zone — being inside a drawn "excluded chawl" polygon was showing as
// "✓ Service available here", while being OUTSIDE it (in the normal,
// otherwise-unrestricted rest of the pincode) showed as "Not bookable
// yet — launching soon", since no zone at all matched that point. This
// is now corrected to only ever treat EXCLUSION zone membership as a
// reason to block — never coverage zone membership (or lack of it) —
// exactly matching how try_claim_slot itself gates bookings.

import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class ServiceZone {
  final String id;
  final String name;
  final List<LatLng> polygon;
  final bool isExclusion;

  ServiceZone({
    required this.id,
    required this.name,
    required this.polygon,
    required this.isExclusion,
  });

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
      isExclusion: row['is_exclusion'] as bool? ?? false,
    );
  }
}

class GeofenceService {
  /// Fetch all active zones ONCE (same pattern as the old
  /// `_loadActiveAreas` pincode fetch) — not per pin-drag. Now also
  /// selects `is_exclusion` so the two zone types can actually be told
  /// apart — the missing piece that caused the original bug.
  static Future<List<ServiceZone>> loadActiveZones() async {
    try {
      final rows = await Supabase.instance.client
          .from('service_zones')
          .select('id, name, polygon, is_exclusion')
          .eq('is_active', true);
      return (rows as List)
          .map((r) => ServiceZone.fromRow(r as Map<String, dynamic>))
          .where((z) => z.polygon.length >= 3) // a polygon needs 3+ points
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// True if [point] is bookable, matching try_claim_slot's real
  /// server-side rule exactly:
  ///   - Inside ANY exclusion zone -> false, always. This is a hard
  ///     block regardless of pincode, coverage zones, or anything else.
  ///   - Otherwise -> true. Coverage zones are informational/organizational
  ///     only right now (see admin Service Zones page) and do NOT gate
  ///     serviceability on the server, so they must not gate it here
  ///     either — a point with zero zone matches is exactly as bookable
  ///     as a point inside a coverage zone, since neither is excluded.
  static bool isServiceable(LatLng point, List<ServiceZone> zones) {
    for (final zone in zones) {
      if (zone.isExclusion && _pointInPolygon(point, zone.polygon)) {
        return false;
      }
    }
    return true;
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