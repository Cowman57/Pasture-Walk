import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:proj4dart/proj4dart.dart' as proj4;
import 'dart:async';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';

class RoundScreen extends StatefulWidget {
  const RoundScreen({super.key});

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen>
    with SingleTickerProviderStateMixin {
  final storage = Storage();
  final uuid = const Uuid();

  static const double _overlayBoxAlpha = 0.80;
  Color get _overlayBoxColor =>
      Colors.grey.shade300.withValues(alpha: _overlayBoxAlpha);

  final MapController _mapController = MapController();
  double _mapZoom = 16;

  Timer? _mapPanTimer;
  ll.LatLng? _mapCenter;

  StreamSubscription<Position>? _posSub;
  bool _gpsLiveEnabled = false;
  bool _gpsTrackingActive = false;
  bool _bgHasMap = false;
  Position? _lastPos;
  List<Map<String, dynamic>> _farmPolysRaw = const [];
  DateTime? _gpsLastSwitchAt;

  bool _gpsExcludedWarned = false;

  late final proj4.Projection _wgs84 =
      proj4.Projection.get('EPSG:4326') ?? proj4.Projection.WGS84;

  late final proj4.Projection _nztm =
      proj4.Projection.get('EPSG:2193') ??
      proj4.Projection.add(
        'EPSG:2193',
        '+proj=tmerc +lat_0=0 +lon_0=173 +k=0.9996 +x_0=1600000 +y_0=10000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );

  bool loaded = false;

  bool _moving = false;

  late final AnimationController _tapCtrl;
  late final Animation<double> _tapOpacity;
  late final Animation<double> _deltaT;
  int _lastTapDelta = 0;
  bool _lastTapWasIncrease = true;

  bool _showHints = true;

  double _hDragDx = 0.0;
  bool _hDragHandled = false;

  List<Paddock> order = [];
  int idx = 0;

  int coverStep = 50;

  // Predicted "now" per paddock when screen was opened
  final Map<String, int> predictedNow = {};

  // Last recorded measurement per paddock (latest, any date)
  final Map<String, Measurement?> lastMeasured = {};

  // ✅ Draft (current-session) cover per paddock, so values "stick" when you go back/forth
  final Map<String, int> draftCover = {};

  // Growth
  double farmGrowth = 0.0;
  String noteBtn1 = 'Weeds';
  String noteBtn2 = 'Water leak';

  // Editable value (big number)
  int currentCover = 2500;

  @override
  void initState() {
    super.initState();
    _tapCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _tapOpacity = CurvedAnimation(parent: _tapCtrl, curve: Curves.easeOut);
    _deltaT = CurvedAnimation(parent: _tapCtrl, curve: Curves.easeInOut);
    _init();
  }

  @override
  void dispose() {
    _posSub?.cancel();
    _gpsTrackingActive = false;
    _mapPanTimer?.cancel();
    _tapCtrl.dispose();
    super.dispose();
  }

  Future<void> _openNotesSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Wrap(
              runSpacing: 10,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _appendNote(noteBtn1);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Note added: $noteBtn1')),
                      );
                    },
                    child: Text(noteBtn1),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: OutlinedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _appendNote(noteBtn2);
                      if (!mounted) return;
                      messenger.showSnackBar(
                        SnackBar(content: Text('Note added: $noteBtn2')),
                      );
                    },
                    child: Text(noteBtn2),
                  ),
                ),
                SizedBox(
                  width: double.infinity,
                  height: 46,
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      await _appendCustomNote();
                    },
                    child: const Text('Custom'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _jumpToPaddock() async {
    if (order.isEmpty) return;

    final pickOrder = [...order];
    int numKey(Paddock p) {
      final m = RegExp(r'\d+').firstMatch(p.name);
      if (m == null) return 1 << 30;
      return int.tryParse(m.group(0) ?? '') ?? (1 << 30);
    }

    pickOrder.sort((a, b) {
      final an = numKey(a);
      final bn = numKey(b);
      if (an != bn) return an.compareTo(bn);
      return a.name.compareTo(b.name);
    });

    final picked = await showModalBottomSheet<int>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return SafeArea(
          child: ListView.builder(
            itemCount: pickOrder.length,
            itemBuilder: (c, i) {
              final p = pickOrder[i];
              final selected = p.id == _p.id;
              return ListTile(
                title: Text(p.name),
                trailing: selected ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(
                  ctx,
                ).pop(order.indexWhere((x) => x.id == p.id)),
              );
            },
          ),
        );
      },
    );

    if (picked == null) return;
    if (picked == idx) return;
    await _saveCurrent();
    if (!mounted) return;
    setState(() {
      idx = picked;
      currentCover = _coverForPaddock(_p.id);
    });
    _panToSelectedPaddock(animate: true);
  }

  void _fireTapFeedback(int delta) {
    if (_showHints) setState(() => _showHints = false);
    _lastTapDelta = delta;
    _lastTapWasIncrease = delta > 0;
    _tapCtrl.forward(from: 0);
  }

  void _dismissHints() {
    if (!_showHints) return;
    setState(() => _showHints = false);
  }

  Future<void> _navNext() async {
    if (_moving) return;
    if (idx >= order.length - 1) return;
    _moving = true;
    try {
      await _next();
    } finally {
      _moving = false;
    }
  }

  Future<void> _navPrev() async {
    if (_moving) return;
    if (idx <= 0) return;
    _moving = true;
    try {
      await _prev();
    } finally {
      _moving = false;
    }
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<void> _init() async {
    order = await storage.loadPaddocks();
    order = order.where((p) => p.includeInRotation).toList();
    order.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));

    noteBtn1 = await storage.loadNoteButton1Title();
    noteBtn2 = await storage.loadNoteButton2Title();

    farmGrowth = await storage.effectiveFarmGrowthKgDmPerHaPerDay();

    final now = DateTime.now();

    for (final p in order) {
      final lm = await storage.lastMeasurementForPaddock(p.id);
      lastMeasured[p.id] = lm;

      final anchor = await storage.latestAnchorForPaddock(p.id);
      final base = anchor?.coverKgDmHa ?? 2500;
      final days = anchor == null ? 0 : now.difference(anchor.at).inDays;

      predictedNow[p.id] = clampCover(base + (days * farmGrowth).round());

      // ✅ If there is already a measurement today, start draft with that cover
      if (lm != null && _sameDay(lm.at, now)) {
        draftCover[p.id] = lm.cover;
      }
    }

    if (order.isNotEmpty) {
      currentCover = _coverForPaddock(order[idx].id);
    }
    coverStep = await storage.loadCoverStep();

    await _maybeLoadFarmMapForBackground();

    await _maybeGpsJumpToCurrentPaddock();
    await _maybeStartGpsLiveTracking();

    loaded = true;
    if (mounted) setState(() {});
  }

  Future<void> _maybeLoadFarmMapForBackground() async {
    final hasMap = await storage.hasFarmMap();
    _bgHasMap = hasMap;
    if (!hasMap) return;

    final polysRaw = await storage.loadFarmMapPolygons();
    if (polysRaw.isEmpty) return;
    _farmPolysRaw = polysRaw;

    _panToSelectedPaddock(animate: false);

    if (mounted) setState(() {});
  }

  ll.LatLng? _centerForPaddockId(String paddockId) {
    if (_farmPolysRaw.isEmpty) return null;

    for (final pr in _farmPolysRaw) {
      final id = pr['paddockId']?.toString();
      if (id != paddockId) continue;
      final ringsAny = pr['polys'];
      if (ringsAny is! List || ringsAny.isEmpty) return null;
      final ring = _ringToLatLon(ringsAny.first);
      if (ring == null || ring.length < 3) return null;

      double minLat = 1e30;
      double minLon = 1e30;
      double maxLat = -1e30;
      double maxLon = -1e30;
      for (final p in ring) {
        final lat = p[0];
        final lon = p[1];
        if (lat < minLat) minLat = lat;
        if (lon < minLon) minLon = lon;
        if (lat > maxLat) maxLat = lat;
        if (lon > maxLon) maxLon = lon;
      }
      if (minLat > maxLat || minLon > maxLon) return null;
      return ll.LatLng((minLat + maxLat) / 2.0, (minLon + maxLon) / 2.0);
    }

    return null;
  }

  void _panToSelectedPaddock({required bool animate}) {
    if (order.isEmpty) return;
    final c = _centerForPaddockId(_p.id);
    if (c == null) return;
    _panTo(c, animate: animate);
  }

  void _panTo(ll.LatLng target, {required bool animate}) {
    _mapPanTimer?.cancel();
    if (!animate) {
      _mapCenter = target;
      _safeMapMove(target, _mapZoom);
      return;
    }

    final start = _mapCenter ?? target;
    const dur = Duration(milliseconds: 280);
    const step = Duration(milliseconds: 16);
    final steps = (dur.inMilliseconds / step.inMilliseconds).round().clamp(
      1,
      999,
    );
    int i = 0;
    _mapPanTimer = Timer.periodic(step, (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      i++;
      final tt = (i / steps).clamp(0.0, 1.0);
      final ease = Curves.easeOutCubic.transform(tt);
      final lat = start.latitude + (target.latitude - start.latitude) * ease;
      final lon = start.longitude + (target.longitude - start.longitude) * ease;
      final p = ll.LatLng(lat, lon);
      _mapCenter = p;
      _safeMapMove(p, _mapZoom);
      if (tt >= 1.0) t.cancel();
    });
  }

  void _safeMapMove(ll.LatLng center, double zoom) {
    try {
      _mapController.move(center, zoom);
    } catch (_) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          _mapController.move(center, zoom);
        } catch (_) {
          // If the map still isn't ready, ignore this move.
        }
      });
    }
  }

  Future<void> _maybeStartGpsLiveTracking() async {
    if (order.isEmpty) return;

    _gpsTrackingActive = false;

    final gpsEnabled = await storage.loadGpsMeasuringEnabled();
    _gpsLiveEnabled = gpsEnabled;
    if (!gpsEnabled) return;

    final hasMap = await storage.hasFarmMap();
    if (!hasMap) return;

    if (mounted) setState(() {});

    final svc = await Geolocator.isLocationServiceEnabled();
    if (!svc) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    final polysRaw = await storage.loadFarmMapPolygons();
    if (polysRaw.isEmpty) return;
    _farmPolysRaw = polysRaw;

    if (mounted) setState(() {});

    _posSub?.cancel();
    _gpsTrackingActive = false;
    _posSub =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.bestForNavigation,
            distanceFilter: 1,
          ),
        ).listen((pos) async {
          if (!mounted) return;
          _lastPos = pos;

          if (!_gpsTrackingActive) {
            _gpsTrackingActive = true;
            if (mounted) setState(() {});
          }

          final hit = await _paddockIdForPosition(
            lat: pos.latitude,
            lon: pos.longitude,
            accuracyM: pos.accuracy,
          );
          await _maybeSwitchToHitPaddock(hit);

          final center = ll.LatLng(pos.latitude, pos.longitude);
          _mapCenter = center;
          _safeMapMove(center, _mapZoom);
          if (mounted) setState(() {});
        }, onError: (_) {});
  }

  Future<String?> _paddockIdForPosition({
    required double lat,
    required double lon,
    required double accuracyM,
  }) async {
    if (_farmPolysRaw.isEmpty) return null;
    if (accuracyM.isFinite && accuracyM > 80) return null;

    final allPaddocks = await storage.loadPaddocks();
    final paddockById = {for (final p in allPaddocks) p.id: p};
    final orderById = {for (final p in order) p.id: p};

    for (final pr in _farmPolysRaw) {
      final paddockId = pr['paddockId']?.toString();
      if (paddockId == null || paddockId.isEmpty) continue;

      final ringsAny = pr['polys'];
      if (ringsAny is! List) continue;

      for (final ringAny in ringsAny) {
        final ring = _ringToLatLon(ringAny);
        if (ring == null || ring.length < 3) continue;
        if (_pointInRing(lat: lat, lon: lon, ring: ring)) {
          final meta = paddockById[paddockId];
          if (meta != null && !meta.includeInRotation) {
            if (!_gpsExcludedWarned && mounted) {
              _gpsExcludedWarned = true;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('GPS: ${meta.name} is excluded')),
              );
            }
            return null;
          }

          if (!orderById.containsKey(paddockId)) {
            return null;
          }
          return paddockId;
        }
      }
    }

    return null;
  }

  Future<void> _maybeSwitchToHitPaddock(String? hitId) async {
    if (!mounted) return;
    if (hitId == null) {
      return;
    }

    if (hitId == _p.id) {
      return;
    }

    final now = DateTime.now();
    final last = _gpsLastSwitchAt;
    if (last != null &&
        now.difference(last) < const Duration(milliseconds: 700)) {
      return;
    }

    final newIdx = order.indexWhere((p) => p.id == hitId);
    if (newIdx < 0 || newIdx == idx) return;

    await _saveCurrent();
    if (!mounted) return;
    setState(() {
      idx = newIdx;
      currentCover = _coverForPaddock(_p.id);
    });

    if (!_gpsLiveEnabled) {
      _panToSelectedPaddock(animate: true);
    }

    _gpsLastSwitchAt = now;
  }

  Future<void> _maybeGpsJumpToCurrentPaddock() async {
    if (order.isEmpty) return;

    final gpsEnabled = await storage.loadGpsMeasuringEnabled();
    if (!gpsEnabled) return;

    final hasMap = await storage.hasFarmMap();
    if (!hasMap) return;

    final svc = await Geolocator.isLocationServiceEnabled();
    if (!svc) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
    } catch (_) {
      return;
    }

    final lat = pos.latitude;
    final lon = pos.longitude;

    final polysRaw = await storage.loadFarmMapPolygons();
    if (polysRaw.isEmpty) return;

    final allPaddocks = await storage.loadPaddocks();
    final paddockById = {for (final p in allPaddocks) p.id: p};

    final orderById = {for (final p in order) p.id: p};

    String? hit;
    for (final pr in polysRaw) {
      final paddockId = pr['paddockId']?.toString();
      if (paddockId == null || paddockId.isEmpty) continue;

      final meta = paddockById[paddockId];

      final ringsAny = pr['polys'];
      if (ringsAny is! List) continue;
      for (final ringAny in ringsAny) {
        final ring = _ringToLatLon(ringAny);
        if (ring == null || ring.length < 3) continue;
        if (_pointInRing(lat: lat, lon: lon, ring: ring)) {
          if (meta != null && !meta.includeInRotation) {
            if (!_gpsExcludedWarned && mounted) {
              _gpsExcludedWarned = true;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('GPS: ${meta.name} is excluded')),
              );
            }
            return;
          }

          if (!orderById.containsKey(paddockId)) {
            // Inside a paddock that isn't in the current round (e.g. excluded or not in rotation list)
            return;
          }
          hit = paddockId;
          break;
        }
      }
      if (hit != null) break;
    }

    if (hit == null) return;
    final newIdx = order.indexWhere((p) => p.id == hit);
    if (newIdx < 0 || newIdx == idx) return;
    if (!mounted) return;
    setState(() {
      idx = newIdx;
      currentCover = _coverForPaddock(order[idx].id);
    });
  }

  List<List<double>>? _ringToLatLon(dynamic ringAny) {
    if (ringAny is! List) return null;
    final out = <List<double>>[];
    for (final xyAny in ringAny) {
      if (xyAny is! List) continue;
      if (xyAny.length < 2) continue;
      final a = (xyAny[0] as num?)?.toDouble();
      final b = (xyAny[1] as num?)?.toDouble();
      if (a == null || b == null) continue;

      // Prefer [lon, lat]
      double lon = a;
      double lat = b;
      final degOk = (lat >= -90 && lat <= 90 && lon >= -180 && lon <= 180);
      if (!degOk) {
        final swappedDegOk = (a >= -90 && a <= 90 && b >= -180 && b <= 180);
        if (swappedDegOk) {
          lat = a;
          lon = b;
        } else {
          final looksProjected = a.abs() > 1000 && b.abs() > 1000;
          if (!looksProjected) return null;
          try {
            final pWgs = _nztm.transform(_wgs84, proj4.Point(x: a, y: b));
            lon = pWgs.x.toDouble();
            lat = pWgs.y.toDouble();
            if (lat < -90 || lat > 90 || lon < -180 || lon > 180) return null;
          } catch (_) {
            return null;
          }
        }
      }

      out.add([lat, lon]);
    }
    return out;
  }

  bool _pointInRing({
    required double lat,
    required double lon,
    required List<List<double>> ring,
  }) {
    bool inside = false;
    for (int i = 0, j = ring.length - 1; i < ring.length; j = i++) {
      final yi = ring[i][0];
      final xi = ring[i][1];
      final yj = ring[j][0];
      final xj = ring[j][1];

      final intersect =
          ((yi > lat) != (yj > lat)) &&
          (lon <
              (xj - xi) * (lat - yi) / ((yj - yi) == 0 ? 1e-12 : (yj - yi)) +
                  xi);
      if (intersect) inside = !inside;
    }
    return inside;
  }

  Paddock get _p => order[idx];
  int get _pred => predictedNow[_p.id] ?? 2500;
  Measurement? get _last => lastMeasured[_p.id];
  double get _gEff => farmGrowth;

  Future<void> _appendNote(String title) async {
    final t = title.trim();
    if (t.isEmpty) return;
    await storage.appendNote(
      NoteEntry(id: uuid.v4(), paddockId: _p.id, at: DateTime.now(), title: t),
    );
  }

  Future<void> _appendCustomNote() async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add note'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Note',
            border: OutlineInputBorder(),
          ),
          maxLines: 3,
          textInputAction: TextInputAction.newline,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;
    final t = ctrl.text.trim();
    if (t.isEmpty) return;
    await _appendNote(t);
  }

  // Centralised: decide what number should show when landing on a paddock
  int _coverForPaddock(String paddockId) {
    // 1) Draft (what you've typed this session)
    final d = draftCover[paddockId];
    if (d != null) return d;

    // 2) If there's a measurement today already, use it
    final lm = lastMeasured[paddockId];
    final now = DateTime.now();
    if (lm != null && _sameDay(lm.at, now)) return lm.cover;

    // 3) Otherwise predicted
    return predictedNow[paddockId] ?? 2500;
  }

  void _setCurrentCover(int v) {
    final clamped = clampCover(v);
    setState(() {
      currentCover = clamped;

      // Always store draft as you type/adjust so it "sticks"
      draftCover[_p.id] = clamped;
    });
  }

  Future<void> _saveCurrent() async {
    // Save whatever is currently on screen (draft already updated)
    final m = Measurement(
      id: uuid.v4(),
      paddockId: _p.id,
      at: DateTime.now(),
      cover: currentCover,
      predictedCoverAtEntry: _pred,
    );

    await storage.upsertMeasurementForToday(m);

    // keep in-memory caches in sync
    lastMeasured[_p.id] = m;
    draftCover[_p.id] = currentCover;
  }

  Future<void> _finish() async {
    await _saveCurrent();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _next() async {
    await _saveCurrent();
    if (idx < order.length - 1) {
      setState(() {
        idx++;
        currentCover = _coverForPaddock(_p.id); // use draft/today/predicted
      });
      _panToSelectedPaddock(animate: true);
    }
  }

  Future<void> _prev() async {
    await _saveCurrent();
    if (idx > 0) {
      setState(() {
        idx--;
        currentCover = _coverForPaddock(_p.id); // use draft/today/predicted
      });
      _panToSelectedPaddock(animate: true);
    }
  }

  void _adjust(int delta) {
    final step = delta.abs(); // 50 or 100
    final isIncrease = delta > 0;

    // Always snap to the step boundary so values stay clean (e.g. 100s) even
    // when the starting cover isn't aligned to the step.
    final next = isIncrease
        ? ((currentCover + step) ~/ step) * step
        : ((currentCover - 1) ~/ step) * step;

    _setCurrentCover(next);
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final now = DateTime.now();
    final lastCoverText = _last == null ? '—' : _last!.cover.toString();
    final lastDaysAgo = _last == null ? '—' : daysAgoLabel(now, _last!.at);

    final growthLine = '${_gEff.toStringAsFixed(1)}/day';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Record covers'),
        actions: [TextButton(onPressed: _finish, child: const Text('Finish'))],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            if (_bgHasMap) Positioned.fill(child: _gpsBgMap()),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            style: _bgHasMap
                                ? OutlinedButton.styleFrom(
                                    backgroundColor: _overlayBoxColor,
                                    foregroundColor: Colors.black,
                                  )
                                : null,
                            onPressed: () async {
                              await _appendNote(noteBtn1);
                              if (!context.mounted) return;
                            },
                            child: Text(
                              noteBtn1,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            style: _bgHasMap
                                ? OutlinedButton.styleFrom(
                                    backgroundColor: _overlayBoxColor,
                                    foregroundColor: Colors.black,
                                  )
                                : null,
                            onPressed: () async {
                              await _appendNote(noteBtn2);
                            },
                            child: Text(
                              noteBtn2,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: OutlinedButton(
                            style: _bgHasMap
                                ? OutlinedButton.styleFrom(
                                    backgroundColor: _overlayBoxColor,
                                    foregroundColor: Colors.black,
                                  )
                                : null,
                            onPressed: _appendCustomNote,
                            child: const Text(
                              'Custom',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onLongPress: () async {
                        _dismissHints();
                        await _openNotesSheet();
                      },
                      onHorizontalDragStart: (_) {
                        _hDragDx = 0.0;
                        _hDragHandled = false;
                      },
                      onHorizontalDragUpdate: (details) async {
                        if (_gpsTrackingActive) return;
                        if (_hDragHandled) return;
                        _hDragDx += details.delta.dx;

                        const trigger = 60.0;
                        if (_hDragDx <= -trigger) {
                          _hDragHandled = true;
                          _dismissHints();
                          await _navNext();
                        } else if (_hDragDx >= trigger) {
                          _hDragHandled = true;
                          _dismissHints();
                          await _navPrev();
                        }
                      },
                      onTapDown: (d) {
                        final w = context.size?.width ?? 0;
                        if (w <= 0) return;
                        final isIncrease = d.localPosition.dx >= (w / 2);
                        final delta = isIncrease ? coverStep : -coverStep;
                        _adjust(delta);
                        _fireTapFeedback(delta);
                      },
                      onHorizontalDragEnd: (details) async {
                        if (_gpsTrackingActive) return;
                        if (_hDragHandled) return;
                        _dismissHints();
                        final v = details.primaryVelocity ?? 0;
                        if (v.abs() < 300) return;
                        if (v < 0) {
                          await _navNext();
                        } else {
                          await _navPrev();
                        }
                      },
                      child: Stack(
                        children: [
                          AnimatedSwitcher(
                            duration: const Duration(milliseconds: 260),
                            switchInCurve: Curves.easeOut,
                            switchOutCurve: Curves.easeIn,
                            transitionBuilder: (child, anim) {
                              final begin = _lastTapWasIncrease
                                  ? const Offset(0.15, 0)
                                  : const Offset(-0.15, 0);
                              final slide = Tween<Offset>(
                                begin: begin,
                                end: Offset.zero,
                              ).animate(anim);
                              return FadeTransition(
                                opacity: anim,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: Column(
                              key: ValueKey(_p.id),
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                InkWell(
                                  onTap: () async {
                                    _dismissHints();
                                    await _jumpToPaddock();
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 2,
                                    ),
                                    child: Center(
                                      child: Text(
                                        'Paddock ${_p.name}  (${idx + 1}/${order.length})',
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w900,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _InfoCard(
                                        title: 'Last cover',
                                        value: lastCoverText,
                                        unit: 'kgDM/ha',
                                        meta: lastDaysAgo,
                                        solidBackground: _bgHasMap,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: _InfoCard(
                                        title: 'Predicted',
                                        value: _pred.toString(),
                                        unit: 'kgDM/ha',
                                        meta: growthLine,
                                        solidBackground: _bgHasMap,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                                Column(
                                  children: [
                                    Text(
                                      currentCover.toString(),
                                      style: const TextStyle(
                                        fontSize: 78,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                    const Text(
                                      'kgDM/ha',
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: Colors.black54,
                                      ),
                                    ),
                                  ],
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                          IgnorePointer(
                            child: AnimatedBuilder(
                              animation: _tapCtrl,
                              builder: (context, _) {
                                if (_tapCtrl.value <= 0) {
                                  return const SizedBox.shrink();
                                }

                                final isInc = _lastTapDelta > 0;
                                final color = isInc ? Colors.green : Colors.red;
                                final sideAlign = isInc
                                    ? Alignment.centerRight
                                    : Alignment.centerLeft;

                                final overlay = Align(
                                  alignment: sideAlign,
                                  child: FractionallySizedBox(
                                    widthFactor: 0.5,
                                    heightFactor: 1.0,
                                    child: Opacity(
                                      opacity: 0.25 * (1 - _tapOpacity.value),
                                      child: Container(color: color),
                                    ),
                                  ),
                                );

                                final sign = isInc ? '+' : '−';
                                final txt = '$sign${_lastTapDelta.abs()}';
                                final dx =
                                    (isInc ? 1 : -1) *
                                    (1 - _deltaT.value) *
                                    140;
                                final dy = (1 - _deltaT.value) * 40;
                                final floaty = Align(
                                  alignment: Alignment.center,
                                  child: Transform.translate(
                                    offset: Offset(dx, dy),
                                    child: Opacity(
                                      opacity: 1 - _tapOpacity.value,
                                      child: Text(
                                        txt,
                                        style: TextStyle(
                                          fontSize: 26,
                                          fontWeight: FontWeight.w900,
                                          color: color,
                                        ),
                                      ),
                                    ),
                                  ),
                                );

                                return Stack(children: [overlay, floaty]);
                              },
                            ),
                          ),
                          if (_showHints && idx == 0)
                            Positioned.fill(
                              child: IgnorePointer(
                                child: AnimatedOpacity(
                                  opacity: 1,
                                  duration: const Duration(milliseconds: 250),
                                  child: Container(
                                    color: Colors.black.withValues(alpha: 0.08),
                                    padding: const EdgeInsets.all(14),
                                    child: Stack(
                                      children: [
                                        Align(
                                          alignment: Alignment.bottomCenter,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 10,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(14),
                                              boxShadow: [
                                                BoxShadow(
                                                  blurRadius: 18,
                                                  color: Colors.black
                                                      .withValues(alpha: 0.12),
                                                ),
                                              ],
                                            ),
                                            child: const Text(
                                              'Tap left/right to -/+ cover\nSwipe to change paddock\nLong-press for notes\nTap header to jump',
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w800,
                                                color: Colors.black87,
                                                height: 1.25,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              left: 6.0,
                                            ),
                                            child: Text(
                                              '-$coverStep',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.red,
                                              ),
                                            ),
                                          ),
                                        ),
                                        Align(
                                          alignment: Alignment.centerRight,
                                          child: Padding(
                                            padding: const EdgeInsets.only(
                                              right: 6.0,
                                            ),
                                            child: Text(
                                              '+$coverStep',
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w900,
                                                color: Colors.green,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _gpsBgMap() {
    final pos = _lastPos;
    final gpsCenter = pos == null
        ? null
        : ll.LatLng(pos.latitude, pos.longitude);

    final center = (_gpsLiveEnabled && gpsCenter != null)
        ? gpsCenter
        : (_mapCenter ?? const ll.LatLng(0, 0));

    return IgnorePointer(
      child: Opacity(
        opacity: 0.42,
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: center,
            initialZoom: _mapZoom,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
            onMapEvent: (e) {
              final z = e.camera.zoom;
              if (z != _mapZoom && mounted) {
                setState(() => _mapZoom = z);
              }
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'pasture_walk',
              tileBuilder: (context, widget, tile) {
                return Opacity(
                  opacity: 0.65,
                  child: ColorFiltered(
                    colorFilter: const ColorFilter.matrix(<double>[
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0.2126,
                      0.7152,
                      0.0722,
                      0,
                      0,
                      0,
                      0,
                      0,
                      1,
                      0,
                    ]),
                    child: widget,
                  ),
                );
              },
            ),
            PolygonLayer(polygons: _bgMapPolygons()),
            if (_gpsLiveEnabled && pos != null)
              CircleLayer(
                circles: [
                  CircleMarker(
                    point: ll.LatLng(pos.latitude, pos.longitude),
                    radius: 7,
                    color: Colors.blue.withValues(alpha: 0.9),
                    borderStrokeWidth: 2,
                    borderColor: Colors.white,
                  ),
                  if (pos.accuracy.isFinite)
                    CircleMarker(
                      point: ll.LatLng(pos.latitude, pos.longitude),
                      radius: (pos.accuracy).clamp(8, 80).toDouble(),
                      useRadiusInMeter: true,
                      color: Colors.blue.withValues(alpha: 0.12),
                      borderStrokeWidth: 1,
                      borderColor: Colors.blue.withValues(alpha: 0.22),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Polygon> _bgMapPolygons() {
    if (_farmPolysRaw.isEmpty) return const [];

    final now = DateTime.now();
    final out = <Polygon>[];
    for (final pr in _farmPolysRaw) {
      final paddockId = pr['paddockId']?.toString();
      if (paddockId == null || paddockId.isEmpty) continue;

      final lm = lastMeasured[paddockId];
      final measuredToday = lm != null && _sameDay(lm.at, now);
      final isCurrent = paddockId == _p.id;

      final ringsAny = pr['polys'];
      if (ringsAny is! List) continue;

      for (final ringAny in ringsAny) {
        final ring = _ringToLatLon(ringAny);
        if (ring == null || ring.length < 3) continue;
        final pts = ring.map((e) => ll.LatLng(e[0], e[1])).toList();
        out.add(
          Polygon(
            points: pts,
            borderColor: measuredToday
                ? Colors.green.withValues(alpha: 0.95)
                : Colors.black.withValues(alpha: 0.45),
            borderStrokeWidth: measuredToday ? 3.0 : 1.4,
            color: isCurrent
                ? Colors.green.withValues(alpha: 0.26)
                : Colors.transparent,
            isFilled: true,
          ),
        );
        break;
      }
    }
    return out;
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final String meta;
  final bool solidBackground;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.meta,
    this.solidBackground = false,
  });

  @override
  Widget build(BuildContext context) {
    final bg = solidBackground
        ? Colors.grey.shade300.withValues(alpha: 0.80)
        : Colors.black.withValues(alpha: 0.04);
    final titleC = solidBackground
        ? Colors.black.withValues(alpha: 0.72)
        : Colors.black54;
    final metaC = solidBackground
        ? Colors.black.withValues(alpha: 0.62)
        : Colors.black45;
    return Card(
      elevation: 0,
      color: bg,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                color: titleC,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  value,
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(
                    unit,
                    style: TextStyle(
                      fontSize: 11,
                      color: titleC,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              meta,
              style: TextStyle(
                fontSize: 11,
                color: metaC,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
