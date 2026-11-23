import 'package:flutter_test/flutter_test.dart';
import 'package:pasture_walk/services/kml_parser.dart';

/// A ~100 m square near Hamilton: 100 m of latitude is 0.000899 deg, and at
/// -37.8 latitude 100 m of longitude is 0.001136 deg. That is ~1.0 ha.
const _squareKml = '''
<?xml version="1.0" encoding="UTF-8"?>
<kml xmlns="http://www.opengis.net/kml/2.2">
  <Document>
    <name>Farm</name>
    <Placemark>
      <name>Paddock 1</name>
      <description>River flat</description>
      <ExtendedData>
        <Data name="pdk"><value>1</value></Data>
        <Data name="notes"><value>wet corner</value></Data>
      </ExtendedData>
      <Polygon>
        <outerBoundaryIs>
          <LinearRing>
            <coordinates>
              175.000000,-37.800000,0
              175.001136,-37.800000,0
              175.001136,-37.800899,0
              175.000000,-37.800899,0
              175.000000,-37.800000,0
            </coordinates>
          </LinearRing>
        </outerBoundaryIs>
      </Polygon>
    </Placemark>
  </Document>
</kml>
''';

void main() {
  test('parses one paddock polygon with name, properties and area', () {
    final feats = kmlToGeoJsonFeatures(_squareKml);

    expect(feats, hasLength(1));
    final f = feats.single;

    expect(f['type'], 'Feature');

    final props = f['properties'] as Map<String, dynamic>;
    expect(props['name'], 'Paddock 1');
    expect(props['description'], 'River flat');
    expect(props['pdk'], '1');
    expect(props['notes'], 'wet corner');

    // ~1 ha, from the outline rather than any attribute.
    final area = props['area_ha'] as double;
    expect(area, greaterThan(0.9));
    expect(area, lessThan(1.1));

    final geom = f['geometry'] as Map<String, dynamic>;
    expect(geom['type'], 'Polygon');

    final rings = geom['coordinates'] as List<dynamic>;
    expect(rings, hasLength(1));
    final ring = rings.single as List<dynamic>;
    expect(ring, hasLength(5));

    // GeoJSON order is [lon, lat]; a swap would flip the sign of the first pair.
    final first = ring.first as List<dynamic>;
    expect(first[0], closeTo(175.0, 1e-9));
    expect(first[1], closeTo(-37.8, 1e-9));
  });

  test('MultiGeometry becomes a MultiPolygon and sums the area', () {
    const kml = '''
<kml><Document>
  <Placemark>
    <name>Paddock 2</name>
    <MultiGeometry>
      <Polygon><outerBoundaryIs><LinearRing><coordinates>
        175.000000,-37.800000 175.001136,-37.800000
        175.001136,-37.800899 175.000000,-37.800899
        175.000000,-37.800000
      </coordinates></LinearRing></outerBoundaryIs></Polygon>
      <Polygon><outerBoundaryIs><LinearRing><coordinates>
        175.010000,-37.800000 175.011136,-37.800000
        175.011136,-37.800899 175.010000,-37.800899
        175.010000,-37.800000
      </coordinates></LinearRing></outerBoundaryIs></Polygon>
    </MultiGeometry>
  </Placemark>
</Document></kml>
''';
    final feats = kmlToGeoJsonFeatures(kml);
    expect(feats, hasLength(1));

    final geom = feats.single['geometry'] as Map<String, dynamic>;
    expect(geom['type'], 'MultiPolygon');
    expect((geom['coordinates'] as List).length, 2);

    final area = (feats.single['properties'] as Map)['area_ha'] as double;
    expect(area, greaterThan(1.8));
    expect(area, lessThan(2.2));
  });

  test('placemarks with only a Point are skipped', () {
    const kml = '''
<kml><Document>
  <Placemark><name>Trough</name><Point><coordinates>175.0,-37.8,0</coordinates></Point></Placemark>
  <Placemark>
    <name>Paddock 3</name>
    <Polygon><outerBoundaryIs><LinearRing><coordinates>
      175.000000,-37.800000 175.001136,-37.800000
      175.001136,-37.800899 175.000000,-37.800899
      175.000000,-37.800000
    </coordinates></LinearRing></outerBoundaryIs></Polygon>
  </Placemark>
</Document></kml>
''';
    final feats = kmlToGeoJsonFeatures(kml);
    expect(feats, hasLength(1));
    expect((feats.single['properties'] as Map)['name'], 'Paddock 3');
  });

  test('a document with no polygons yields no features', () {
    const kml = '''
<kml><Document>
  <Placemark><name>Trough</name><Point><coordinates>175.0,-37.8,0</coordinates></Point></Placemark>
</Document></kml>
''';
    expect(kmlToGeoJsonFeatures(kml), isEmpty);
  });

  test('coordinates in projected metres are rejected rather than plotted', () {
    const kml = '''
<kml><Document>
  <Placemark>
    <name>Bad</name>
    <Polygon><outerBoundaryIs><LinearRing><coordinates>
      1790000,5810000 1790100,5810000 1790100,5810100 1790000,5810000
    </coordinates></LinearRing></outerBoundaryIs></Polygon>
  </Placemark>
</Document></kml>
''';
    expect(kmlToGeoJsonFeatures(kml), isEmpty);
  });
}
