import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';

/// A paddock shown in the planner's bottom palette.
class PlannerPaddock {
  final String id;
  final String name;
  final double areaHa;
  final int predictedCover;
  final DateTime? lastAt;

  PlannerPaddock({
    required this.id,
    required this.name,
    required this.areaHa,
    required this.predictedCover,
    this.lastAt,
  });
}

/// Drag-and-drop grazing planner.
///
/// Rows are days, columns are grazing breaks grouped by herd. Paddocks are
/// dragged from the bottom palette onto a cell to schedule a grazing.
class GrazingPlanner extends StatefulWidget {
  final Storage storage;

  /// Paddocks for the palette (already sorted by the caller if desired).
  final List<PlannerPaddock> palettePaddocks;

  /// Called after any change that should refresh the rest of the app.
  final Future<void> Function()? onChanged;

  const GrazingPlanner({
    super.key,
    required this.storage,
    required this.palettePaddocks,
    this.onChanged,
  });

  @override
  State<GrazingPlanner> createState() => _GrazingPlannerState();
}

class _BreakCol {
  final Herd herd;
  final GrazingSlot slot;
  _BreakCol({required this.herd, required this.slot});
}

/// In-progress block edit: ONE paddock placed across a set of cells
/// (break column, day). Entered by long-pressing a paddock box. Drag to move,
/// tap an empty neighbour to add a cell, tap a covered cell to remove it.
class _BlockEdit {
  final String groupId;
  final String paddockId;
  final Set<String> originalCells; // cells when edit started
  final Set<String> cells; // current cells

  _BlockEdit({
    required this.groupId,
    required this.paddockId,
    required this.originalCells,
    required this.cells,
  });

  static String key(int col, int day) => '$col:$day';

  bool covers(int c, int d) => cells.contains(key(c, d));
}

/// Pointer tracking for moving a block while in edit mode.
class _MoveDrag {
  final Offset startGlobal;
  final Set<String> startCells;
  _MoveDrag({required this.startGlobal, required this.startCells});
}

class _GrazingPlannerState extends State<GrazingPlanner> {
  final Uuid _uuid = const Uuid();

  static const double _rowH = 66;
  static const double _dateW = 58;
  static const double _herdH = 22;
  static const double _breakH = 40;
  static const int _defaultDays = 31;
  static const int _loadChunk = 30;
  static const int _defaultBack = 15;

  /// Break-column width, derived from the viewport and [_visibleCols].
  double _breakW = 118;
  int _visibleCols = 4;

  List<Grazing> _grazings = [];
  List<Herd> _herds = [];
  List<GrazingSlot> _slots = [];
  Map<String, Paddock> _paddockById = {};
  List<_BreakCol> _cols = [];
  bool _loading = true;

  late DateTime _startDay;
  int _dayCount = _defaultDays;

  double _offX = 0;
  double _offY = 0;
  final ValueNotifier<Offset> _pan = ValueNotifier(Offset.zero);
  // Precomputed per build (indexed by break column / day index).
  Map<String, List<Grazing>> _cellAllocs = {};
  Map<int, Map<String, List<double>>> _dayShares = {};
  Map<int, List<Grazing>> _unassignedByDay = {};
  _BlockEdit? _blockEdit;
  _MoveDrag? _moveDrag;
  Offset? _dragGlobal;
  int _moveCd = 0;
  int _moveDd = 0;
  final GlobalKey _gridStackKey = GlobalKey();
  bool _didInitialJump = false;
  Map<String, int> _paddockIndex = {};
  int _pre = 2800;
  int _post = 1500;

  static const List<Color> _paddockColors = [
    Color(0xFF1E88E5),
    Color(0xFFE53935),
    Color(0xFF43A047),
    Color(0xFFFB8C00),
    Color(0xFF8E24AA),
    Color(0xFF00897B),
    Color(0xFF6D4C41),
    Color(0xFF3949AB),
    Color(0xFFC0CA33),
    Color(0xFFD81B60),
    Color(0xFF00ACC1),
    Color(0xFFF4511E),
    Color(0xFF7CB342),
    Color(0xFF5E35B1),
  ];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _startDay = DateTime(now.year, now.month, now.day - _defaultBack);
    _load();
  }

  @override
  void dispose() {
    _pan.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final res = await Future.wait([
      widget.storage.loadAllGrazings(),
      widget.storage.loadHerds(),
      widget.storage.loadGrazingSlots(),
      widget.storage.loadPaddocks(),
      widget.storage.loadFeedWedgePreGrazingOverride(),
      widget.storage.loadFeedWedgePostGrazingResidualOverride(),
      widget.storage.loadCalendarVisibleCols(),
    ]);
    if (!mounted) return;
    setState(() {
      _grazings = res[0] as List<Grazing>;
      _herds = res[1] as List<Herd>;
      _slots = res[2] as List<GrazingSlot>;
      _paddockById = {for (final p in res[3] as List<Paddock>) p.id: p};
      _pre = (res[4] as int?) ?? 2800;
      _post = (res[5] as int?) ?? 1500;
      final savedCols = res[6] as int?;
      if (savedCols != null) _visibleCols = savedCols.clamp(1, 12);
      _paddockIndex = _buildPaddockIndex();
      _rebuildCols();
      _loading = false;
    });
    if (!_didInitialJump && _cols.isNotEmpty) {
      _didInitialJump = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToday();
      });
    }
  }

  void _rebuildCols() {
    _cols = [
      for (final h in _herds)
        for (final s in _slots.where((s) => s.herdId == h.id))
          _BreakCol(herd: h, slot: s),
    ];
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  // Build each day from calendar parts (DST-safe) rather than adding 24h.
  DateTime _dayAt(int i) =>
      DateTime(_startDay.year, _startDay.month, _startDay.day + i);

  int _dayIndexFor(DateTime day) {
    final a = DateTime.utc(_startDay.year, _startDay.month, _startDay.day);
    final b = DateTime.utc(day.year, day.month, day.day);
    return b.difference(a).inDays;
  }

  String _paddockName(String id) =>
      _paddockById[id]?.name ?? '[${id.substring(0, 6)}]';

  double _areaOf(Grazing g) =>
      g.areaHa ?? _paddockById[g.paddockId]?.areaHa ?? 0.0;

  /// Grazings for this break whose run covers [day] (includes continuations of
  /// multi-day grazings that started on an earlier day).
  List<Grazing> _allocations(String slotId, DateTime day) => _grazings
      .where((g) {
        if (g.slotId != slotId) return false;
        final start = DateTime(g.at.year, g.at.month, g.at.day);
        final dur = g.durationDays < 1 ? 1 : g.durationDays;
        // Calendar-add (DST safe): a run of N days covers start..start+N-1.
        final end = DateTime(start.year, start.month, start.day + dur);
        return !day.isBefore(start) && day.isBefore(end);
      })
      .toList();

  /// All area/harvest bucketing for the day totals happens in [_precompute].

  /// Daily target = the sum of the herds' daily area requirements.
  double get _dayTarget =>
      _herds.fold<double>(0.0, (a, h) => a + h.areaGrazedPerDayHa);

  Color _colorForHerd(String herdId) {
    final hue = (herdId.hashCode % 360).abs().toDouble();
    return HSLColor.fromAHSL(1, hue, 0.5, 0.45).toColor();
  }

  Map<String, int> _buildPaddockIndex() {
    final sorted = _paddockById.values.toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    return {for (var i = 0; i < sorted.length; i++) sorted[i].id: i};
  }

  Color _colorForPaddock(String paddockId) {
    final i = _paddockIndex[paddockId] ?? paddockId.hashCode.abs();
    return _paddockColors[i % _paddockColors.length];
  }

  String _herdName(String herdId) =>
      _herds.firstWhere((h) => h.id == herdId, orElse: () {
        return Herd(id: herdId, name: '?', cowCount: 0, areaGrazedPerDayHa: 0);
      }).name;

  Future<void> _place(
    GrazingSlot slot,
    DateTime day,
    PlannerPaddock p,
  ) async {
    // The paddock's area drives the allocation. If it exceeds the slot's
    // target, the daily total simply reflects the overage.
    final area = p.areaHa;
    final at = DateTime(day.year, day.month, day.day, 9, 0);
    final pre = p.predictedCover > 0 ? p.predictedCover : 2000;
    const res = 1600;
    final harvest = ((pre - res) * area).round().clamp(0, 999999999);
    await widget.storage.appendGrazing(
      Grazing(
        id: _uuid.v4(),
        paddockId: p.id,
        at: at,
        enteredAt: DateTime.now(),
        preCover: pre,
        residual: res,
        harvestedKgDm: harvest,
        durationDays: 1,
        slotId: slot.id,
        areaHa: area,
      ),
    );
    await _load();
    widget.onChanged?.call();
    // Leave the newly dropped paddock selected so it can be resized straight away.
    final colIndex = _cols.indexWhere((c) => c.slot.id == slot.id);
    if (colIndex >= 0) {
      await _enterEditMode(_cols[colIndex], colIndex, _dayIndexFor(at), p.id);
    }
  }

  Future<void> _deleteAllocation(Grazing g) async {
    await widget.storage.deleteGrazingById(g.id);
    await _load();
    widget.onChanged?.call();
  }

  // -----------------------------
  // DRAG TO MOVE / RESIZE
  // -----------------------------

  Grazing _copyWithGroup(Grazing g, String? groupId) => Grazing(
    id: g.id,
    paddockId: g.paddockId,
    at: g.at,
    enteredAt: g.enteredAt,
    preCover: g.preCover,
    residual: g.residual,
    harvestedKgDm: g.harvestedKgDm,
    durationDays: g.durationDays,
    slotId: g.slotId,
    areaHa: g.areaHa,
    groupId: groupId,
  );

  Future<void> _enterEditMode(
    _BreakCol c,
    int colIndex,
    int dayIndex,
    String paddockId,
  ) async {
    // Persist any in-progress edit before switching to a new block.
    if (_blockEdit != null) {
      await _persistEdit();
      if (!mounted) return;
      setState(() => _blockEdit = null);
    }
    final day = _dayAt(dayIndex);
    // Any covered cell of the run can be used (not just the start day).
    final covering = _allocations(c.slot.id, day)
        .where((g) => g.paddockId == paddockId)
        .toList();
    if (covering.isEmpty) return;

    final existingGroup = covering
        .map((g) => g.groupId)
        .firstWhere((x) => x != null, orElse: () => null);
    final groupId = existingGroup ?? _uuid.v4();
    final group = existingGroup == null
        ? covering
        : _grazings
              .where(
                (g) =>
                    g.groupId == existingGroup && g.paddockId == paddockId,
              )
              .toList();
    for (final g in group) {
      if (g.groupId != groupId) {
        await widget.storage.updateGrazing(_copyWithGroup(g, groupId));
      }
    }

    final cells = <String>{};
    for (final g in group) {
      final ci = _cols.indexWhere((col) => col.slot.id == g.slotId);
      if (ci < 0) continue;
      final d0 = _dayIndexFor(g.at);
      final dur = g.durationDays < 1 ? 1 : g.durationDays;
      for (var k = 0; k < dur; k++) {
        cells.add(_BlockEdit.key(ci, d0 + k));
      }
    }
    if (cells.isEmpty) cells.add(_BlockEdit.key(colIndex, dayIndex));

    setState(() {
      _blockEdit = _BlockEdit(
        groupId: groupId,
        paddockId: paddockId,
        originalCells: {...cells},
        cells: cells,
      );
    });
    await _load();
  }

  bool _isFrontier(_BlockEdit e, int col, int day) {
    if (e.covers(col, day)) return false;
    const dirs = [
      [-1, 0],
      [1, 0],
      [0, -1],
      [0, 1],
    ];
    for (final d in dirs) {
      if (e.covers(col + d[0], day + d[1])) return true;
    }
    return false;
  }

  Future<void> _addCell(int col, int day) async {
    final e = _blockEdit;
    if (e == null) return;
    if (col < 0 || col >= _cols.length || day < 0 || day >= _dayCount) return;
    setState(() => e.cells.add(_BlockEdit.key(col, day)));
    await _persistEdit();
  }

  Future<void> _removeCell(int col, int day) async {
    final e = _blockEdit;
    if (e == null) return;
    // Always keep at least one box; deleting a grazing is done from the
    // details sheet or the list view.
    if (e.cells.length <= 1) return;
    if (!e.cells.remove(_BlockEdit.key(col, day))) return;
    setState(() {});
    await _persistEdit();
  }

  /// Commits the current edit block to storage without leaving edit mode.
  Future<void> _persistEdit() async {
    final e = _blockEdit;
    if (e == null) return;
    _moveDrag = null;
    _dragGlobal = null;
    await _commitEdit(e);
    await _load();
    widget.onChanged?.call();
  }

  void _startMove(Offset global) {
    final e = _blockEdit;
    if (e == null) return;
    _moveDrag = _MoveDrag(startGlobal: global, startCells: {...e.cells});
    _dragGlobal = global;
    _moveCd = 0;
    _moveDd = 0;
    setState(() {});
  }

  /// Live drag: the block does not move until the finger is released.
  void _updateMove(Offset global) {
    final e = _blockEdit;
    final m = _moveDrag;
    if (e == null || m == null) return;
    _dragGlobal = global;
    final dx = global.dx - m.startGlobal.dx;
    final dy = global.dy - m.startGlobal.dy;
    var cDelta = (dx / _breakW).round();
    var dDelta = (dy / _rowH).round();

    var minC = 1 << 30, maxC = -(1 << 30);
    var minD = 1 << 30, maxD = -(1 << 30);
    for (final key in m.startCells) {
      final p = key.split(':');
      final c = int.parse(p[0]);
      final d = int.parse(p[1]);
      if (c < minC) minC = c;
      if (c > maxC) maxC = c;
      if (d < minD) minD = d;
      if (d > maxD) maxD = d;
    }
    if (minC + cDelta < 0) cDelta = -minC;
    if (maxC + cDelta > _cols.length - 1) cDelta = _cols.length - 1 - maxC;
    if (minD + dDelta < 0) dDelta = -minD;
    if (maxD + dDelta > _dayCount - 1) dDelta = _dayCount - 1 - maxD;

    setState(() {
      _moveCd = cDelta;
      _moveDd = dDelta;
    });
  }

  /// Land the block where the drag currently points, then persist.
  Future<void> _endMove() async {
    final e = _blockEdit;
    final m = _moveDrag;
    if (e == null || m == null) return;
    final next = <String>{};
    for (final key in m.startCells) {
      final p = key.split(':');
      next.add(
        _BlockEdit.key(
          int.parse(p[0]) + _moveCd,
          int.parse(p[1]) + _moveDd,
        ),
      );
    }
    _moveDrag = null;
    _dragGlobal = null;
    _moveCd = 0;
    _moveDd = 0;
    setState(() => e.cells..clear()..addAll(next));
    await _persistEdit();
  }

  Future<void> _exitEditMode() async {
    final e = _blockEdit;
    _moveDrag = null;
    _dragGlobal = null;
    if (e == null) return;
    setState(() => _blockEdit = null);
    await _commitEdit(e);
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _commitEdit(_BlockEdit e) async {
    // Never delete the grazing from edit mode: keep at least one cell.
    if (e.cells.isEmpty) return;

    // Region touched by this edit (old + new cells).
    final affected = {...e.originalCells, ...e.cells};
    final colIdxs = <int>{};
    final dayIdxs = <int>{};
    for (final k in affected) {
      final p = k.split(':');
      colIdxs.add(int.parse(p[0]));
      dayIdxs.add(int.parse(p[1]));
    }
    if (colIdxs.isEmpty) return;
    final slotIds = {for (final ci in colIdxs) _cols[ci].slot.id};
    final minDay = dayIdxs.reduce((a, b) => a < b ? a : b);
    final maxDay = dayIdxs.reduce((a, b) => a > b ? a : b);

    // Remove every record of this paddock overlapping that region, and keep
    // one as the field template. This prevents stale/duplicate records.
    Grazing? sample;
    final toDelete = <Grazing>[];
    for (final g in _grazings) {
      if (g.paddockId != e.paddockId) continue;
      if (!slotIds.contains(g.slotId)) continue;
      final d0 = _dayIndexFor(g.at);
      final dur = g.durationDays < 1 ? 1 : g.durationDays;
      if (d0 <= maxDay && d0 + dur - 1 >= minDay) {
        sample ??= g;
        toDelete.add(g);
      }
    }
    for (final g in toDelete) {
      await widget.storage.deleteGrazingById(g.id);
    }

    // Rebuild from the cell set (contiguous runs per column).
    final byCol = <int, List<int>>{};
    for (final key in e.cells) {
      final p = key.split(':');
      (byCol[int.parse(p[0])] ??= []).add(int.parse(p[1]));
    }

    final pid = e.paddockId;
    final area = sample?.areaHa ?? _paddockById[pid]?.areaHa ?? 1.0;
    final pre = sample?.preCover ?? 2000;
    final res = sample?.residual ?? 1600;

    for (final entry in byCol.entries) {
      final days = entry.value..sort();
      final slotId = _cols[entry.key].slot.id;
      var start = days.first;
      var prev = days.first;
      for (var i = 1; i <= days.length; i++) {
        final d = i < days.length ? days[i] : null;
        if (d == null || d != prev + 1) {
          final startDay = _dayAt(start);
          final dur = prev - start + 1;
          final at = DateTime(
            startDay.year,
            startDay.month,
            startDay.day,
            9,
            0,
          );
          final harvest = ((pre - res) * area).round().clamp(0, 999999999);
          await widget.storage.appendGrazing(
            Grazing(
              id: _uuid.v4(),
              paddockId: pid,
              at: at,
              enteredAt: sample?.enteredAt ?? DateTime.now(),
              preCover: pre,
              residual: res,
              harvestedKgDm: harvest,
              durationDays: dur,
              slotId: slotId,
              areaHa: area,
              groupId: e.groupId,
            ),
          );
          if (d != null) start = d;
        }
        if (d != null) prev = d;
      }
    }
  }

  Future<void> _editAllocation(Grazing g) async {
    final preCtrl = TextEditingController(text: '${g.preCover}');
    final resCtrl = TextEditingController(text: '${g.residual}');
    final areaCtrl = TextEditingController(
      text: _areaOf(g).toStringAsFixed(2),
    );
    final daysCtrl = TextEditingController(text: '${g.durationDays}');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_paddockName(g.paddockId)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: preCtrl,
                decoration: const InputDecoration(labelText: 'Pre (kgDM/ha)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: resCtrl,
                decoration:
                    const InputDecoration(labelText: 'Post (kgDM/ha)'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: areaCtrl,
                decoration: const InputDecoration(labelText: 'Area (ha)'),
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
              ),
              TextField(
                controller: daysCtrl,
                decoration: const InputDecoration(labelText: 'Days'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final pre = int.tryParse(preCtrl.text.trim()) ?? g.preCover;
    final res = int.tryParse(resCtrl.text.trim()) ?? g.residual;
    final area = double.tryParse(areaCtrl.text.trim()) ?? _areaOf(g);
    final days = (int.tryParse(daysCtrl.text.trim()) ?? g.durationDays)
        .clamp(1, 365);
    final harvest = ((pre - res) * area).round().clamp(0, 999999999);
    await widget.storage.updateGrazing(
      Grazing(
        id: g.id,
        paddockId: g.paddockId,
        at: g.at,
        enteredAt: g.enteredAt,
        preCover: pre,
        residual: res,
        harvestedKgDm: harvest,
        durationDays: days,
        slotId: g.slotId,
        areaHa: area,
      ),
    );
    await _load();
    widget.onChanged?.call();
  }

  Future<void> _showDetails(
    GrazingSlot slot,
    DateTime day, {
    String? paddockId,
  }) async {
    final allocs = _allocations(slot.id, day)
        .where((g) => paddockId == null || g.paddockId == paddockId)
        .toList();
    if (allocs.isEmpty) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                '${_herdName(slot.herdId)} · ${slot.label} · '
                '${DateFormat('EEE d MMM').format(day)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 16,
                ),
              ),
            ),
            const Divider(height: 1),
            for (final g in allocs)
              ListTile(
                title: Text(
                  '${_paddockName(g.paddockId)} · '
                  '${_areaOf(g).toStringAsFixed(2)} ha',
                ),
                subtitle: Text(
                  'Pre ${g.preCover} · Post ${g.residual} · '
                  '${g.harvestedKgDm} kgDM · ${g.durationDays}d',
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await _editAllocation(g);
                },
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove',
                  onPressed: () async {
                    Navigator.pop(ctx);
                    await _deleteAllocation(g);
                  },
                ),
              ),
            TextButton.icon(
              onPressed: () async {
                Navigator.pop(ctx);
                for (final g in allocs) {
                  await widget.storage.deleteGrazingById(g.id);
                }
                await _load();
                widget.onChanged?.call();
              },
              icon: const Icon(Icons.delete_sweep_outlined),
              label: Text(
                paddockId == null
                    ? 'Delete all for this break'
                    : 'Delete this paddock',
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_cols.isEmpty) {
      return _setupHint();
    }
    return Column(
      children: [
        _toolbar(),
        Expanded(
          child: Stack(
            key: _gridStackKey,
            children: [
              _grid(),
              if (_blockEdit != null && _dragGlobal != null)
                _dragFeedback(),
            ],
          ),
        ),
        const Divider(height: 1),
        // Keep the palette above the Android navigation bar / gesture area.
        SafeArea(top: false, child: _palette()),
      ],
    );
  }

  Widget _dragFeedback() {
    final box =
        _gridStackKey.currentContext?.findRenderObject() as RenderBox?;
    final g = _dragGlobal;
    if (box == null || g == null) return const SizedBox.shrink();
    final local = box.globalToLocal(g);
    const w = 96.0;
    const h = 56.0;
    return Positioned(
      left: local.dx - w / 2,
      top: local.dy - h / 2,
      width: w,
      height: h,
      child: IgnorePointer(
        child: Opacity(
          opacity: 0.85,
          child: _paddockBox(_blockEdit!.paddockId),
        ),
      ),
    );
  }

  Widget _setupHint() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_note, size: 40, color: Colors.black38),
            const SizedBox(height: 12),
            const Text(
              'No grazing breaks set up yet.',
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'Add herds and breaks in Grazing Plan Setup, then plan here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toolbar() {
    final editing = _blockEdit != null;
    if (editing) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
        child: Row(
          children: [
            const Icon(Icons.touch_app_outlined, size: 18),
            const SizedBox(width: 6),
            const Expanded(
              child: Text(
                'Drag to move · tap greyed boxes to extend · hold for detail',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            FilledButton(
              onPressed: _exitEditMode,
              child: const Text('Done'),
            ),
          ],
        ),
      );
    }
    final end = _dayAt(_dayCount - 1);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Load earlier',
            onPressed: _loadEarlier,
          ),
          Expanded(
            child: Text(
              '${DateFormat('d MMM').format(_startDay)} – '
              '${DateFormat('d MMM').format(end)}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          TextButton(onPressed: _jumpToday, child: const Text('Today')),
          IconButton(
            icon: const Icon(Icons.more_time),
            tooltip: 'Load later',
            onPressed: _loadLater,
          ),
          IconButton(
            icon: const Icon(Icons.zoom_out),
            tooltip: 'More columns',
            onPressed: _visibleCols >= 7
                ? null
                : () => _setVisibleCols(_visibleCols + 1),
          ),
          IconButton(
            icon: const Icon(Icons.zoom_in),
            tooltip: 'Fewer columns',
            onPressed: _visibleCols <= 2
                ? null
                : () => _setVisibleCols(_visibleCols - 1),
          ),
        ],
      ),
    );
  }

  void _setVisibleCols(int v) {
    final next = v.clamp(1, 12);
    if (next == _visibleCols) return;
    setState(() => _visibleCols = next);
    widget.storage.saveCalendarVisibleCols(next);
  }

  void _jumpToday() {
    final now = DateTime.now();
    setState(() {
      _startDay = DateTime(now.year, now.month, now.day - _defaultBack);
      _dayCount = _defaultDays;
      final rows = (_defaultBack - 3).clamp(0, _dayCount);
      _offY = rows * _rowH;
    });
  }

  void _loadEarlier() {
    setState(() {
      _startDay = DateTime(
        _startDay.year,
        _startDay.month,
        _startDay.day - _loadChunk,
      );
      _dayCount += _loadChunk;
      // Keep the viewport over the same dates after prepending.
      _offY += _loadChunk * _rowH;
    });
  }

  void _loadLater() {
    setState(() => _dayCount += _loadChunk);
  }

  /// Buckets grazings by (break column, day index) once per build so cells
  /// don't rescan every grazing, and so per-day totals are cheap.
  void _precompute() {
    final slotCol = <String, int>{};
    for (var i = 0; i < _cols.length; i++) {
      slotCol[_cols[i].slot.id] = i;
    }
    final cellAllocs = <String, List<Grazing>>{};
    final dayShares = <int, Map<String, List<double>>>{};
    final unassigned = <int, List<Grazing>>{};
    for (final g in _grazings) {
      final startIdx = _dayIndexFor(g.at);
      final dur = g.durationDays < 1 ? 1 : g.durationDays;
      final ci = g.slotId == null ? null : slotCol[g.slotId];
      for (var k = 0; k < dur; k++) {
        final di = startIdx + k;
        if (di < 0 || di >= _dayCount) continue;
        if (ci == null) {
          (unassigned[di] ??= []).add(g);
        } else {
          (cellAllocs['$ci:$di'] ??= []).add(g);
          ((dayShares[di] ??= {})[g.paddockId] ??= []).add(_areaOf(g) / dur);
        }
      }
    }
    _cellAllocs = cellAllocs;
    _dayShares = dayShares;
    _unassignedByDay = unassigned;
  }

  double _dayAllocatedAt(int i) {
    final byP = _dayShares[i];
    if (byP == null) return 0;
    var sum = 0.0;
    for (final shares in byP.values) {
      sum += shares.reduce((a, b) => a + b) / shares.length;
    }
    return sum;
  }

  Widget _grid() {
    return LayoutBuilder(
      builder: (ctx, constraints) {
        final headerH = _herdH + _breakH;
        final breakViewportW = constraints.maxWidth - _dateW;
        if (breakViewportW > 0 && _cols.isNotEmpty) {
          final effective = _visibleCols.clamp(1, _cols.length);
          _breakW = (breakViewportW / effective).clamp(60.0, 360.0);
        }
        final breaksW = _cols.length * _breakW;
        final bodyViewportH = constraints.maxHeight - headerH;
        final bodyContentH = _dayCount * _rowH;
        final maxX = (breaksW - breakViewportW).clamp(0.0, double.infinity);
        final maxY = (bodyContentH - bodyViewportH).clamp(0.0, double.infinity);
        _offX = _offX.clamp(0.0, maxX);
        _offY = _offY.clamp(0.0, maxY);
        final target = Offset(_offX, _offY);
        if (_pan.value != target) _pan.value = target;

        _precompute();

        // Content is built once; panning only moves the transforms below.
        final headerContent = SizedBox(
          width: breaksW,
          height: headerH,
          child: Column(
            children: [
              SizedBox(height: _herdH, child: Row(children: _herdHeaderCells())),
              SizedBox(height: _breakH, child: Row(children: _breakHeaderCells())),
            ],
          ),
        );
        final dateContent = SizedBox(
          width: _dateW,
          height: bodyContentH,
          child: Column(
            children: [
              for (var i = 0; i < _dayCount; i++)
                SizedBox(height: _rowH, child: _leftCells(i)),
            ],
          ),
        );
        final bodyContent = SizedBox(
          width: breaksW,
          height: bodyContentH,
          child: Column(
            children: [
              for (var i = 0; i < _dayCount; i++)
                SizedBox(height: _rowH, child: _dayRow(i)),
            ],
          ),
        );

        // Panning updates the notifier only (no rebuild of the content).
        void dragX(DragUpdateDetails d) {
          _offX = (_offX - d.delta.dx).clamp(0.0, maxX);
          _pan.value = Offset(_offX, _offY);
        }

        void dragY(DragUpdateDetails d) {
          _offY = (_offY - d.delta.dy).clamp(0.0, maxY);
          _pan.value = Offset(_offX, _offY);
        }

        void dragBoth(DragUpdateDetails d) {
          _offX = (_offX - d.delta.dx).clamp(0.0, maxX);
          _offY = (_offY - d.delta.dy).clamp(0.0, maxY);
          _pan.value = Offset(_offX, _offY);
        }

        final onBodyDrag = _blockEdit == null ? dragBoth : null;

        return Column(
          children: [
            // Frozen header row (herd names + break labels).
            SizedBox(
              height: headerH,
              child: Row(
                children: [
                  SizedBox(
                    width: _dateW,
                    child: Column(
                      children: [
                        const SizedBox(height: _herdH),
                        SizedBox(
                          height: _breakH,
                          child: GestureDetector(
                            onPanUpdate: dragX,
                            child: const Center(
                              child: Text(
                                'Date',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onPanUpdate: dragX,
                      child: ClipRect(
                        child: ValueListenableBuilder<Offset>(
                          valueListenable: _pan,
                          child: headerContent,
                          builder: (c, o, ch) => Stack(
                            children: [
                              Positioned(left: -o.dx, top: 0, child: ch!),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Body: frozen date column + 2D-panning grid.
            Expanded(
              child: Row(
                children: [
                  SizedBox(
                    width: _dateW,
                    child: GestureDetector(
                      onPanUpdate: dragY,
                      child: ClipRect(
                        child: ValueListenableBuilder<Offset>(
                          valueListenable: _pan,
                          child: dateContent,
                          builder: (c, o, ch) => Stack(
                            children: [
                              Positioned(left: 0, top: -o.dy, child: ch!),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: GestureDetector(
                      onPanUpdate: onBodyDrag,
                      child: ClipRect(
                        child: ValueListenableBuilder<Offset>(
                          valueListenable: _pan,
                          child: bodyContent,
                          builder: (c, o, ch) => Stack(
                            children: [
                              Positioned(left: -o.dx, top: -o.dy, child: ch!),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _herdHeaderCells() {
    final cells = <Widget>[];
    for (final herd in _herds) {
      final count = _cols.where((c) => c.herd.id == herd.id).length;
      if (count == 0) continue;
      cells.add(
        Container(
          width: count * _breakW,
          height: _herdH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
            ),
            color: _colorForHerd(herd.id).withValues(alpha: 0.10),
          ),
          child: Text(
            herd.name,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: _colorForHerd(herd.id),
            ),
          ),
        ),
      );
    }
    return cells;
  }

  List<Widget> _breakHeaderCells() {
    return [
      for (final c in _cols)
        Container(
          width: _breakW,
          height: _breakH,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: Colors.black.withValues(alpha: 0.10)),
              bottom: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
            ),
          ),
          child: Text(
            c.slot.label,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
    ];
  }

  Widget _leftCells(int i) {
    final day = _dayAt(i);
    final isToday = _sameDay(day, DateTime.now());
    final total = _dayAllocatedAt(i);
    final target = _dayTarget;
    final ratio = target > 0 ? total / target : 0.0;
    final dev = target > 0 ? (total - target) / target : 0.0;
    final Color barColor;
    if (target <= 0) {
      barColor = Colors.grey;
    } else if (dev.abs() <= 0.10) {
      barColor = Colors.green;
    } else if (dev.abs() <= 0.30) {
      barColor = Colors.orange;
    } else {
      barColor = Colors.red;
    }
    final underFill = ratio.clamp(0.0, 1.0);
    final overFill = (ratio - 1).clamp(0.0, 1.0);

    final cell = Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
          right: BorderSide(color: Colors.black.withValues(alpha: 0.12)),
        ),
        color: isToday ? Colors.amber.withValues(alpha: 0.10) : null,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Container(color: Colors.black.withValues(alpha: 0.04)),
          Align(
            alignment: Alignment.centerLeft,
            child: FractionallySizedBox(
              widthFactor: underFill,
              heightFactor: 1,
              child: Container(color: barColor.withValues(alpha: 0.38)),
            ),
          ),
          if (overFill > 0)
            Align(
              alignment: Alignment.centerRight,
              child: FractionallySizedBox(
                widthFactor: overFill,
                heightFactor: 1,
                child: Container(color: Colors.red.withValues(alpha: 0.55)),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  DateFormat('EEE').format(day),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: isToday ? Colors.orange.shade900 : Colors.black87,
                  ),
                ),
                Text(
                  DateFormat('d MMM').format(day),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    // When a paddock is selected, the date column is a pan handle.
    return cell;
  }

  Widget _unassignedBar(List<Grazing> grazings) {
    final label = grazings
        .map((g) => _paddockName(g.paddockId))
        .join('  ·  ');
    return Container(
      width: double.infinity,
      color: Colors.blueGrey.withValues(alpha: 0.18),
      alignment: Alignment.centerLeft,
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Text(
        'Unassigned:  $label',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: Colors.blueGrey.shade800,
        ),
      ),
    );
  }

  Widget _dayRow(int i) {
    final unassigned = _unassignedByDay[i] ?? const <Grazing>[];
    return Column(
      children: [
        if (unassigned.isNotEmpty)
          SizedBox(height: 18, child: _unassignedBar(unassigned)),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var ci = 0; ci < _cols.length; ci++) _cell(_cols[ci], ci, i),
            ],
          ),
        ),
      ],
    );
  }

  /// Font sized so the longest paddock name on record fits the box width.
  double get _numFontSize {
    final maxLen = _paddockById.values
        .map((p) => p.name.length)
        .fold<int>(2, (a, b) => a > b ? a : b);
    final byWidth = (_breakW - 8) / (maxLen * 0.62);
    return byWidth.clamp(12.0, 46.0);
  }

  Widget _paddockBox(String id) {
    final color = _colorForPaddock(id);
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.85)),
      ),
      alignment: Alignment.center,
      child: FittedBox(
        fit: BoxFit.scaleDown,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Text(
            _paddockName(id),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: _numFontSize,
              height: 1.0,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ),
    );
  }

  /// 0 = up, 1 = down, 2 = left, 3 = right relative to the edit block.
  BoxDecoration _cellBorder({Color? color}) => BoxDecoration(
    border: Border(
      right: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
      bottom: BorderSide(color: Colors.black.withValues(alpha: 0.08)),
    ),
    color: color,
  );

  Set<String>? _previewSet() {
    final m = _moveDrag;
    if (m == null) return null;
    final out = <String>{};
    for (final key in m.startCells) {
      final p = key.split(':');
      out.add(
        _BlockEdit.key(int.parse(p[0]) + _moveCd, int.parse(p[1]) + _moveDd),
      );
    }
    return out;
  }

  Widget _cell(_BreakCol c, int colIndex, int dayIndex) {
    final day = _dayAt(dayIndex);
    final e = _blockEdit;
    final preview = _previewSet();
    final moving = preview != null;
    final inPreview =
        preview != null && preview.contains(_BlockEdit.key(colIndex, dayIndex));

    // Covered by the edit block: drag to move, tap to remove.
    if (e != null && e.covers(colIndex, dayIndex)) {
      return GestureDetector(
        onTap: () => _removeCell(colIndex, dayIndex),
        onLongPress: () =>
            _showDetails(c.slot, day, paddockId: e.paddockId),
        onPanStart: (d) => _startMove(d.globalPosition),
        onPanUpdate: (d) => _updateMove(d.globalPosition),
        onPanEnd: (_) => _endMove(),
        child: Opacity(
          opacity: moving ? 0.4 : 1.0,
          child: Container(
            width: _breakW,
            padding: const EdgeInsets.all(2),
            decoration: _cellBorder(
              color: Colors.blueGrey.withValues(alpha: 0.08),
            ),
            child: Stack(
              children: [
                Positioned.fill(child: _paddockBox(e.paddockId)),
                Positioned(
                  top: -2,
                  right: -2,
                  child: Icon(
                    Icons.open_with,
                    size: 12,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final baseAllocs = (_cellAllocs['$colIndex:$dayIndex'] ?? const <Grazing>[])
        .where((g) => e == null || g.groupId != e.groupId)
        .toList();

    // Empty neighbour of the block: tap to add it.
    if (e != null &&
        !moving &&
        baseAllocs.isEmpty &&
        _isFrontier(e, colIndex, dayIndex)) {
      return GestureDetector(
        onTap: () => _addCell(colIndex, dayIndex),
        child: Container(
          width: _breakW,
          padding: const EdgeInsets.all(2),
          decoration: _cellBorder(),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.blueGrey.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: Colors.blueGrey.withValues(alpha: 0.35),
              ),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.add,
              color: Colors.blueGrey.withValues(alpha: 0.55),
            ),
          ),
        ),
      );
    }

    return DragTarget<PlannerPaddock>(
      onWillAcceptWithDetails: (_) => true,
      onAcceptWithDetails: (d) => _place(c.slot, day, d.data),
      builder: (ctx, candidate, rejected) {
        final highlight = candidate.isNotEmpty;
        final color = highlight
            ? Colors.green.withValues(alpha: 0.14)
            : (inPreview ? Colors.blue.withValues(alpha: 0.18) : null);
        return GestureDetector(
          onTap: e == null ? null : () => _exitEditMode(),
          child: Container(
            width: _breakW,
            padding: const EdgeInsets.all(2),
            decoration: _cellBorder(color: color),
            child: baseAllocs.isEmpty
                ? const SizedBox.expand()
                : _cellBoxes(c, colIndex, dayIndex, day, baseAllocs),
          ),
        );
      },
    );
  }

  /// Boxes for a cell, each paddock individually tappable / long-press edit.
  Widget _cellBoxes(
    _BreakCol c,
    int colIndex,
    int dayIndex,
    DateTime day,
    List<Grazing> allocs,
  ) {
    final byPaddock = <String, List<Grazing>>{};
    for (final g in allocs) {
      (byPaddock[g.paddockId] ??= []).add(g);
    }
    final ids = byPaddock.keys.toList();

    Widget boxFor(String id) => GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _enterEditMode(c, colIndex, dayIndex, id),
      onLongPress: () => _showDetails(c.slot, day, paddockId: id),
      child: _paddockBox(id),
    );

    if (ids.length == 1) return boxFor(ids.first);
    return Row(
      children: [
        for (final id in ids)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: boxFor(id),
            ),
          ),
      ],
    );
  }

  Widget _palette() {
    final today = DateTime.now();
    final todayStart = DateTime(today.year, today.month, today.day);
    // Exclude paddocks already allocated from today onwards so they don't get
    // double-booked. (Silage / out-of-rotation paddocks are filtered upstream.)
    final busy = <String>{};
    for (final g in _grazings) {
      final d = DateTime(g.at.year, g.at.month, g.at.day);
      if (!d.isBefore(todayStart)) busy.add(g.paddockId);
    }
    final sorted = widget.palettePaddocks
        .where((p) => !busy.contains(p.id))
        .toList()
      ..sort((a, b) => b.predictedCover.compareTo(a.predictedCover));
    return SizedBox(
      height: 116,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 6),
          Expanded(
            child: sorted.isEmpty
                ? const Center(
                    child: Text('All paddocks are already allocated.'),
                  )
                : ListView.separated(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) => _paletteCard(sorted[i]),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _paletteCard(PlannerPaddock p) {
    // Cover as a fraction between post-graze and pre-graze targets.
    final denom = _pre - _post;
    final pct = denom <= 0
        ? 0.0
        : ((p.predictedCover - _post) / denom).clamp(0.0, 1.0);
    final levelColor = pct >= 0.75
        ? Colors.green
        : (pct >= 0.4 ? Colors.amber : Colors.red);

    final card = Container(
      width: 108,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.black.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Align(
            alignment: Alignment.bottomCenter,
            child: FractionallySizedBox(
              widthFactor: 1,
              heightFactor: pct,
              child: Container(color: levelColor.withValues(alpha: 0.35)),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${p.areaHa.toStringAsFixed(2)} ha',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10,
                      color: Colors.black.withValues(alpha: 0.6),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${p.predictedCover} · '
                    '${p.lastAt == null ? '—' : '${DateTime.now().difference(p.lastAt!).inDays}d'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    // Fixed size for the drag feedback so it has a definite size in the overlay.
    final feedback = SizedBox(width: 108, height: 72, child: card);
    return LongPressDraggable<PlannerPaddock>(
      data: p,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.92, child: feedback),
      ),
      childWhenDragging: Opacity(opacity: 0.35, child: card),
      child: card,
    );
  }
}
