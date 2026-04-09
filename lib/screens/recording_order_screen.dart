import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:proj4dart/proj4dart.dart' as proj4;

import '../models.dart';
import '../storage.dart';

class RecordingOrderScreen extends StatefulWidget {
  const RecordingOrderScreen({super.key});

  @override
  State<RecordingOrderScreen> createState() => _RecordingOrderScreenState();
}

class _RecordingOrderScreenState extends State<RecordingOrderScreen> {
  final storage = Storage();

  bool loaded = false;
  List<Paddock> paddocks = [];

  int _viewMode = 0;
  bool _setOrderMode = false;
  final List<String> _setOrderSequence = [];
  List<Paddock>? _paddocksBeforeSetOrder;

  final MapController _mapController = MapController();
  bool _mapFitApplied = false;
  double _mapZoom = 15;

  late final proj4.Projection _wgs84 =
      proj4.Projection.get('EPSG:4326') ?? proj4.Projection.WGS84;
  late final proj4.Projection _nztm =
      proj4.Projection.get('EPSG:2193') ??
      proj4.Projection.add(
        'EPSG:2193',
        '+proj=tmerc +lat_0=0 +lon_0=173 +k=0.9996 +x_0=1600000 +y_0=10000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    paddocks = await storage.loadPaddocks();
    paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    loaded = true;
    setState(() {});
  }

  Future<void> _saveAll() async {
    await storage.savePaddocks(paddocks);
  }

  Future<void> _saveOrderOnly() async {
    // Keep everything the same, just rewrite recordOrder based on current list order.
    final updated = <Paddock>[];
    for (int i = 0; i < paddocks.length; i++) {
      final p = paddocks[i];
      updated.add(
        Paddock(
          id: p.id,
          name: p.name,
          areaHa: p.areaHa,
          recordOrder: i + 1,
          includeInRotation: p.includeInRotation,
        ),
      );
    }
    paddocks = updated;
    await _saveAll();
  }

  Future<void> _saveAndCloseSetOrderMode() async {
    await _saveAll();
    if (!mounted) return;
    setState(() {
      _setOrderMode = false;
      _setOrderSequence.clear();
      _paddocksBeforeSetOrder = null;
    });
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Saved')));
  }

  List<Paddock> _clonePaddocks(List<Paddock> src) {
    return src
        .map(
          (p) => Paddock(
            id: p.id,
            name: p.name,
            areaHa: p.areaHa,
            recordOrder: p.recordOrder,
            includeInRotation: p.includeInRotation,
          ),
        )
        .toList();
  }

  void _cancelSetOrderMode() {
    final snap = _paddocksBeforeSetOrder;
    if (snap != null) {
      paddocks = _clonePaddocks(snap);
      paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    }
    setState(() {
      _setOrderMode = false;
      _setOrderSequence.clear();
      _paddocksBeforeSetOrder = null;
    });
  }

  void _toggleInclude(String paddockId, bool include) async {
    final i = paddocks.indexWhere((p) => p.id == paddockId);
    if (i < 0) return;

    setState(() {
      final p = paddocks[i];
      paddocks[i] = Paddock(
        id: p.id,
        name: p.name,
        areaHa: p.areaHa,
        recordOrder: p.recordOrder,
        includeInRotation: include,
      );
    });

    await _saveAll();
  }

  void _toggleIncludeLocal(String paddockId) {
    final i = paddocks.indexWhere((p) => p.id == paddockId);
    if (i < 0) return;
    setState(() {
      final p = paddocks[i];
      paddocks[i] = Paddock(
        id: p.id,
        name: p.name,
        areaHa: p.areaHa,
        recordOrder: p.recordOrder,
        includeInRotation: !p.includeInRotation,
      );
    });
  }

  void _enterSetOrderMode() {
    setState(() {
      _paddocksBeforeSetOrder = _clonePaddocks(paddocks);
      paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
      _setOrderMode = true;
      _setOrderSequence.clear();
    });
  }

  void _applyOrderSequence() {
    if (_setOrderSequence.isEmpty) return;
    final byId = {for (final p in paddocks) p.id: p};
    final used = <String>{..._setOrderSequence};

    final rest = paddocks.where((p) => !used.contains(p.id)).toList()
      ..sort((a, b) => a.recordOrder.compareTo(b.recordOrder));

    int k = 1;
    final updated = <Paddock>[];

    for (final id in _setOrderSequence) {
      final p = byId[id];
      if (p == null) continue;
      updated.add(
        Paddock(
          id: p.id,
          name: p.name,
          areaHa: p.areaHa,
          recordOrder: k++,
          includeInRotation: p.includeInRotation,
        ),
      );
    }

    for (final p in rest) {
      updated.add(
        Paddock(
          id: p.id,
          name: p.name,
          areaHa: p.areaHa,
          recordOrder: k++,
          includeInRotation: p.includeInRotation,
        ),
      );
    }

    updated.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    paddocks = updated;
  }

  void _tapSetOrder(String paddockId) {
    if (!_setOrderMode) return;
    if (_setOrderSequence.contains(paddockId)) return;
    setState(() {
      _setOrderSequence.add(paddockId);
      _applyOrderSequence();
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_setOrderMode,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        if (_setOrderMode) {
          _cancelSetOrderMode();
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Recording order'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () {
              if (_setOrderMode) {
                _cancelSetOrderMode();
              }
              Navigator.of(context).pop();
            },
          ),
          actions: [
            if (_viewMode == 1)
              TextButton(
                onPressed: _setOrderMode ? _saveAndCloseSetOrderMode : null,
                child: const Text('Save'),
              ),
          ],
        ),
        body: !loaded
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                    child: SizedBox(
                      height: 34,
                      child: SegmentedButton<int>(
                        showSelectedIcon: false,
                        style: const ButtonStyle(
                          visualDensity: VisualDensity.compact,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                        segments: const [
                          ButtonSegment(
                            value: 0,
                            label: SizedBox(
                              width: 96,
                              child: Center(child: Text('List')),
                            ),
                          ),
                          ButtonSegment(
                            value: 1,
                            label: SizedBox(
                              width: 96,
                              child: Center(child: Text('Map')),
                            ),
                          ),
                        ],
                        selected: {_viewMode},
                        onSelectionChanged: (s) {
                          final v = s.first;
                          setState(() {
                            _viewMode = v;
                            if (_setOrderMode) {
                              _cancelSetOrderMode();
                            }
                            _mapFitApplied = false;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _viewMode == 0 ? _listView() : _mapView()),
                ],
              ),
      ),
    );
  }

  Widget _listView() {
    return ReorderableListView.builder(
      itemCount: paddocks.length,
      onReorder: (oldIndex, newIndex) async {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final item = paddocks.removeAt(oldIndex);
          paddocks.insert(newIndex, item);
        });
        await _saveOrderOnly();
      },
      itemBuilder: (ctx, i) {
        final p = paddocks[i];
        return ListTile(
          key: ValueKey(p.id),
          title: Text(p.name),
          subtitle: const Text('Include in rotation'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Checkbox(
                value: p.includeInRotation,
                onChanged: (v) => _toggleInclude(p.id, v ?? true),
              ),
              const Icon(Icons.drag_handle),
            ],
          ),
        );
      },
    );
  }

  Widget _mapView() {
    final byId = {for (final p in paddocks) p.id: p};

    return FutureBuilder<List<Map<String, dynamic>>>(
      future: storage.loadFarmMapPolygons(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final raw = snap.data ?? <Map<String, dynamic>>[];
        if (raw.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.map_outlined, size: 48),
                  const SizedBox(height: 12),
                  const Text(
                    'No map imported',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Import a farm map from Settings to enable Map order mode.',
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          );
        }

        final polys = _buildMapPolys(raw, byId);
        final bounds = _boundsForMapPolys(polys);

        if (!_mapFitApplied && bounds != null && polys.isNotEmpty) {
          _mapFitApplied = true;
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _setOrderMode ? null : _enterSetOrderMode,
                      icon: const Icon(Icons.format_list_numbered),
                      label: Text(
                        _setOrderMode ? 'Set order active' : 'Set order',
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: !_setOrderMode ? null : _cancelSetOrderMode,
                      icon: const Icon(Icons.close),
                      label: const Text('Exit'),
                    ),
                  ),
                ],
              ),
            ),
            if (_setOrderMode)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.black.withValues(alpha: 0.08),
                    ),
                  ),
                  child: Text(
                    'Tap paddocks to set order. Selected: ${_setOrderSequence.length}',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
              ),
            Expanded(
              child: FlutterMap(
                mapController: _mapController,
                options: MapOptions(
                  initialCenter: bounds?.center ?? const ll.LatLng(0, 0),
                  initialZoom: 15,
                  onMapEvent: (e) {
                    final z = e.camera.zoom;
                    if (z != _mapZoom) setState(() => _mapZoom = z);
                  },
                  interactionOptions: const InteractionOptions(
                    flags:
                        InteractiveFlag.drag |
                        InteractiveFlag.pinchZoom |
                        InteractiveFlag.doubleTapZoom |
                        InteractiveFlag.flingAnimation,
                  ),
                  onTap: (tapPosition, point) {
                    final hitId = _hitTest(point, polys);
                    if (hitId == null) return;
                    if (_setOrderMode) {
                      _tapSetOrder(hitId);
                    }
                  },
                  onLongPress: (tapPosition, point) async {
                    final hitId = _hitTest(point, polys);
                    if (hitId == null) return;
                    _toggleIncludeLocal(hitId);
                    await _saveAll();
                  },
                ),
                children: [
                  TileLayer(
                    urlTemplate:
                        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                    userAgentPackageName: 'pasture_walk',
                  ),
                  PolygonLayer(
                    polygons: polys.map((p) {
                      final selected =
                          _setOrderMode &&
                          _setOrderSequence.contains(p.paddockId);
                      return Polygon(
                        points: p.rings.first,
                        borderColor: Colors.black.withValues(alpha: 0.60),
                        borderStrokeWidth: 1.6,
                        isFilled: true,
                        color: p.excluded
                            ? Colors.grey.withValues(alpha: 0.25)
                            : (selected
                                  ? Colors.amber.withValues(alpha: 0.35)
                                  : Colors.lightGreen.withValues(alpha: 0.25)),
                      );
                    }).toList(),
                  ),
                  MarkerLayer(
                    markers: polys.map((p) {
                      final pdk = byId[p.paddockId];
                      final int? order = !_setOrderMode
                          ? (pdk?.recordOrder ?? 0)
                          : (_setOrderSequence.contains(p.paddockId)
                                ? (_setOrderSequence.indexOf(p.paddockId) + 1)
                                : null);
                      final opacity = _labelOpacity(p, _mapZoom);
                      return Marker(
                        point: p.centroid,
                        width: 74,
                        height: 34,
                        alignment: Alignment.center,
                        child: Opacity(
                          opacity: opacity,
                          child: _OrderLabel(
                            title: p.label,
                            order: order,
                            excluded: p.excluded,
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  double _labelOpacity(_OrderMapPoly p, double zoom) {
    var a = 1.0;
    if (zoom < 13) {
      a *= ((zoom - 11.5) / (13 - 11.5)).clamp(0.0, 1.0);
    }
    if (p.excluded) a *= 0.85;
    return a.clamp(0.0, 1.0);
  }

  List<_OrderMapPoly> _buildMapPolys(
    List<Map<String, dynamic>> raw,
    Map<String, Paddock> byId,
  ) {
    final out = <_OrderMapPoly>[];
    for (final p in raw) {
      final paddockId = p['paddockId']?.toString();
      if (paddockId == null || paddockId.isEmpty) continue;
      final paddock = byId[paddockId];
      if (paddock == null) continue;

      final ringsAny = p['polys'];
      if (ringsAny is! List) continue;

      final rings = <List<ll.LatLng>>[];
      for (final ringAny in ringsAny) {
        final ring = _ringToLatLng(ringAny);
        if (ring != null && ring.length >= 3) rings.add(ring);
      }
      if (rings.isEmpty) continue;

      var minLat = double.infinity;
      var minLon = double.infinity;
      var maxLat = -double.infinity;
      var maxLon = -double.infinity;
      for (final r in rings) {
        for (final pt in r) {
          minLat = math.min(minLat, pt.latitude);
          minLon = math.min(minLon, pt.longitude);
          maxLat = math.max(maxLat, pt.latitude);
          maxLon = math.max(maxLon, pt.longitude);
        }
      }
      if (!minLat.isFinite ||
          !minLon.isFinite ||
          !maxLat.isFinite ||
          !maxLon.isFinite) {
        continue;
      }

      final bounds = _MapBounds(
        ll.LatLng(minLat, minLon),
        ll.LatLng(maxLat, maxLon),
      );

      final centroid = _centroidForRing(rings.first) ?? bounds.center;

      out.add(
        _OrderMapPoly(
          paddockId: paddockId,
          label: paddock.name,
          excluded: !paddock.includeInRotation,
          rings: rings,
          bounds: bounds,
          centroid: centroid,
        ),
      );
    }
    return out;
  }

  List<ll.LatLng>? _ringToLatLng(dynamic ringAny) {
    if (ringAny is! List) return null;
    final pts = <ll.LatLng>[];
    for (final xyAny in ringAny) {
      if (xyAny is! List) continue;
      if (xyAny.length < 2) continue;
      final a = (xyAny[0] as num?)?.toDouble();
      final b = (xyAny[1] as num?)?.toDouble();
      if (a == null || b == null) continue;

      ll.LatLng? pt;
      final degOk = (b >= -90 && b <= 90 && a >= -180 && a <= 180);
      if (degOk) {
        pt = ll.LatLng(b, a);
      } else {
        final swappedDegOk = (a >= -90 && a <= 90 && b >= -180 && b <= 180);
        if (swappedDegOk) {
          pt = ll.LatLng(a, b);
        } else {
          final looksProjected = a.abs() > 1000 && b.abs() > 1000;
          if (looksProjected) {
            try {
              final pWgs = _nztm.transform(_wgs84, proj4.Point(x: a, y: b));
              final lon = pWgs.x.toDouble();
              final lat = pWgs.y.toDouble();
              if (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180) {
                pt = ll.LatLng(lat, lon);
              }
            } catch (_) {
              pt = null;
            }
          }
        }
      }

      if (pt == null) return null;
      pts.add(pt);
    }
    return pts;
  }

  _MapBounds? _boundsForMapPolys(List<_OrderMapPoly> polys) {
    if (polys.isEmpty) return null;
    final b = _MapBounds(
      polys.first.bounds.southWest,
      polys.first.bounds.northEast,
    );
    for (final p in polys.skip(1)) {
      b.extend(p.bounds.southWest);
      b.extend(p.bounds.northEast);
    }
    return b;
  }

  String? _hitTest(ll.LatLng p, List<_OrderMapPoly> polys) {
    for (final poly in polys.reversed) {
      if (_pointInRing(p, poly.rings.first)) return poly.paddockId;
    }
    return null;
  }

  bool _pointInRing(ll.LatLng p, List<ll.LatLng> ring) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final xi = ring[i].longitude;
      final yi = ring[i].latitude;
      final xj = ring[j].longitude;
      final yj = ring[j].latitude;

      final intersect =
          ((yi > p.latitude) != (yj > p.latitude)) &&
          (p.longitude <
              (xj - xi) *
                      (p.latitude - yi) /
                      ((yj - yi) == 0 ? 1e-12 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  ll.LatLng? _centroidForRing(List<ll.LatLng> ring) {
    if (ring.length < 3) return null;
    double a = 0;
    double cx = 0;
    double cy = 0;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final x0 = ring[j].longitude;
      final y0 = ring[j].latitude;
      final x1 = ring[i].longitude;
      final y1 = ring[i].latitude;
      final f = (x0 * y1) - (x1 * y0);
      a += f;
      cx += (x0 + x1) * f;
      cy += (y0 + y1) * f;
    }
    a *= 0.5;
    if (a.abs() < 1e-12) return null;
    cx /= (6.0 * a);
    cy /= (6.0 * a);
    if (cy < -90 || cy > 90 || cx < -180 || cx > 180) return null;
    return ll.LatLng(cy, cx);
  }
}

class _MapBounds {
  ll.LatLng southWest;
  ll.LatLng northEast;

  _MapBounds(this.southWest, this.northEast);

  ll.LatLng get center => ll.LatLng(
    (southWest.latitude + northEast.latitude) / 2.0,
    (southWest.longitude + northEast.longitude) / 2.0,
  );

  void extend(ll.LatLng p) {
    final minLat = math.min(southWest.latitude, p.latitude);
    final minLon = math.min(southWest.longitude, p.longitude);
    final maxLat = math.max(northEast.latitude, p.latitude);
    final maxLon = math.max(northEast.longitude, p.longitude);
    southWest = ll.LatLng(minLat, minLon);
    northEast = ll.LatLng(maxLat, maxLon);
  }
}

class _OrderMapPoly {
  final String paddockId;
  final String label;
  final bool excluded;
  final List<List<ll.LatLng>> rings;
  final _MapBounds bounds;
  final ll.LatLng centroid;

  const _OrderMapPoly({
    required this.paddockId,
    required this.label,
    required this.excluded,
    required this.rings,
    required this.bounds,
    required this.centroid,
  });
}

class _OrderLabel extends StatelessWidget {
  final String title;
  final int? order;
  final bool excluded;

  const _OrderLabel({
    required this.title,
    required this.order,
    required this.excluded,
  });

  @override
  Widget build(BuildContext context) {
    final bg = excluded
        ? Colors.grey.withValues(alpha: 0.70)
        : Colors.white.withValues(alpha: 0.88);
    final fg = excluded ? Colors.white : Colors.black;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withValues(alpha: 0.25)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: excluded
                  ? Colors.black.withValues(alpha: 0.25)
                  : Colors.black.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              (order == null || order! <= 0) ? '' : '${order!}',
              style: TextStyle(fontWeight: FontWeight.w900, color: fg),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, color: fg),
            ),
          ),
        ],
      ),
    );
  }
}
