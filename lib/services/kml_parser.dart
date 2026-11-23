import 'dart:math' as math;

import 'package:xml/xml.dart';

/// Converts a KML document into GeoJSON-style features.
///
/// KML has no attribute table and no area field, so each `<Placemark>` becomes
/// one feature:
///  * `<name>` → `properties.name`
///  * `<description>` → `properties.description`
///  * `<ExtendedData><Data name="x">` and `<SimpleData name="x">` → properties
///  * polygon geometry → `Polygon` (one ring) or `MultiPolygon` (several)
///  * `properties.area_ha` computed from the outline, because the import
///    pipeline skips any feature without an area
///
/// Placemarks holding only a Point or a LineString are skipped. Inner boundaries
/// (holes) are ignored, matching what the GeoJSON and Shapefile paths do.
List<Map<String, dynamic>> kmlToGeoJsonFeatures(String text) {
  final doc = XmlDocument.parse(text);

  List<List<double>> ringFrom(XmlElement? ringEl) {
    final raw = ringEl?.getElement('coordinates')?.innerText.trim() ?? '';
    final pts = <List<double>>[];
    for (final token in raw.split(RegExp(r'\s+'))) {
      if (token.isEmpty) continue;
      final parts = token.split(',');
      if (parts.length < 2) continue;
      final lon = double.tryParse(parts[0].trim());
      final lat = double.tryParse(parts[1].trim());
      if (lon == null || lat == null) continue;
      // KML coordinates are lon,lat in degrees; reject anything else (e.g. a
      // projected shapefile-style pair) rather than plotting it in the Gulf.
      if (lat < -90 || lat > 90 || lon < -180 || lon > 180) continue;
      pts.add(<double>[lon, lat]);
    }
    return pts;
  }

  final out = <Map<String, dynamic>>[];
  for (final pm in doc.findAllElements('Placemark')) {
    // Every Polygon beneath the placemark, so <MultiGeometry> works too.
    final rings = <List<List<double>>>[];
    for (final poly in pm.findAllElements('Polygon')) {
      final ring = ringFrom(
        poly.getElement('outerBoundaryIs')?.getElement('LinearRing'),
      );
      if (ring.length >= 4) rings.add(ring); // a closed ring needs 4 points
    }
    if (rings.isEmpty) continue; // a point or a path, not a paddock

    final props = <String, dynamic>{};
    final name = pm.getElement('name')?.innerText.trim() ?? '';
    if (name.isNotEmpty) props['name'] = name;
    final desc = pm.getElement('description')?.innerText.trim() ?? '';
    if (desc.isNotEmpty) props['description'] = desc;

    for (final d in pm.findAllElements('Data')) {
      final key = d.getAttribute('name');
      final value = d.getElement('value')?.innerText.trim();
      if (key != null && key.isNotEmpty && value != null) props[key] = value;
    }
    for (final sd in pm.findAllElements('SimpleData')) {
      final key = sd.getAttribute('name');
      if (key != null && key.isNotEmpty) props[key] = sd.innerText.trim();
    }

    var ha = 0.0;
    for (final r in rings) {
      ha += ringAreaHa(r);
    }
    if (ha > 0) props['area_ha'] = ha;

    final geometry = rings.length == 1
        ? <String, dynamic>{
            'type': 'Polygon',
            'coordinates': <dynamic>[rings.first],
          }
        : <String, dynamic>{
            'type': 'MultiPolygon',
            'coordinates': rings.map((r) => <dynamic>[r]).toList(),
          };

    out.add(<String, dynamic>{
      'type': 'Feature',
      'properties': props,
      'geometry': geometry,
    });
  }

  return out;
}

/// Geodesic area of a lon/lat ring in hectares, from the spherical excess.
/// Accurate to a fraction of a percent at paddock scale.
double ringAreaHa(List<List<double>> ring) {
  if (ring.length < 3) return 0;
  const earthRadius = 6378137.0;
  const degToRad = math.pi / 180.0;
  var total = 0.0;
  for (var i = 0; i < ring.length; i++) {
    final p1 = ring[i];
    final p2 = ring[(i + 1) % ring.length];
    total +=
        (p2[0] - p1[0]) *
        degToRad *
        (2 + math.sin(p1[1] * degToRad) + math.sin(p2[1] * degToRad));
  }
  return (total * earthRadius * earthRadius / 2).abs() / 10000.0;
}
