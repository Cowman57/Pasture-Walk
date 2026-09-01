import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';
import 'dart:math' as math;
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' as ll;
import 'package:proj4dart/proj4dart.dart' as proj4;

import '../models.dart';
import '../storage.dart';
import '../utils.dart';
import 'round_screen.dart';
import 'settings_screen.dart';
import 'paddock_history_screen.dart';
import 'avg_cover_history_screen.dart';
import 'grazing_accuracy_screen.dart';
import 'grazing_schedule_preview_screen.dart';
import '../widgets/grazing_calendar_board.dart';

const _coverHeatStops = <(double, Color)>[
  (1400, Color(0xFFD32F2F)),
  (1800, Color(0xFFEF6C00)),
  (1900, Color(0xFFFDD835)),
  (2300, Color(0xFFC5E1A5)),
  (2900, Color(0xFF1B5E20)),
  (3000, Color(0xFF4FC3F7)),
  (3200, Color(0xFF0D47A1)),
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
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

class _CoverHeatKey extends StatelessWidget {
  const _CoverHeatKey();

  static const _minCover = 1400.0;
  static const _maxCover = 3200.0;
  static const _labels = [3200, 2900, 2300, 1800, 1400];
  static const _barH = 152.0;
  static const _labelH = 14.0;

  @override
  Widget build(BuildContext context) {
    final minC = _coverHeatStops.first.$1;
    final span = _coverHeatStops.last.$1 - minC;
    final colors = [for (final s in _coverHeatStops) s.$2];
    final stops = [
      for (final s in _coverHeatStops) ((s.$1 - minC) / span).clamp(0.0, 1.0),
    ];

    return Material(
      color: Colors.white.withValues(alpha: 0.92),
      elevation: 2,
      shadowColor: Colors.black.withValues(alpha: 0.18),
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'kgDM/ha',
              style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.2,
                color: Colors.black.withValues(alpha: 0.62),
              ),
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: _barH + _labelH,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: _labelH / 2),
                    child: Container(
                      width: 14,
                      height: _barH,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.28),
                        ),
                        gradient: LinearGradient(
                          begin: Alignment.bottomCenter,
                          end: Alignment.topCenter,
                          colors: colors,
                          stops: stops,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  SizedBox(
                    width: 40,
                    height: _barH + _labelH,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        for (final cover in _labels)
                          Positioned(
                            top:
                                (1.0 -
                                    (cover - _minCover) /
                                        (_maxCover - _minCover)) *
                                _barH,
                            left: 0,
                            child: Text(
                              cover >= 3200 ? '3200+' : '$cover',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: FontWeight.w800,
                                color: Colors.black.withValues(alpha: 0.82),
                              ),
                            ),
                          ),
                      ],
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
}

class _OutlinedLabelLines extends StatelessWidget {
  final List<String> lines;

  const _OutlinedLabelLines({required this.lines});

  @override
  Widget build(BuildContext context) {
    final t = lines.join('\n');
    return Stack(
      alignment: Alignment.center,
      children: [
        SizedBox(
          width: double.infinity,
          child: Text(
            t,
            textAlign: TextAlign.center,
            maxLines: lines.length,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              height: 1.05,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              foreground: Paint()
                ..style = PaintingStyle.stroke
                ..strokeWidth = 1.6
                ..color = Colors.white.withValues(alpha: 0.95),
            ),
          ),
        ),
        SizedBox(
          width: double.infinity,
          child: Text(
            t,
            textAlign: TextAlign.center,
            maxLines: lines.length,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              height: 1.05,
              fontSize: 14,
              fontWeight: FontWeight.w900,
              color: Colors.black.withValues(alpha: 0.92),
            ),
          ),
        ),
      ],
    );
  }
}

class _AccuracyBar extends StatelessWidget {
  final double value;
  final bool enabled;

  const _AccuracyBar({required this.value, required this.enabled});

  Color _colorFor(double v) {
    final x = v.clamp(0.0, 1.0);
    if (x < 0.5) {
      return Color.lerp(Colors.red, Colors.yellow, x / 0.5) ?? Colors.red;
    }
    return Color.lerp(Colors.yellow, Colors.green, (x - 0.5) / 0.5) ??
        Colors.green;
  }

  @override
  Widget build(BuildContext context) {
    final x = enabled ? value.clamp(0.0, 1.0) : 0.0;
    final c = _colorFor(x);
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 12,
        color: Colors.black.withValues(alpha: 0.08),
        child: Align(
          alignment: Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: x,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [c.withValues(alpha: 0.6), c]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MapPoly {
  final String paddockId;
  final String label;
  final double areaHa;
  final bool excluded;
  final int predicted;
  final bool pending;
  /// At least one grazing with `at` in the future (scheduled).
  final bool hasFutureGrazing;
  final List<List<ll.LatLng>> rings;
  final _MapBounds bounds;
  final ll.LatLng centroid;

  const _MapPoly({
    required this.paddockId,
    required this.label,
    required this.areaHa,
    required this.excluded,
    required this.predicted,
    required this.pending,
    required this.hasFutureGrazing,
    required this.rings,
    required this.bounds,
    required this.centroid,
  });
}

class _RowData {
  final Paddock paddock;
  final int? lastCover; // last recorded cover measurement
  final DateTime? lastAt; // when that measurement happened
  final int predicted; // predicted now (from latest anchor)
  final bool grazed; // last event is grazing
  final bool hasRecentNote; // note added today (used for home icon)
  /// Any stored grazing for this paddock with `at` after now (scheduled).
  final bool hasFutureGrazing;

  _RowData({
    required this.paddock,
    required this.lastCover,
    required this.lastAt,
    required this.predicted,
    required this.grazed,
    required this.hasRecentNote,
    required this.hasFutureGrazing,
  });
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin {
  final storage = Storage();
  final uuid = const Uuid();

  final MapController _mapController = MapController();
  bool _mapFitApplied = false;
  int _mapLayer = 1;
  final _mapZoom = ValueNotifier<double>(15);

  late final proj4.Projection _wgs84 =
      proj4.Projection.get('EPSG:4326') ?? proj4.Projection.WGS84;

  late final proj4.Projection _nztm =
      proj4.Projection.get('EPSG:2193') ??
      proj4.Projection.add(
        'EPSG:2193',
        '+proj=tmerc +lat_0=0 +lon_0=173 +k=0.9996 +x_0=1600000 +y_0=10000000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs',
      );

  bool loaded = false;
  List<Paddock> paddocks = [];

  // Layout
  static const double leftColW = 120;
  static const double cowColW = 28;

  static const String colRecorded = 'recorded';
  static const String colPredicted = 'predictedNow';

  // Sorting: default highest predicted cover first
  String sortCol = colPredicted;
  bool sortAsc = false;

  // Selection mode for grazing entry (paddocks / map)
  bool selectionMode = false;
  final Set<String> selectedPaddockIds = {};
  int residual = 1600;

  /// Grazings tab calendar: view by default; edit requires explicit mode.
  bool _grazingCalEdit = false;
  bool _grazingCalLeavePromptOpen = false;
  List<GrazingCalendarBlock>? _grazingCalWorking;
  ({List<GrazingCalendarBlock> blocks, double target})? _grazingCalData;
  Future<({List<GrazingCalendarBlock> blocks, double target})>?
      _grazingCalFuture;

  final Set<String> _selectedSummaryNoteIds = {};

  int _tabIndex = 0;
  int _herdFeedPage = 0;
  bool _grazingsTabMounted = false;
  bool _mapTabMounted = false;

  /// Map is the last home tab; used for grazing multi-select layout (bar + map).
  static const int _kMapTabIndex = 3;

  Future<List<_RowData>>? _rowsFuture;
  Future<List<dynamic>>? _summaryCardsFuture;
  Future<List<dynamic>>? _summaryWedgeFuture;
  Future<List<dynamic>>? _summaryNotesFuture;

  /// Avoid refetching map polygons/notes on every selection toggle.
  Future<List<dynamic>>? _mapTabDataFuture;

  static const Duration _grazingBarDropDuration = Duration(milliseconds: 340);

  late final AnimationController _grazingBarDropController;

  @override
  void initState() {
    super.initState();
    _grazingBarDropController = AnimationController(
      vsync: this,
      duration: _grazingBarDropDuration,
    );
    _load();
  }

  @override
  void dispose() {
    _grazingBarDropController.dispose();
    _mapZoom.dispose();
    super.dispose();
  }

  void _playGrazingBarDropIn() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _grazingBarDropController.forward(from: 0);
    });
  }

  void _resetGrazingBarDrop() {
    if (_grazingBarDropController.isAnimating) {
      _grazingBarDropController.stop();
    }
    _grazingBarDropController.reset();
  }

  Future<void> _load() async {
    paddocks = await storage.loadPaddocks();
    paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    loaded = true;
    _rowsFuture = _buildRows();
    _mapTabDataFuture = null;
    _summaryCardsFuture = null;
    _summaryWedgeFuture = null;
    _summaryNotesFuture = null;
    if (mounted) setState(() {});
  }

  Future<void> _refreshHome() async {
    _grazingCalFuture = null;
    _grazingCalData = null;
    if (!_grazingCalEdit) {
      _grazingCalWorking = null;
    }
    await _load();
    if (mounted) setState(() {});
  }

  Future<({List<GrazingCalendarBlock> blocks, double target})>
      _loadGrazingCalendar() async {
    final herds = await storage.loadHerds();
    final allPaddocks = await storage.loadPaddocks();
    final grazings = await storage.loadAllGrazings();
    final pById = {for (final p in allPaddocks) p.id: p};
    final target = Storage.totalAreaGrazedPerDayHa(herds);
    final blocks = <GrazingCalendarBlock>[];
    for (final g in grazings) {
      final p = pById[g.paddockId];
      if (p == null) continue;
      blocks.add(
        GrazingCalendarBlock(
          id: g.id,
          paddockId: g.paddockId,
          paddockName: p.name,
          areaHa: p.areaHa,
          startDay: g.at,
          durationDays: g.durationDays,
          isDraft: false,
          locked: false,
          preCover: g.preCover,
          residual: g.residual,
          harvestedKgDm: g.harvestedKgDm,
          enteredAt: g.enteredAt,
        ),
      );
    }
    return (blocks: blocks, target: target);
  }

  Future<({List<GrazingCalendarBlock> blocks, double target})>
      _ensureGrazingCalFuture() {
    return _grazingCalFuture ??= _loadGrazingCalendar().then((data) {
      _grazingCalData = data;
      if (mounted) setState(() {});
      return data;
    });
  }

  void _enterGrazingCalEdit(List<GrazingCalendarBlock> blocks) {
    setState(() {
      _grazingCalEdit = true;
      _grazingCalWorking = blocks.map((b) => b.copyWith()).toList();
    });
  }

  void _cancelGrazingCalEdit() {
    setState(() {
      _grazingCalEdit = false;
      _grazingCalWorking = null;
      _grazingCalFuture = null;
    });
  }

  Future<bool> _promptSaveGrazingCalIfNeeded() async {
    if (!_grazingCalEdit) return true;

    final action = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Save grazings?'),
        content: const Text(
          'You have unsaved grazing edits. Save them before leaving this tab?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text("Don't save"),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted) return false;
    if (action == null || action == 0) return false;
    if (action == 1) {
      await _saveGrazingCalEdit();
      return mounted;
    }
    _cancelGrazingCalEdit();
    return true;
  }

  Future<void> _selectHomeTab(int index) async {
    if (index == _tabIndex) return;
    if (_grazingCalLeavePromptOpen) return;
    if (_grazingCalEdit && index != 2) {
      _grazingCalLeavePromptOpen = true;
      final leave = await _promptSaveGrazingCalIfNeeded();
      _grazingCalLeavePromptOpen = false;
      if (!leave || !mounted) return;
    }
    setState(() {
      if (index == 2) _grazingsTabMounted = true;
      if (index == 3) _mapTabMounted = true;
      _tabIndex = index;
    });
  }

  Future<void> _saveGrazingCalEdit() async {
    final working = _grazingCalWorking;
    if (working == null) return;
    final existing = await storage.loadAllGrazings();
    final byId = {for (final g in existing) g.id: g};
    final keepIds = working.map((b) => b.id).toSet();

    for (final g in existing) {
      if (!keepIds.contains(g.id)) {
        await storage.deleteGrazingById(g.id);
      }
    }

    for (final b in working) {
      final prev = byId[b.id];
      final at = DateTime(
        b.startDay.year,
        b.startDay.month,
        b.startDay.day,
        prev?.at.hour ?? 12,
        prev?.at.minute ?? 0,
      );
      await storage.updateGrazing(
        Grazing(
          id: b.id,
          paddockId: b.paddockId,
          at: at,
          enteredAt: b.enteredAt ?? prev?.enteredAt ?? at,
          preCover: b.preCover ?? prev?.preCover ?? 2500,
          residual: b.residual ?? prev?.residual ?? residual,
          harvestedKgDm: b.harvestedKgDm ?? prev?.harvestedKgDm ?? 0,
          durationDays: b.durationDays < 1 ? 1 : b.durationDays,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _grazingCalEdit = false;
      _grazingCalWorking = null;
      _grazingCalFuture = null;
    });
    await _refreshHome();
  }

  Future<void> _deleteGrazingCalBlock(GrazingCalendarBlock b) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete grazing?'),
        content: Text('Remove ${b.paddockName} from the schedule?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() {
      _grazingCalWorking?.removeWhere((x) => x.id == b.id);
    });
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtDateShort(DateTime d) {
    const m = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd ${m[d.month - 1]}';
  }

  Future<List<_RowData>> _buildRows() async {
    final now = DateTime.now();

    final manualGrowth = await storage.loadManualFarmGrowthKgDmPerHaPerDay();
    final batch = await Future.wait([
      storage.loadAllMeasurements(),
      storage.loadAllGrazings(),
      storage.loadAllNotes(),
    ]);
    final msAll = batch[0] as List<Measurement>;
    final gsAll = batch[1] as List<Grazing>;
    final notesAll = batch[2] as List<NoteEntry>;

    final includedIds = paddocks
        .where((p) => p.includeInRotation)
        .map((p) => p.id)
        .toSet();
    final farmGrowth = manualGrowth ??
        storage.computeFarmGrowthFromLoadedData(msAll, gsAll, includedIds);

    final msByPdk = <String, List<Measurement>>{};
    for (final m in msAll) {
      (msByPdk[m.paddockId] ??= []).add(m);
    }
    for (final list in msByPdk.values) {
      list.sort((a, b) => b.at.compareTo(a.at));
    }

    final lastGrazingByPdk = <String, Grazing?>{};
    for (final g in gsAll) {
      if (g.at.isAfter(now)) continue; // ignore scheduled/future grazings
      final cur = lastGrazingByPdk[g.paddockId];
      if (cur == null || g.at.isAfter(cur.at)) {
        lastGrazingByPdk[g.paddockId] = g;
      }
    }

    final lastNoteByPdk = <String, NoteEntry?>{};
    for (final n in notesAll) {
      final cur = lastNoteByPdk[n.paddockId];
      if (cur == null || n.at.isAfter(cur.at)) {
        lastNoteByPdk[n.paddockId] = n;
      }
    }

    final out = <_RowData>[];
    for (final p in paddocks) {
      final list = msByPdk[p.id] ?? const <Measurement>[];
      final lastCoverM = list.isEmpty ? null : list.first;

      // note icon: show if note added today
      final lastNote = lastNoteByPdk[p.id];
      final hasRecentNote = lastNote != null && _sameDay(lastNote.at, now);

      // Grazed: last grazing within 3 days
      final lastG = lastGrazingByPdk[p.id];
      final grazed =
          lastG != null && DateTime.now().difference(lastG.at).inDays < 3;

      final isExcluded = !p.includeInRotation;
      final recordedCover = isExcluded ? null : lastCoverM?.cover;
      final recordedAt = isExcluded ? null : lastCoverM?.at;

      int predicted;

      // Cropped paddocks: predicted cover should be 0 so sorting doesn't float them up at 2500
      if (!p.includeInRotation) {
        predicted = 0;
      } else {
        // Latest anchor = last measurement OR last grazing residual
        final lastM = lastCoverM;
        final baseAt = (lastM == null && lastG == null)
            ? null
            : (lastM != null && lastG == null)
            ? lastM.at
            : (lastG != null && lastM == null)
            ? lastG.at
            : (lastM!.at.isAfter(lastG!.at) ? lastM.at : lastG.at);
        final baseCover = (lastM == null && lastG == null)
            ? 2500
            : (lastM != null && lastG == null)
            ? lastM.cover
            : (lastG != null && lastM == null)
            ? lastG.residual
            : (lastM!.at.isAfter(lastG!.at) ? lastM.cover : lastG.residual);
        final days = baseAt == null ? 0 : now.difference(baseAt).inDays;

        predicted = clampCover(baseCover + (days * farmGrowth).round());
      }

      final hasFutureGrazing = gsAll.any(
        (g) => g.paddockId == p.id && g.at.isAfter(now),
      );

      out.add(
        _RowData(
          paddock: p,
          lastCover: recordedCover,
          lastAt: recordedAt,
          predicted: predicted,
          grazed: grazed,
          hasRecentNote: hasRecentNote,
          hasFutureGrazing: hasFutureGrazing,
        ),
      );
    }
    return out;
  }

  void _toggleSort(String col) {
    setState(() {
      if (sortCol == col) {
        // Same column → flip direction
        sortAsc = !sortAsc;
      } else {
        sortCol = col;

        // Default direction:
        // - Paddock name: A→Z
        // - Area/Recorded/Predicted: HIGH→LOW
        sortAsc = (col == Storage.colPaddock);
      }
    });
  }

  // ----------------------------------------------------
  // Natural (numeric-aware) paddock name sorting
  // ----------------------------------------------------
  List<dynamic> _splitAlphaNum(String s) {
    final re = RegExp(r'(\d+|\D+)');
    return re.allMatches(s.toLowerCase()).map((m) {
      final part = m.group(0)!;
      final n = int.tryParse(part);
      return n ?? part;
    }).toList();
  }

  int _compareNatural(String a, String b) {
    final aa = _splitAlphaNum(a);
    final bb = _splitAlphaNum(b);

    final len = aa.length < bb.length ? aa.length : bb.length;
    for (int i = 0; i < len; i++) {
      final x = aa[i];
      final y = bb[i];

      if (x is int && y is int) {
        if (x != y) return x.compareTo(y);
      } else {
        final c = x.toString().compareTo(y.toString());
        if (c != 0) return c;
      }
    }
    return aa.length.compareTo(bb.length);
  }

  int _compare(_RowData a, _RowData b) {
    int cmp;
    switch (sortCol) {
      case Storage.colArea:
        cmp = a.paddock.areaHa.compareTo(b.paddock.areaHa);
        break;
      case colRecorded:
        cmp = (a.lastCover ?? -1).compareTo(b.lastCover ?? -1);
        break;
      case colPredicted:
        cmp = a.predicted.compareTo(b.predicted);
        break;
      case Storage.colPaddock:
      default:
        cmp = _compareNatural(a.paddock.name, b.paddock.name);
        break;
    }
    return sortAsc ? cmp : -cmp;
  }

  void _enterSelectionMode(String paddockId) {
    setState(() {
      selectionMode = true;
      selectedPaddockIds.add(paddockId);
    });
    _playGrazingBarDropIn();
  }

  void _toggleSelected(String paddockId) {
    final willExit =
        selectedPaddockIds.contains(paddockId) &&
        selectedPaddockIds.length == 1;
    if (willExit) {
      _resetGrazingBarDrop();
    }
    setState(() {
      if (selectedPaddockIds.contains(paddockId)) {
        selectedPaddockIds.remove(paddockId);
        if (selectedPaddockIds.isEmpty) {
          selectionMode = false;
        }
      } else {
        selectedPaddockIds.add(paddockId);
      }
    });
  }

  void _cancelSelection() {
    _resetGrazingBarDrop();
    setState(() {
      selectionMode = false;
      selectedPaddockIds.clear();
    });
  }

  double _selectedAreaHa(List<_RowData> rows) {
    var sum = 0.0;
    for (final r in rows) {
      if (selectedPaddockIds.contains(r.paddock.id)) {
        sum += r.paddock.areaHa;
      }
    }
    return sum;
  }

  Widget _grazingBar(List<_RowData> rows) {
    final areaHa = _selectedAreaHa(rows);
    return _GrazingBar(
      residual: residual,
      selectedCount: selectedPaddockIds.length,
      selectedAreaHa: areaHa,
      onResidualChanged: (v) => setState(() => residual = clampCover(v)),
      onUndo: selectedPaddockIds.isEmpty ? null : _undoGrazing,
      onPreview: selectedPaddockIds.isEmpty
          ? null
          : (range) async {
              final selected = rows
                  .where((r) => selectedPaddockIds.contains(r.paddock.id))
                  .map(
                    (r) => GrazingSchedulePaddock(
                      id: r.paddock.id,
                      name: r.paddock.name,
                      areaHa: r.paddock.areaHa,
                      predictedCoverKgDmHa: r.predicted,
                    ),
                  )
                  .toList();

              final saved = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => GrazingSchedulePreviewScreen(
                    paddocks: selected,
                    range: range,
                    residualKgDmHa: residual,
                  ),
                ),
              );

              if (saved == true) {
                _resetGrazingBarDrop();
                setState(() {
                  selectionMode = false;
                  selectedPaddockIds.clear();
                });
                await _refreshHome();
              }
            },
    );
  }

  Future<void> _undoGrazing() async {
    if (selectedPaddockIds.isEmpty) return;

    final removed = await storage.undoLatestGrazingsForPaddocks(
      selectedPaddockIds,
      withinHours: 24,
    );

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          removed == 0
              ? 'No grazings to undo in the last 24 hours.'
              : 'Undid $removed grazing${removed == 1 ? '' : 's'}.',
        ),
      ),
    );

    _resetGrazingBarDrop();
    setState(() {
      selectionMode = false;
      selectedPaddockIds.clear();
    });

    await _refreshHome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _topNavBar(),
            if (!selectionMode) _tabs(),
            Expanded(
              child: !loaded
                  ? const Center(child: CircularProgressIndicator())
                  : FutureBuilder<List<_RowData>>(
                      future: _rowsFuture,
                      builder: (context, snap) {
                        if (!snap.hasData) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }

                        final rows = [...(snap.data ?? <_RowData>[])];
                        rows.sort((a, b) => _compare(a, b));

                        if (!selectionMode) {
                          return ClipRect(
                            child: IndexedStack(
                              index: _tabIndex,
                              sizing: StackFit.expand,
                              children: [
                                _summaryTab(rows),
                                _paddocksTab(rows),
                                _grazingsTabMounted
                                    ? _grazingsTab(rows)
                                    : const SizedBox.shrink(),
                                _mapTabMounted
                                    ? _mapTab(rows)
                                    : const SizedBox.shrink(),
                              ],
                            ),
                          );
                        }

                        if (_tabIndex == _kMapTabIndex) {
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              final maxBarH = (constraints.maxHeight * 0.5)
                                  .clamp(120.0, 520.0);
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _grazingBarAnimatedShell(
                                    child: Material(
                                      elevation: 6,
                                      shadowColor: Colors.black.withValues(
                                        alpha: 0.35,
                                      ),
                                      color: Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.97),
                                      child: ConstrainedBox(
                                        constraints: BoxConstraints(
                                          maxHeight: maxBarH,
                                        ),
                                        child: SingleChildScrollView(
                                          physics:
                                              const ClampingScrollPhysics(),
                                          child: _grazingBar(rows),
                                        ),
                                      ),
                                    ),
                                  ),
                                  Expanded(child: _mapTab(rows)),
                                ],
                              );
                            },
                          );
                        }

                        return _paddocksTab(rows);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _topNavBar() {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: Container(
        height: 48,
        decoration: BoxDecoration(
          border: Border(
            bottom: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.45),
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(
          children: [
            if (selectionMode)
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: 'Cancel selection',
                onPressed: _cancelSelection,
              )
            else
              const SizedBox(width: 8),
            if (selectionMode)
              Expanded(
                child: Text(
                  'Select paddocks',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                  ),
                ),
              )
            else
              const Spacer(),
            if (!selectionMode && _tabIndex == 2) ..._grazingCalNavActions(),
            if (!selectionMode)
              IconButton(
                icon: const Icon(Icons.settings_outlined),
                tooltip: 'Settings',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                  await _refreshHome();
                },
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _grazingCalNavActions() {
    if (_grazingCalEdit) {
      return [
        TextButton(
          onPressed: _cancelGrazingCalEdit,
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 4),
        FilledButton(
          onPressed: _saveGrazingCalEdit,
          child: const Text('Save'),
        ),
        const SizedBox(width: 4),
      ];
    }

    final blocks = _grazingCalData?.blocks;
    return [
      TextButton.icon(
        onPressed: blocks == null
            ? null
            : () => _enterGrazingCalEdit(blocks),
        icon: const Icon(Icons.edit_outlined, size: 18),
        label: const Text('Edit'),
      ),
      const SizedBox(width: 4),
    ];
  }

  Widget _tabs() {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.45),
          ),
          boxShadow: [
            BoxShadow(
              color: cs.shadow.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: SizedBox(
            height: 46,
            child: Row(
              children: [
                Expanded(child: _homeTabSegment(0, 'Summary')),
                Expanded(child: _homeTabSegment(1, 'Paddocks')),
                Expanded(child: _homeTabSegment(2, 'Grazings')),
                Expanded(child: _homeTabSegment(3, 'Map')),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _homeTabSegment(int index, String label) {
    final cs = Theme.of(context).colorScheme;
    final selected = _tabIndex == index;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => _selectHomeTab(index),
          borderRadius: BorderRadius.circular(14),
          splashColor: cs.primary.withValues(alpha: 0.12),
          highlightColor: cs.primary.withValues(alpha: 0.06),
          child: Semantics(
            button: true,
            selected: selected,
            label: label,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 10),
              decoration: BoxDecoration(
                color: selected ? cs.primaryContainer : Colors.transparent,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.22)
                      : Colors.transparent,
                  width: 1,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: 0.14),
                          blurRadius: 6,
                          offset: const Offset(0, 2),
                        ),
                      ]
                    : null,
              ),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12.5,
                  letterSpacing: 0.15,
                  fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  color: selected
                      ? cs.onPrimaryContainer
                      : cs.onSurfaceVariant,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _mapTab(List<_RowData> rows) {
    final byId = {for (final r in rows) r.paddock.id: r};

    return FutureBuilder<List<dynamic>>(
      future: _mapTabDataFuture ??= Future.wait([
        storage.loadFarmMapPolygons(),
        storage.loadAllNotes(),
        storage.loadHiddenSummaryNoteIds(),
      ]),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final polys = (snap.data![0] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        final notes = (snap.data![1] as List<NoteEntry>);
        final hidden = (snap.data![2] as Set<String>);

        if (polys.isEmpty) {
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
                    'Import a farm map (GeoJSON or Shapefile zip) from Settings to enable the map view.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                      await _refreshHome();
                    },
                    child: const Text('Open Settings'),
                  ),
                ],
              ),
            ),
          );
        }

        final pendingByPdk = <String, bool>{};
        for (final n in notes) {
          if (hidden.contains(n.id)) continue;
          pendingByPdk[n.paddockId] = true;
        }

        final mapPolys = _buildMapPolys(polys, byId, pendingByPdk);
        final farmBounds = _boundsForMapPolys(mapPolys);

        return LayoutBuilder(
          builder: (context, constraints) {
            if (!_mapFitApplied && mapPolys.isNotEmpty && farmBounds != null) {
              _mapFitApplied = true;
            }

            if (mapPolys.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.map_outlined, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'Map could not be rendered',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'The imported file contained no valid paddock polygons to display.',
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const SettingsScreen(),
                            ),
                          );
                          await _refreshHome();
                        },
                        child: const Text('Open Settings'),
                      ),
                    ],
                  ),
                ),
              );
            }

            final bg = (_mapLayer == 1)
                ? Colors.black.withValues(alpha: 0.04)
                : Colors.white;

            final tileUrl = _mapLayer == 0
                ? 'https://tile.openstreetmap.org/{z}/{x}/{y}.png'
                : 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}';

            return Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: bg)),
                Positioned.fill(
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter:
                          farmBounds?.center ?? const ll.LatLng(0, 0),
                      initialZoom: 15,
                      onMapEvent: (e) {
                        final z = e.camera.zoom;
                        if ((z - _mapZoom.value).abs() > 1e-4) {
                          _mapZoom.value = z;
                        }
                      },
                      interactionOptions: const InteractionOptions(
                        flags:
                            InteractiveFlag.drag |
                            InteractiveFlag.pinchZoom |
                            InteractiveFlag.doubleTapZoom |
                            InteractiveFlag.flingAnimation,
                      ),
                      onTap: (tapPosition, point) async {
                        final hitId = _hitTest(point, mapPolys);
                        if (hitId == null) return;
                        final r = byId[hitId];
                        if (r == null) return;
                        if (selectionMode) {
                          _toggleSelected(hitId);
                          return;
                        }
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                PaddockHistoryScreen(paddock: r.paddock),
                          ),
                        );
                        await _refreshHome();
                      },
                      onLongPress: (tapPosition, point) {
                        final hitId = _hitTest(point, mapPolys);
                        if (hitId == null) return;
                        if (byId[hitId] == null) return;
                        if (selectionMode) return;
                        _enterSelectionMode(hitId);
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: tileUrl,
                        userAgentPackageName: 'pasture_walk',
                      ),
                      PolygonLayer(
                        polygons: mapPolys.map((p) {
                          final c = _heatColorForCover(p.predicted);
                          final sel =
                              selectionMode &&
                              selectedPaddockIds.contains(p.paddockId);
                          final futureBorder =
                              p.hasFutureGrazing && !p.excluded && !sel;
                          return Polygon(
                            points: p.rings.first,
                            borderColor: sel
                                ? Colors.blue.shade700
                                : (futureBorder
                                      ? Colors.blue.shade600
                                      : Colors.black.withValues(alpha: 0.55)),
                            borderStrokeWidth: sel
                                ? 3.2
                                : (futureBorder ? 2.8 : 1.6),
                            isFilled: true,
                            color: p.excluded
                                ? Colors.grey.withValues(alpha: 0.25)
                                : c.withValues(alpha: sel ? 0.95 : 0.90),
                          );
                        }).toList(),
                      ),
                      PolylineLayer(
                        polylines: () {
                          final out = <Polyline>[];
                          for (final p in mapPolys) {
                            if (!p.pending) continue;
                            if (p.rings.isEmpty || p.rings.first.length < 2) {
                              continue;
                            }
                            out.add(_solidRing(p.rings.first));
                          }
                          return out;
                        }(),
                      ),
                      ValueListenableBuilder<double>(
                        valueListenable: _mapZoom,
                        builder: (context, zoom, _) => MarkerLayer(
                        markers: () {
                          final ref = _avgBoundsPx(mapPolys, zoom);
                          final out = <Marker>[];

                          for (final p in mapPolys) {
                            final lines = _labelLines(p, ref);
                            final opacity = _labelOpacity(lines, ref, zoom);
                            final show3 = lines.length >= 3;

                            if (p.pending && show3) {
                              out.add(
                                Marker(
                                  point: p.centroid,
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.topRight,
                                  child: Transform.translate(
                                    offset: const Offset(18, -16),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.92,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.black.withValues(
                                            alpha: 0.20,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.10,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Icon(
                                        Icons.note_alt_outlined,
                                        size: 16,
                                        color: Colors.black.withValues(
                                          alpha: 0.75,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            if (p.hasFutureGrazing &&
                                !p.excluded &&
                                show3) {
                              out.add(
                                Marker(
                                  point: p.centroid,
                                  width: 22,
                                  height: 22,
                                  alignment: Alignment.topLeft,
                                  child: Transform.translate(
                                    offset: const Offset(-18, -16),
                                    child: Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: Colors.white.withValues(
                                          alpha: 0.92,
                                        ),
                                        borderRadius: BorderRadius.circular(8),
                                        border: Border.all(
                                          color: Colors.blue.withValues(
                                            alpha: 0.35,
                                          ),
                                        ),
                                        boxShadow: [
                                          BoxShadow(
                                            color: Colors.black.withValues(
                                              alpha: 0.10,
                                            ),
                                            blurRadius: 6,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Text(
                                        '🐄',
                                        style: TextStyle(
                                          fontSize: 15,
                                          height: 1.0,
                                          color: Colors.blue.shade800,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }

                            final w = math.max(
                              110.0,
                              math.min(180.0, ref.width * 0.85),
                            );
                            final hBase = 26.0;
                            final h = hBase + (lines.length - 1) * 16.0;

                            out.add(
                              Marker(
                                point: p.centroid,
                                width: w,
                                height: h,
                                alignment: Alignment.center,
                                child: Opacity(
                                  opacity: opacity,
                                  child: _OutlinedLabelLines(lines: lines),
                                ),
                              ),
                            );
                          }

                          return out;
                        }(),
                      ),
                      ),
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  bottom: 12 + MediaQuery.paddingOf(context).bottom,
                  child: const _CoverHeatKey(),
                ),
                Positioned(
                  right: 12,
                  top: 12,
                  child: FloatingActionButton.small(
                    heroTag: 'map-layer',
                    onPressed: () {
                      setState(() {
                        _mapLayer = (_mapLayer + 1) % 2;
                      });
                    },
                    child: const Icon(Icons.layers_outlined),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Color _heatColorForCover(int cover) {
    const stops = _coverHeatStops;
    final v = cover.toDouble();
    if (v <= stops.first.$1) return stops.first.$2;
    if (v >= stops.last.$1) return stops.last.$2;
    for (var i = 1; i < stops.length; i++) {
      final lo = stops[i - 1];
      final hi = stops[i];
      if (v <= hi.$1) {
        final t = ((v - lo.$1) / (hi.$1 - lo.$1)).clamp(0.0, 1.0);
        return Color.lerp(lo.$2, hi.$2, t) ?? hi.$2;
      }
    }
    return stops.last.$2;
  }

  _MapBounds? _boundsForMapPolys(List<_MapPoly> polys) {
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

  List<_MapPoly> _buildMapPolys(
    List<Map<String, dynamic>> polys,
    Map<String, _RowData> byId,
    Map<String, bool> pendingByPdk,
  ) {
    final out = <_MapPoly>[];
    for (final p in polys) {
      final paddockId = p['paddockId']?.toString();
      if (paddockId == null || paddockId.isEmpty) continue;
      final row = byId[paddockId];
      if (row == null) continue;

      final ringsAny = p['polys'];
      if (ringsAny is! List) continue;

      final rings = <List<ll.LatLng>>[];
      for (final ringAny in ringsAny) {
        if (ringAny is! List) continue;
        final pts = <ll.LatLng>[];
        var invalid = false;
        for (final xyAny in ringAny) {
          if (xyAny is! List) continue;
          if (xyAny.length < 2) continue;
          final a = (xyAny[0] as num?)?.toDouble();
          final b = (xyAny[1] as num?)?.toDouble();
          if (a == null || b == null) continue;

          // Prefer GeoJSON-style [lon, lat] degrees.
          // If coords look projected (meters), transform NZTM -> WGS84.
          // If degrees appear swapped, swap.
          ll.LatLng? pt;
          final degOk = (b >= -90 && b <= 90 && a >= -180 && a <= 180);
          if (degOk) {
            pt = ll.LatLng(b, a);
          } else {
            final swappedDegOk = (a >= -90 && a <= 90 && b >= -180 && b <= 180);
            if (swappedDegOk) {
              pt = ll.LatLng(a, b);
            } else {
              // Heuristic: NZTM eastings/northings are ~1,000,000 to 2,500,000 / 4,000,000 to 10,000,000.
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
                  // ignore and mark invalid below
                }
              }
            }
          }

          if (pt == null) {
            invalid = true;
            break;
          }
          pts.add(pt);
        }
        if (!invalid && pts.length >= 3) {
          rings.add(pts);
        }
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
        _MapPoly(
          paddockId: paddockId,
          label: row.paddock.name,
          areaHa: row.paddock.areaHa,
          excluded: !row.paddock.includeInRotation,
          predicted: row.predicted,
          pending: pendingByPdk[paddockId] == true,
          hasFutureGrazing: row.hasFutureGrazing,
          rings: rings,
          bounds: bounds,
          centroid: centroid,
        ),
      );
    }
    return out;
  }

  String? _hitTest(ll.LatLng p, List<_MapPoly> polys) {
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

  Size _boundsPx(_MapBounds b, double zoom) {
    final z = zoom.clamp(0.0, 22.0);
    final scale = 256.0 * math.pow(2.0, z);

    double mercY(double lat) {
      final r = lat.clamp(-85.05112878, 85.05112878) * math.pi / 180.0;
      return math.log(math.tan((math.pi / 4.0) + (r / 2.0)));
    }

    final dLon = (b.northEast.longitude - b.southWest.longitude).abs();
    final w = (dLon * scale / 360.0);

    final y0 = mercY(b.southWest.latitude);
    final y1 = mercY(b.northEast.latitude);
    final h = ((y1 - y0).abs() * scale / (2.0 * math.pi));
    return Size(w.isFinite ? w : 0, h.isFinite ? h : 0);
  }

  Size _avgBoundsPx(List<_MapPoly> polys, double zoom) {
    if (polys.isEmpty) return const Size(0, 0);
    double sw = 0;
    double sh = 0;
    int n = 0;
    for (final p in polys) {
      final sz = _boundsPx(p.bounds, zoom);
      if (sz.width <= 0 || sz.height <= 0) continue;
      sw += sz.width;
      sh += sz.height;
      n++;
    }
    if (n == 0) return const Size(0, 0);
    return Size(sw / n, sh / n);
  }

  List<String> _labelLines(_MapPoly p, Size ref) {
    final out = <String>[p.label];

    final can2 = ref.width >= 120 && ref.height >= 70;
    final can3 = ref.width >= 140 && ref.height >= 95;

    if (can2) {
      out.add('${p.predicted}');
    }
    if (can3) {
      out.add('${p.areaHa.toStringAsFixed(1)} ha');
    }
    return out;
  }

  double _labelOpacity(List<String> lines, Size ref, double zoom) {
    if (lines.isEmpty) return 0.0;
    final style = const TextStyle(
      fontSize: 14,
      fontWeight: FontWeight.w900,
      height: 1.05,
    );
    final tp = TextPainter(
      text: TextSpan(text: lines.join('\n'), style: style),
      textAlign: TextAlign.center,
      textDirection: TextDirection.ltr,
      maxLines: lines.length,
    )..layout();

    final availW = math.max(1.0, ref.width * 0.80);
    final availH = math.max(1.0, ref.height * 0.60);
    final overflow = math.max(tp.width / availW, tp.height / availH);

    var a = 1.0;
    if (overflow > 1.0) {
      a *= (1.0 / overflow).clamp(0.0, 1.0);
    }
    if (zoom < 13) {
      a *= ((zoom - 11.5) / (13 - 11.5)).clamp(0.0, 1.0);
    }
    return a.clamp(0.0, 1.0);
  }

  Polyline _solidRing(List<ll.LatLng> ring) {
    final pts = [...ring];
    if (pts.length >= 2 && pts.first != pts.last) pts.add(pts.first);
    return Polyline(
      points: pts,
      strokeWidth: 3.0,
      color: Colors.orange.withValues(alpha: 0.95),
    );
  }


  Widget _summaryTab(List<_RowData> rows) {
    final included = rows.where((r) => r.paddock.includeInRotation).toList();
    included.sort((a, b) => b.predicted.compareTo(a.predicted));

    final predicted = included
        .map((r) => r.predicted)
        .where((v) => v > 0)
        .toList();
    final avgCover = predicted.isEmpty
        ? 0
        : (predicted.reduce((a, b) => a + b) / predicted.length).round();

    DateTime? lastMeasureDay;
    DateTime? lastMeasureAt;
    for (final r in included) {
      if (r.lastAt == null) continue;
      final d = calendarDay(r.lastAt!);
      if (lastMeasureDay == null ||
          d.isAfter(lastMeasureDay) ||
          (d == lastMeasureDay && r.lastAt!.isAfter(lastMeasureAt!))) {
        lastMeasureDay = d;
        lastMeasureAt = r.lastAt;
      }
    }
    final measuredCovers = <int>[];
    if (lastMeasureDay != null) {
      for (final r in included) {
        if (r.lastCover == null || r.lastAt == null) continue;
        if (calendarDay(r.lastAt!) == lastMeasureDay) {
          measuredCovers.add(r.lastCover!);
        }
      }
    }
    final measuredAvg = measuredCovers.isEmpty
        ? null
        : (measuredCovers.reduce((a, b) => a + b) / measuredCovers.length)
            .round();

    final wedgePaddocks = included.where((r) => r.predicted > 0).map((r) {
      final m = RegExp(r'\d+').firstMatch(r.paddock.name);
      final label = m?.group(0) ?? '';
      return _WedgePaddock(label: label, cover: r.predicted);
    }).toList();

    final bottomInset = MediaQuery.paddingOf(context).bottom;
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset + 16),
      children: [
        SizedBox(
          width: double.infinity,
          height: 64,
          child: FilledButton(
            onPressed: () async {
              if (included.isEmpty) {
                if (!context.mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    icon: Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange.shade800,
                      size: 36,
                    ),
                    title: const Text('Add paddocks first'),
                    content: const Text(
                      'You need at least one paddock included in your rotation '
                      'before you can record covers.\n\n'
                      'Open Settings (the gear icon): use Add / edit paddocks to '
                      'add paddocks and turn on “Include in rotation”, and use '
                      'Recording order to set the walk order.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                );
                return;
              }
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const RoundScreen()));
              await _refreshHome();
            },
            child: const Text(
              'Start Recording Covers',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _summaryCards(
          avgCover: avgCover,
          measuredAvg: measuredAvg,
          measuredAt: lastMeasureAt,
        ),
        const SizedBox(height: 12),
        _FeedWedge(
          paddocks: wedgePaddocks,
          storage: storage,
          onChanged: _refreshHome,
        ),
        const SizedBox(height: 12),
        _summaryUnderWedgeWidgets(),
        const SizedBox(height: 12),
        _summaryNotes(),
      ],
    );
  }

  Widget _summaryUnderWedgeWidgets() {
    return FutureBuilder<List<dynamic>>(
      future: _summaryWedgeFuture ??= Future.wait([
        storage.loadHerds(),
        storage.loadPaddocks(),
        storage.loadAllGrazings(),
      ]),
      builder: (context, snap) {
        final data = snap.data;

        final herds = (data != null && data.isNotEmpty)
            ? (data[0] as List<Herd>)
            : <Herd>[];
        final paddocks = (data != null && data.length > 1)
            ? (data[1] as List<Paddock>)
            : <Paddock>[];
        final grazings = (data != null && data.length > 2)
            ? (data[2] as List<Grazing>)
            : <Grazing>[];

        final pById = {for (final p in paddocks) p.id: p};
        final totalAreaPerDay = Storage.totalAreaGrazedPerDayHa(herds);

        final now = DateTime.now();
        final today = DateTime(now.year, now.month, now.day);
        final start = today.subtract(const Duration(days: 6));

        double areaWeek = 0.0;
        var harvestedWeek = 0;
        for (final g in grazings) {
          if (g.at.isAfter(now)) continue;
          final p = pById[g.paddockId];
          if (p == null || !p.includeInRotation) continue;
          forEachGrazingAllocationDay(
            g.at,
            g.durationDays,
            areaHa: p.areaHa,
            harvestedKgDm: g.harvestedKgDm.toDouble(),
            fn: (day, area, harvest) {
              if (day.isBefore(start) || day.isAfter(today)) return;
              areaWeek += area;
              harvestedWeek += harvest.round();
            },
          );
        }
        final actualAreaPerDay = areaWeek / 7.0;

        final acc = (totalAreaPerDay <= 0)
            ? null
            : (actualAreaPerDay / totalAreaPerDay);
        final accPct = acc == null ? null : (acc * 100).clamp(0.0, 999.0);

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: Card(
                  elevation: 0,
                  color: Colors.black.withValues(alpha: 0.04),
                  child: SizedBox(
                    height: 148,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                      child: StatefulBuilder(
                        builder: (context, setLocal) {
                          final page = herds.isEmpty
                              ? 0
                              : _herdFeedPage.clamp(0, herds.length - 1);
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text(
                                      'kgDM/cow/day',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.black54,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  InkWell(
                                    onTap: _editHerds,
                                    child: const Padding(
                                      padding: EdgeInsets.all(2),
                                      child: Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                        color: Colors.black45,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Expanded(
                                child: herds.isEmpty
                                    ? InkWell(
                                        onTap: _editHerds,
                                        child: const Align(
                                          alignment: Alignment.centerLeft,
                                          child: Text(
                                            'Tap edit to add herds',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black54,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ),
                                      )
                                    : PageView.builder(
                                        itemCount: herds.length,
                                        onPageChanged: (i) {
                                          _herdFeedPage = i;
                                          setLocal(() {});
                                        },
                                        itemBuilder: (context, i) {
                                          final h = herds[i];
                                          final pasture = _kgDmCowDayForHerd(
                                            herd: h,
                                            totalAreaPerDay: totalAreaPerDay,
                                            harvestedWeek: harvestedWeek,
                                          );
                                          final supp =
                                              h.supplementKgDmPerCowPerDay;
                                          final total = pasture == null
                                              ? null
                                              : pasture + supp;
                                          String fmt(double? v) => v == null
                                              ? '—'
                                              : v.toStringAsFixed(1);
                                          return Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                h.name,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                              const SizedBox(height: 4),
                                              _herdFeedLine(
                                                'Pasture',
                                                fmt(pasture),
                                              ),
                                              _herdFeedLine(
                                                'Supplement',
                                                fmt(supp),
                                              ),
                                              _herdFeedLine(
                                                'Total',
                                                fmt(total),
                                                bold: true,
                                              ),
                                            ],
                                          );
                                        },
                                      ),
                              ),
                              if (herds.length > 1)
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    for (var i = 0; i < herds.length; i++)
                                      Container(
                                        width: 6,
                                        height: 6,
                                        margin: const EdgeInsets.symmetric(
                                          horizontal: 2,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: i == page
                                              ? Colors.black87
                                              : Colors.black26,
                                        ),
                                      ),
                                  ],
                                ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: InkWell(
                  onTap: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const GrazingAccuracyScreen(),
                      ),
                    );
                    if (!mounted) return;
                    await _refreshHome();
                  },
                  child: Card(
                    elevation: 0,
                    color: Colors.black.withValues(alpha: 0.04),
                    child: SizedBox(
                      height: 148,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Grazing accuracy',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (totalAreaPerDay <= 0)
                              const Expanded(
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'Set herd areas to track\nactual vs target ha/day',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.black54,
                                      fontWeight: FontWeight.w600,
                                      height: 1.3,
                                    ),
                                  ),
                                ),
                              )
                            else ...[
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${(accPct ?? 0).toStringAsFixed(0)}%',
                                    style: const TextStyle(
                                      fontSize: 22,
                                      fontWeight: FontWeight.w900,
                                      height: 1,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Padding(
                                      padding: const EdgeInsets.only(bottom: 4),
                                      child: _AccuracyBar(
                                        value: acc ?? 0.0,
                                        enabled: true,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              _herdFeedLine(
                                'Target',
                                '${totalAreaPerDay.toStringAsFixed(2)} ha/d',
                              ),
                              _herdFeedLine(
                                'Actual (7d)',
                                '${actualAreaPerDay.toStringAsFixed(2)} ha/d',
                              ),
                              _herdFeedLine(
                                'Difference',
                                '${actualAreaPerDay >= totalAreaPerDay ? '+' : ''}${(actualAreaPerDay - totalAreaPerDay).toStringAsFixed(2)} ha/d',
                                bold: true,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  double? _kgDmCowDayForHerd({
    required Herd herd,
    required double totalAreaPerDay,
    required int harvestedWeek,
  }) {
    if (herd.cowCount <= 0 || totalAreaPerDay <= 0) return null;
    final share = herd.areaGrazedPerDayHa / totalAreaPerDay;
    return (harvestedWeek * share) / herd.cowCount / 7.0;
  }

  Widget _herdFeedLine(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 1),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 11,
                color: Colors.black54,
                fontWeight: bold ? FontWeight.w800 : FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: bold ? FontWeight.w900 : FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editHerds() async {
    final existing = await storage.loadHerds();
    if (!mounted) return;

    final drafts = existing
        .map(
          (h) => _HerdDraft(
            id: h.id,
            nameCtrl: TextEditingController(text: h.name),
            cowsCtrl: TextEditingController(
              text: h.cowCount <= 0 ? '' : '${h.cowCount}',
            ),
            areaCtrl: TextEditingController(
              text: h.areaGrazedPerDayHa <= 0
                  ? ''
                  : h.areaGrazedPerDayHa.toStringAsFixed(2),
            ),
            suppCtrl: TextEditingController(
              text: h.supplementKgDmPerCowPerDay <= 0
                  ? ''
                  : h.supplementKgDmPerCowPerDay.toStringAsFixed(1),
            ),
          ),
        )
        .toList();

    if (drafts.isEmpty) {
      drafts.add(
        _HerdDraft(
          id: 'herd_milkers',
          nameCtrl: TextEditingController(text: 'Milkers'),
          cowsCtrl: TextEditingController(),
          areaCtrl: TextEditingController(),
          suppCtrl: TextEditingController(),
        ),
      );
    }

    List<Herd>? result;
    try {
      result = await showDialog<List<Herd>>(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setLocal) {
              List<Herd>? parseDrafts() {
                final saved = <Herd>[];
                for (final d in drafts) {
                  final name = d.nameCtrl.text.trim().isEmpty
                      ? 'Herd'
                      : d.nameCtrl.text.trim();
                  final cowsText = d.cowsCtrl.text.trim();
                  final areaText = d.areaCtrl.text.trim();
                  final suppText = d.suppCtrl.text.trim();
                  final cows =
                      cowsText.isEmpty ? 0 : int.tryParse(cowsText);
                  final area = areaText.isEmpty
                      ? 0.0
                      : double.tryParse(areaText);
                  final supp = suppText.isEmpty
                      ? 0.0
                      : double.tryParse(suppText);
                  if (cows == null ||
                      cows < 0 ||
                      area == null ||
                      area < 0 ||
                      supp == null ||
                      supp < 0) {
                    return null;
                  }
                  saved.add(
                    Herd(
                      id: d.id,
                      name: name,
                      cowCount: cows,
                      areaGrazedPerDayHa: area,
                      supplementKgDmPerCowPerDay: supp,
                    ),
                  );
                }
                return saved.isEmpty ? null : saved;
              }

              return AlertDialog(
                title: const Text('Herds'),
                content: SizedBox(
                  width: double.maxFinite,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: MediaQuery.sizeOf(ctx).height * 0.55,
                    ),
                    child: SingleChildScrollView(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (var i = 0; i < drafts.length; i++) ...[
                            if (i > 0) const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Herd ${i + 1}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ),
                                if (drafts.length > 1)
                                  IconButton(
                                    tooltip: 'Remove herd',
                                    onPressed: () {
                                      final removed = drafts.removeAt(i);
                                      setLocal(() {});
                                      WidgetsBinding.instance
                                          .addPostFrameCallback((_) {
                                        removed.dispose();
                                      });
                                    },
                                    icon: const Icon(Icons.delete_outline),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            TextField(
                              controller: drafts[i].nameCtrl,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: drafts[i].cowsCtrl,
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(
                                labelText: 'Cows',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: drafts[i].areaCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Area grazed (ha/day)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: drafts[i].suppCtrl,
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              decoration: const InputDecoration(
                                labelText: 'Supplement (kgDM/cow/day)',
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                          const SizedBox(height: 12),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton.icon(
                              onPressed: () {
                                setLocal(() {
                                  drafts.add(
                                    _HerdDraft(
                                      id:
                                          'herd_${DateTime.now().millisecondsSinceEpoch}',
                                      nameCtrl: TextEditingController(
                                        text: drafts.any(
                                              (d) =>
                                                  d.nameCtrl.text
                                                      .trim()
                                                      .toLowerCase() ==
                                                  'dry',
                                            )
                                            ? 'Herd ${drafts.length + 1}'
                                            : 'Dry',
                                      ),
                                      cowsCtrl: TextEditingController(),
                                      areaCtrl: TextEditingController(),
                                      suppCtrl: TextEditingController(),
                                    ),
                                  );
                                });
                              },
                              icon: const Icon(Icons.add),
                              label: const Text('Add herd'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      final saved = parseDrafts();
                      if (saved == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Check herd cows and area values.',
                            ),
                          ),
                        );
                        return;
                      }
                      Navigator.pop(ctx, saved);
                    },
                    child: const Text('Save'),
                  ),
                ],
              );
            },
          );
        },
      );
    } finally {
      final toDispose = List<_HerdDraft>.from(drafts);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final d in toDispose) {
          d.dispose();
        }
      });
    }

    if (result == null || !mounted) return;
    await storage.saveHerds(result);
    if (!mounted) return;
    await _refreshHome();
  }

  Widget _summaryNotes() {
    return FutureBuilder<List<dynamic>>(
      future: _summaryNotesFuture ??= Future.wait([
        storage.loadAllNotes(),
        storage.loadHiddenSummaryNoteIds(),
        storage.loadPaddocks(),
      ]),
      builder: (context, snap) {
        final selecting = _selectedSummaryNoteIds.isNotEmpty;
        final data = snap.data;
        final allNotes = (data != null && data.isNotEmpty)
            ? (data[0] as List<NoteEntry>)
            : <NoteEntry>[];
        final hidden = (data != null && data.length > 1)
            ? (data[1] as Set<String>)
            : <String>{};
        final paddocks = (data != null && data.length > 2)
            ? (data[2] as List<Paddock>)
            : <Paddock>[];

        final pdkById = {for (final p in paddocks) p.id: p};

        final visible = allNotes.where((n) => !hidden.contains(n.id)).toList()
          ..sort((a, b) => b.at.compareTo(a.at));

        final recent = visible.take(20).toList();

        return Card(
          elevation: 0,
          color: Colors.black.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Notes',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (selecting)
                      TextButton(
                        onPressed: () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: const Text('Clear selected notes?'),
                              content: const Text(
                                'This will remove them from the Summary screen only. They will still remain in paddock history.',
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('Cancel'),
                                ),
                                ElevatedButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('Clear'),
                                ),
                              ],
                            ),
                          );

                          if (ok != true) return;
                          final ids = _selectedSummaryNoteIds.toList();
                          for (final id in ids) {
                            await storage.hideSummaryNoteId(id);
                          }
                          _selectedSummaryNoteIds.clear();
                          if (!mounted) return;
                          setState(() {});
                          await _refreshHome();
                        },
                        child: Text(
                          'Clear (${_selectedSummaryNoteIds.length})',
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (recent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text('No notes.'),
                  ),
                for (final n in recent)
                  InkWell(
                    onLongPress: () {
                      setState(() {
                        if (_selectedSummaryNoteIds.contains(n.id)) {
                          _selectedSummaryNoteIds.remove(n.id);
                        } else {
                          _selectedSummaryNoteIds.add(n.id);
                        }
                      });
                    },
                    onTap: () {
                      if (!selecting) return;
                      setState(() {
                        if (_selectedSummaryNoteIds.contains(n.id)) {
                          _selectedSummaryNoteIds.remove(n.id);
                        } else {
                          _selectedSummaryNoteIds.add(n.id);
                        }
                      });
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: _selectedSummaryNoteIds.contains(n.id)
                            ? Colors.blue.withValues(alpha: 0.12)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 6,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(
                            width: 56,
                            child: Text(
                              () {
                                final p = pdkById[n.paddockId];
                                if (p == null) return '';
                                final m = RegExp(r'\d+').firstMatch(p.name);
                                return m?.group(0) ?? '';
                              }(),
                              style: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                          SizedBox(
                            width: 60,
                            child: Text(
                              _fmtDateShort(n.at),
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              n.title,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
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
        );
      },
    );
  }

  Widget _avgCoverSlide({
    required String title,
    required String value,
    required String subtitle,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 12,
            height: 1.15,
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 22,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            fontSize: 11,
            height: 1.15,
            color: Colors.black54,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _avgCoverCard({
    required int? measuredAvg,
    required DateTime? measuredAt,
    required int expectedAvg,
  }) {
    final now = DateTime.now();
    final measuredLabel = measuredAt == null
        ? 'No measurements'
        : daysAgoLabel(now, measuredAt);
    final measuredValue = measuredAvg?.toString() ?? '—';
    final expectedValue = expectedAvg > 0 ? '$expectedAvg' : '—';

    return InkWell(
      onTap: () async {
        await Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const AvgCoverHistoryScreen()),
        );
      },
      child: Card(
        elevation: 0,
        color: Colors.black.withValues(alpha: 0.04),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: SizedBox(
                height: 72,
                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(right: 18),
                      child: PageView(
                        children: [
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: _avgCoverSlide(
                              title: 'Last measurement',
                              value: measuredValue,
                              subtitle: 'kgDM/ha · $measuredLabel',
                            ),
                          ),
                          FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.topLeft,
                            child: _avgCoverSlide(
                              title: 'Expected',
                              value: expectedValue,
                              subtitle: 'kgDM/ha · predicted',
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Positioned(
                      right: -6,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        child: Center(
                          child: Icon(
                            Icons.chevron_right,
                            size: 22,
                            color: Colors.black38,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  Widget _summaryCards({
    required int avgCover,
    required int? measuredAvg,
    required DateTime? measuredAt,
  }) {
    return FutureBuilder<List<dynamic>>(
      future: _summaryCardsFuture ??= Future.wait([
        storage.effectiveFarmGrowthKgDmPerHaPerDay(),
        storage.loadAreaGrazedPerDayHa(),
        storage.loadCoverTrendTimescale(),
        storage.loadPaddocks(),
        storage.loadAllGrazings(),
      ]),
      builder: (context, snap) {
        final data = snap.data;
        final growth = (data != null && data.isNotEmpty)
            ? (data[0] as double)
            : 0.0;
        final areaPerDay = (data != null && data.length > 1)
            ? (data[1] as double)
            : 0.0;
        final timescale = (data != null && data.length > 2)
            ? (data[2] as String)
            : 'day';
        final allPaddocks = (data != null && data.length > 3)
            ? (data[3] as List<Paddock>)
            : <Paddock>[];
        final allGrazings = (data != null && data.length > 4)
            ? (data[4] as List<Grazing>)
            : <Grazing>[];

        final includedIds = allPaddocks
            .where((p) => p.includeInRotation)
            .map((p) => p.id)
            .toSet();

        final includedArea = allPaddocks
            .where((p) => p.includeInRotation)
            .fold<double>(0.0, (sum, p) => sum + p.areaHa);

        final roundLengthDays = (areaPerDay > 0 && includedArea > 0)
            ? (includedArea / areaPerDay)
            : null;

        // Cover trend: avg actual pre/post from last 7 days of past grazings only.
        final now = DateTime.now();
        final since = now.subtract(const Duration(days: 7));
        final recentPast = allGrazings
            .where(
              (g) =>
                  includedIds.contains(g.paddockId) &&
                  !g.at.isAfter(now) &&
                  !g.at.isBefore(since),
            )
            .toList();
        double? requiredGrowth;
        if (roundLengthDays != null &&
            roundLengthDays > 0 &&
            recentPast.isNotEmpty) {
          final avgPre =
              recentPast.map((g) => g.preCover).reduce((a, b) => a + b) /
              recentPast.length;
          final avgPost =
              recentPast.map((g) => g.residual).reduce((a, b) => a + b) /
              recentPast.length;
          requiredGrowth = (avgPre - avgPost) / roundLengthDays;
        }

        final deltaPerDay = requiredGrowth == null
            ? null
            : (growth - requiredGrowth);

        final factor = timescale == 'week'
            ? 7.0
            : (timescale == 'month' ? 30.0 : 1.0);
        final deltaScaled = deltaPerDay == null ? null : deltaPerDay * factor;

        final timescaleUnit = timescale == 'week'
            ? 'kgDM/ha/week'
            : (timescale == 'month' ? 'kgDM/ha/month' : 'kgDM/ha/day');

        String deltaText;
        if (deltaScaled == null) {
          deltaText = '—';
        } else {
          final sign = deltaScaled >= 0 ? '+' : '';
          deltaText = '$sign${deltaScaled.toStringAsFixed(0)}';
        }

        final roundText = roundLengthDays == null
            ? '—'
            : roundLengthDays.toStringAsFixed(1);

        return Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _avgCoverCard(
                    measuredAvg: measuredAvg,
                    measuredAt: measuredAt,
                    expectedAvg: avgCover,
                  ),
                ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: _editGrowth,
                    child: Card(
                      elevation: 0,
                      color: Colors.black.withValues(alpha: 0.04),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Growth',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              growth.toStringAsFixed(1),
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'kgDM/ha/day',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
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
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: _editAreaGrazedPerDay,
                    child: Card(
                      elevation: 0,
                      color: Colors.black.withValues(alpha: 0.04),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Round length',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              roundText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'days  (${areaPerDay.toStringAsFixed(2)} ha/day)',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _editTrendTimescale,
                    child: Card(
                      elevation: 0,
                      color: Colors.black.withValues(alpha: 0.04),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Cover trend',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              deltaText,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              timescaleUnit,
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
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
          ],
        );
      },
    );
  }

  Future<void> _editAreaGrazedPerDay() async {
    await _editHerds();
  }

  Future<void> _editTrendTimescale() async {
    final current = await storage.loadCoverTrendTimescale();
    if (!mounted) return;
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Cover trend timescale'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'day'),
            child: Row(
              children: [
                if (current == 'day') const Icon(Icons.check, size: 18),
                if (current != 'day') const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('Day'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'week'),
            child: Row(
              children: [
                if (current == 'week') const Icon(Icons.check, size: 18),
                if (current != 'week') const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('Week'),
              ],
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'month'),
            child: Row(
              children: [
                if (current == 'month') const Icon(Icons.check, size: 18),
                if (current != 'month') const SizedBox(width: 18),
                const SizedBox(width: 8),
                const Text('Month'),
              ],
            ),
          ),
        ],
      ),
    );

    if (picked == null) return;
    await storage.saveCoverTrendTimescale(picked);
    await _refreshHome();
  }

  Future<void> _editGrowth() async {
    final start = await storage.loadManualFarmGrowthKgDmPerHaPerDay();
    final ctrl = TextEditingController(text: start?.toStringAsFixed(1) ?? '');
    if (!mounted) return;
    final action = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Farm growth rate'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'kgDM/ha/day',
            helperText: 'Leave blank to use auto-calculated growth',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 0),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 2),
            child: const Text('Use auto'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 1),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (!mounted) return;

    if (action == null || action == 0) return;

    if (action == 2) {
      await storage.clearManualFarmGrowthKgDmPerHaPerDay();
      await _refreshHome();
      return;
    }

    final t = ctrl.text.trim();
    if (t.isEmpty) {
      await storage.clearManualFarmGrowthKgDmPerHaPerDay();
      await _refreshHome();
      return;
    }

    final v = double.tryParse(t);
    if (v == null) return;
    await storage.saveManualFarmGrowthKgDmPerHaPerDay(v);
    await _refreshHome();
  }

  /// Reveals the grazing bar by growing height from the top; content below in
  /// the parent [Column] moves down in sync (map or paddock list).
  Widget _grazingBarAnimatedShell({required Widget child}) {
    return ClipRect(
      clipBehavior: Clip.hardEdge,
      child: SizeTransition(
        sizeFactor: CurvedAnimation(
          parent: _grazingBarDropController,
          curve: Curves.easeOutCubic,
        ),
        axis: Axis.vertical,
        axisAlignment: -1,
        child: child,
      ),
    );
  }

  Widget _paddocksTab(List<_RowData> rows) {
    return Column(
      children: [
        if (selectionMode)
          _grazingBarAnimatedShell(
            child: Material(
              elevation: 6,
              shadowColor: Colors.black.withValues(alpha: 0.35),
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.97),
              child: _grazingBar(rows),
            ),
          ),
        _stickyHeader(),
        const Divider(height: 1),
        Expanded(
          child: ListView.separated(
            itemCount: rows.length,
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (ctx, i) => _row(rows[i]),
          ),
        ),
      ],
    );
  }

  /// Farm-wide grazings on the shared calendar board (view until Edit).
  Widget _grazingsTab(List<_RowData> _) {
    return FutureBuilder<({List<GrazingCalendarBlock> blocks, double target})>(
      future: _ensureGrazingCalFuture(),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final data = snap.data!;
        final blocks = _grazingCalEdit
            ? (_grazingCalWorking ?? data.blocks)
            : data.blocks;

        return Padding(
          padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
          child: GrazingCalendarBoard(
            key: ValueKey('gcal_edit_$_grazingCalEdit'),
            blocks: blocks,
            targetHaDay: data.target,
            interaction: _grazingCalEdit
                ? GrazingCalendarInteraction.edit
                : GrazingCalendarInteraction.view,
            onBlocksChanged: _grazingCalEdit
                ? (next) {
                    setState(() => _grazingCalWorking = [...next]);
                  }
                : null,
            onBlockLongPress:
                _grazingCalEdit ? _deleteGrazingCalBlock : null,
          ),
        );
      },
    );
  }

  Widget _stickyHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          SizedBox(width: cowColW, child: const SizedBox()),
          SizedBox(
            width: leftColW,
            child: _hdrCell(
              Storage.colPaddock,
              'Pdk',
              unit: '',
              alignLeft: true,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _hdrCell(Storage.colArea, 'Area', unit: 'ha')),
                Expanded(
                  child: _hdrCell(colRecorded, 'Recorded', unit: 'kgDM/ha'),
                ),
                Expanded(
                  child: _hdrCell(colPredicted, 'Predicted', unit: 'kgDM/ha'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdrCell(
    String col,
    String label, {
    required String unit,
    bool alignLeft = false,
  }) {
    final isSorted = sortCol == col;
    final arrow = isSorted ? (sortAsc ? ' ▲' : ' ▼') : '';
    return InkWell(
      onTap: () => _toggleSort(col),
      child: Column(
        crossAxisAlignment: alignLeft
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Text(
            '$label$arrow',
            style: const TextStyle(
              fontSize: 11,
              color: Colors.black87,
              fontWeight: FontWeight.w700,
            ),
            textAlign: alignLeft ? TextAlign.left : TextAlign.center,
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: const TextStyle(
                fontSize: 10,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
              textAlign: alignLeft ? TextAlign.left : TextAlign.center,
            ),
        ],
      ),
    );
  }

  Widget _row(_RowData r) {
    final now = DateTime.now();

    final isExcluded = !r.paddock.includeInRotation;

    const minCoverBar = 1200;
    const maxCoverBar = 3200;
    final denom = (maxCoverBar - minCoverBar);
    final cover = r.lastCover;
    final clamped = cover == null
        ? minCoverBar
        : cover.clamp(minCoverBar, maxCoverBar);
    final t = (cover == null || denom <= 0)
        ? 0.0
        : ((clamped - minCoverBar) / denom);

    // ✅ Prev line becomes "Excluded" when cropped
    final prevText = isExcluded
        ? 'Excluded'
        : (r.lastAt == null
              ? 'Prev —'
              : 'Prev ${daysAgoLabel(now, r.lastAt!)}');

    // ✅ Grey out if grazed OR excluded
    final rowGreyed = r.grazed || isExcluded;

    final isSelected = selectedPaddockIds.contains(r.paddock.id);
    final bg = selectionMode && isSelected
        ? Colors.lightBlue.withValues(alpha: 0.15)
        : Colors.transparent;
    final textColor = rowGreyed ? Colors.black38 : Colors.black87;
    final subColor = rowGreyed ? Colors.black26 : Colors.blueGrey;

    return InkWell(
      onLongPress: () {
        if (!selectionMode) _enterSelectionMode(r.paddock.id);
      },
      onTap: () async {
        if (selectionMode) {
          _toggleSelected(r.paddock.id);
        } else {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => PaddockHistoryScreen(paddock: r.paddock),
            ),
          );
          await _refreshHome();
        }
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: t,
                heightFactor: 1,
                child: Container(color: Colors.green.withValues(alpha: 0.14)),
              ),
            ),
          ),
          Container(
            color: bg,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                SizedBox(
                  width: cowColW,
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ✅ excluded red symbol (takes priority visually)
                        if (isExcluded)
                          const Icon(Icons.block, size: 16, color: Colors.red),

                        // grazed symbol
                        if (!isExcluded && r.grazed)
                          const Text('🐄', style: TextStyle(fontSize: 16)),

                        // scheduled (future) grazing — blue cow vs unstyled 🐄 for recently grazed
                        if (!isExcluded && r.hasFutureGrazing)
                          Text(
                            '🐄',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.blue.shade700,
                            ),
                          ),

                        // note symbol
                        if (r.hasRecentNote)
                          const Icon(Icons.sticky_note_2_outlined, size: 16),

                        if (isExcluded == false &&
                            r.grazed == false &&
                            r.hasRecentNote == false &&
                            r.hasFutureGrazing == false)
                          const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: leftColW,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        r.paddock.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        prevText,
                        style: TextStyle(fontSize: 11, color: subColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.paddock.areaHa.toStringAsFixed(1),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.lastCover?.toString() ?? '—',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.predicted.toString(),
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 14, color: textColor),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _WedgePaddock {
  final String label;
  final int cover;
  const _WedgePaddock({required this.label, required this.cover});
}

class _HerdDraft {
  final String id;
  final TextEditingController nameCtrl;
  final TextEditingController cowsCtrl;
  final TextEditingController areaCtrl;
  final TextEditingController suppCtrl;

  _HerdDraft({
    required this.id,
    required this.nameCtrl,
    required this.cowsCtrl,
    required this.areaCtrl,
    required this.suppCtrl,
  });

  void dispose() {
    nameCtrl.dispose();
    cowsCtrl.dispose();
    areaCtrl.dispose();
    suppCtrl.dispose();
  }
}

class _FeedWedge extends StatelessWidget {
  final List<_WedgePaddock> paddocks;
  final Storage storage;
  final Future<void> Function() onChanged;

  const _FeedWedge({
    required this.paddocks,
    required this.storage,
    required this.onChanged,
  });

  Future<({int? avgPre, int? avgPost})> _autoPrePost() async {
    final paddocksAll = await storage.loadPaddocks();
    final includedIds = paddocksAll
        .where((p) => p.includeInRotation)
        .map((p) => p.id)
        .toSet();

    final now = DateTime.now();
    final allGrazings = await storage.loadAllGrazings();
    final scheduled = allGrazings.where(
      (g) => includedIds.contains(g.paddockId) && g.at.isAfter(now),
    ).toList();

    if (scheduled.isNotEmpty) {
      final avgPre = (scheduled
              .map((g) => g.preCover)
              .reduce((a, b) => a + b) /
          scheduled.length).round();
      final avgPost = (scheduled
              .map((g) => g.residual)
              .reduce((a, b) => a + b) /
          scheduled.length).round();
      return (avgPre: avgPre, avgPost: avgPost);
    }

    final avg = await storage.avgGrazingPrePostLastDays(
      days: 7,
      includedPaddockIds: includedIds,
    );
    return (avgPre: avg.avgPre, avgPost: avg.avgPost);
  }

  Future<void> _editTargets(BuildContext context) async {
    final auto = await _autoPrePost();
    final preOverride = await storage.loadFeedWedgePreGrazingOverride();
    final postOverride = await storage.loadFeedWedgePostGrazingResidualOverride();
    if (!context.mounted) return;

    final preCtrl = TextEditingController(
      text: (preOverride ?? auto.avgPre)?.toString() ?? '',
    );
    final postCtrl = TextEditingController(
      text: (postOverride ?? auto.avgPost)?.toString() ?? '',
    );
    final autoLabel = (auto.avgPre != null && auto.avgPost != null)
        ? 'Auto: ${auto.avgPre} → ${auto.avgPost}'
        : 'Auto: no grazings available';

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Feed wedge pre / post'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              autoLabel,
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(ctx).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: preCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Pre-grazing cover',
                helperText: 'kgDM/ha (leave blank for auto)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: postCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Post-grazing residual',
                helperText: 'kgDM/ha (leave blank for auto)',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'cancel'),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'auto'),
            child: const Text('Use auto'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, 'save'),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result == null || result == 'cancel') return;

    if (result == 'auto') {
      await storage.clearFeedWedgePreGrazingOverride();
      await storage.clearFeedWedgePostGrazingResidualOverride();
      await onChanged();
      return;
    }

    final preText = preCtrl.text.trim();
    final postText = postCtrl.text.trim();
    if (preText.isEmpty) {
      await storage.clearFeedWedgePreGrazingOverride();
    } else {
      final pre = int.tryParse(preText);
      if (pre == null) return;
      await storage.saveFeedWedgePreGrazingTarget(pre);
    }
    if (postText.isEmpty) {
      await storage.clearFeedWedgePostGrazingResidualOverride();
    } else {
      final post = int.tryParse(postText);
      if (post == null) return;
      await storage.saveFeedWedgePostGrazingResidualTarget(post);
    }
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        storage.loadFeedWedgePreGrazingOverride(),
        storage.loadFeedWedgePostGrazingResidualOverride(),
        _autoPrePost(),
      ]),
      builder: (context, snap) {
        final preOverride = (snap.data != null && snap.data!.isNotEmpty)
            ? snap.data![0] as int?
            : null;
        final postOverride = (snap.data != null && snap.data!.length > 1)
            ? snap.data![1] as int?
            : null;
        final auto = (snap.data != null && snap.data!.length > 2)
            ? snap.data![2] as ({int? avgPre, int? avgPost})
            : (avgPre: null, avgPost: null);

        final pre = preOverride ?? auto.avgPre ?? 2800;
        final post = postOverride ?? auto.avgPost ?? 1500;
        final isAuto = preOverride == null && postOverride == null;
        final buttonLabel = isAuto
            ? 'Auto: $pre → $post'
            : 'Override: $pre → $post';

        final screenW = MediaQuery.of(context).size.width;
        final plotW = (paddocks.length * 26).toDouble();
        final chartW = plotW < (screenW - 24) ? (screenW - 24) : plotW;

        return Card(
          elevation: 0,
          color: Colors.black.withValues(alpha: 0.04),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Feed wedge',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () => _editTargets(context),
                      child: Text(buttonLabel),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: chartW,
                      child: CustomPaint(
                        painter: _FeedWedgePainter(
                          paddocks: paddocks,
                          preTarget: pre,
                          postResidualTarget: post,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _FeedWedgePainter extends CustomPainter {
  final List<_WedgePaddock> paddocks;
  final int preTarget;
  final int postResidualTarget;

  _FeedWedgePainter({
    required this.paddocks,
    required this.preTarget,
    required this.postResidualTarget,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final leftPad = 44.0;
    final rightPad = 10.0;
    final topPad = 10.0;
    final bottomPad = 46.0;

    final plot = Rect.fromLTWH(
      leftPad,
      topPad,
      size.width - leftPad - rightPad,
      size.height - topPad - bottomPad,
    );

    final maxCover = paddocks.isEmpty
        ? 0
        : paddocks.map((p) => p.cover).reduce((a, b) => a > b ? a : b);
    final yMax0 = [
      maxCover,
      preTarget,
      postResidualTarget,
    ].reduce((a, b) => a > b ? a : b);
    final yMax = ((yMax0 + 199) ~/ 200) * 200;

    final gridPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x22000000);

    final axisPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x33000000);

    for (int y = 0; y <= yMax; y += 500) {
      final yy = _y(plot, y.toDouble(), yMax.toDouble());
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), gridPaint);
      _drawText(
        canvas,
        y.toString(),
        Offset(6, yy - 7),
        const TextStyle(
          fontSize: 10,
          color: Color(0x99000000),
          fontWeight: FontWeight.w700,
        ),
      );
    }

    canvas.drawRect(plot, axisPaint);

    if (paddocks.isEmpty) {
      return;
    }

    final n = paddocks.length;
    final barW = plot.width / n;
    final barPaint = Paint()..color = const Color(0xFF6DAA41);

    for (int i = 0; i < n; i++) {
      final p = paddocks[i];
      final x0 = plot.left + i * barW;
      final x1 = x0 + barW;
      final y0 = _y(plot, p.cover.toDouble(), yMax.toDouble());

      final rect = Rect.fromLTRB(
        x0 + barW * 0.18,
        y0,
        x1 - barW * 0.18,
        plot.bottom,
      );
      canvas.drawRect(rect, barPaint);

      final label = p.label;
      if (label.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: label,
            style: const TextStyle(
              fontSize: 10,
              color: Color(0xCC000000),
              fontWeight: FontWeight.w700,
            ),
          ),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          textAlign: TextAlign.center,
          ellipsis: '…',
        )..layout(maxWidth: barW);
        tp.paint(canvas, Offset(x0 + (barW - tp.width) / 2, plot.bottom + 6));
      }
    }

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF2F66E3);

    final xStart = plot.left + barW * 0.5;
    final xEnd = plot.left + barW * (n - 0.5);
    final yStart = _y(plot, preTarget.toDouble(), yMax.toDouble());
    final yEnd = _y(plot, postResidualTarget.toDouble(), yMax.toDouble());
    canvas.drawLine(Offset(xStart, yStart), Offset(xEnd, yEnd), linePaint);
  }

  double _y(Rect plot, double value, double yMax) {
    final v = value.clamp(0, yMax);
    final frac = yMax <= 0 ? 0.0 : (v / yMax);
    return plot.bottom - frac * plot.height;
  }

  void _drawText(Canvas canvas, String text, Offset offset, TextStyle style) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, offset);
  }

  @override
  bool shouldRepaint(covariant _FeedWedgePainter oldDelegate) {
    return oldDelegate.paddocks != paddocks ||
        oldDelegate.preTarget != preTarget ||
        oldDelegate.postResidualTarget != postResidualTarget;
  }
}

class _GrazingBar extends StatefulWidget {
  final int residual;
  final int selectedCount;
  final double selectedAreaHa;
  final ValueChanged<int> onResidualChanged;
  final VoidCallback? onUndo;
  final ValueChanged<DateTimeRange>? onPreview;

  const _GrazingBar({
    required this.residual,
    required this.selectedCount,
    this.selectedAreaHa = 0,
    required this.onResidualChanged,
    required this.onUndo,
    required this.onPreview,
  });

  @override
  State<_GrazingBar> createState() => _GrazingBarState();
}

class _GrazingBarState extends State<_GrazingBar> {
  late final TextEditingController _ctrl;

  DateTimeRange? _range;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.residual.toString());
    final t = _today();
    _range = DateTimeRange(start: t, end: t.add(const Duration(days: 6)));
  }

  @override
  void didUpdateWidget(covariant _GrazingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.residual != widget.residual &&
        _ctrl.text != widget.residual.toString()) {
      _ctrl.text = widget.residual.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  int _daysInRange(DateTimeRange r) {
    final start = _day(r.start);
    final end = _day(r.end);
    return end.difference(start).inDays + 1;
  }

  Future<void> _pickRange() async {
    final t = _today();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: t.subtract(const Duration(days: 365)),
      lastDate: t.add(const Duration(days: 365)),
      initialDateRange: _range,
    );
    if (picked == null) return;
    setState(() {
      _range = DateTimeRange(start: _day(picked.start), end: _day(picked.end));
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _range;
    final days = r == null ? 0 : _daysInRange(r);
    final perDay = (days <= 0)
        ? 0
        : (widget.selectedCount / days).toStringAsFixed(1);

    final rangeLabel = r == null
        ? 'No range selected'
        : '${DateFormat('d MMM yyyy').format(r.start)} → ${DateFormat('d MMM yyyy').format(r.end)}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.black.withValues(alpha: 0.04),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Post grazing residual',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    SizedBox(
                      width: 120,
                      child: TextField(
                        controller: _ctrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          isDense: true,
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 10,
                          ),
                        ),
                        onChanged: (s) {
                          final v = int.tryParse(s.trim());
                          if (v != null) widget.onResidualChanged(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Flexible(
                      child: Text(
                        'kgDM/ha',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'When',
                  style: TextStyle(fontSize: 12, color: Colors.black54),
                ),
                const SizedBox(height: 6),
                Text(
                  rangeLabel,
                  style: const TextStyle(
                    fontSize: 11,
                    color: Colors.black54,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _pickRange,
                        icon: const Icon(Icons.date_range, size: 18),
                        label: const Text('Pick range'),
                      ),
                    ),
                    if (days > 0) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Scheduling ${widget.selectedCount} across $days days (~$perDay/day)',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black87,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                if (widget.selectedCount > 0 && widget.selectedAreaHa > 0) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Selected area: ${widget.selectedAreaHa.toStringAsFixed(1)} ha',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 44,
                  child: OutlinedButton(
                    onPressed: widget.onUndo,
                    child: const Text(
                      'Undo grazing',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 48,
                  child: ElevatedButton(
                    onPressed: (widget.onPreview == null || _range == null)
                        ? null
                        : () => widget.onPreview!(_range!),
                    child: Text(
                      widget.selectedAreaHa > 0
                          ? 'Preview (${widget.selectedCount}) · ${widget.selectedAreaHa.toStringAsFixed(1)} ha'
                          : 'Preview (${widget.selectedCount})',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 2,
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
