import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';
import 'round_screen.dart';
import 'settings_screen.dart';
import 'paddock_history_screen.dart';
import 'avg_cover_history_screen.dart';
import 'grazing_schedule_preview_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
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

class _RowData {
  final Paddock paddock;
  final int? lastCover; // last recorded cover measurement
  final DateTime? lastAt; // when that measurement happened
  final int predicted; // predicted now (from latest anchor)
  final bool grazed; // last event is grazing
  final bool hasRecentNote; // note added today (used for home icon)

  _RowData({
    required this.paddock,
    required this.lastCover,
    required this.lastAt,
    required this.predicted,
    required this.grazed,
    required this.hasRecentNote,
  });
}

class _HomeScreenState extends State<HomeScreen> {
  final storage = Storage();
  final uuid = const Uuid();

  bool loaded = false;
  List<Paddock> paddocks = [];

  // Sorting: click header toggles asc/desc only
  String sortCol = Storage.colPaddock;
  bool sortAsc = true;

  // Layout
  static const double leftColW = 120;
  static const double cowColW = 28;

  static const String colRecorded = 'recorded';
  static const String colPredicted = 'predictedNow';

  // Selection mode for grazing
  bool selectionMode = false;
  final Set<String> selectedPaddockIds = {};
  int residual = 1600;

  final Set<String> _selectedSummaryNoteIds = {};

  int _tabIndex = 0;

  Future<List<_RowData>>? _rowsFuture;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    paddocks = await storage.loadPaddocks();
    paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    loaded = true;
    _rowsFuture = _buildRows();
    if (mounted) setState(() {});
  }

  Future<void> _refreshHome() async {
    await _load();
    if (mounted) setState(() {});
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

    final farmGrowth = await storage.effectiveFarmGrowthKgDmPerHaPerDay();

    // Batch-load once to avoid per-paddock SharedPreferences reads.
    final msAll = await storage.loadAllMeasurements();
    final gsAll = await storage.loadAllGrazings();
    final notesAll = await storage.loadAllNotes();

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

      // ✅ note icon: show if note added today
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

      // ✅ Cropped paddocks: predicted cover should be 0 so sorting doesn't float them up at 2500
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

      out.add(
        _RowData(
          paddock: p,
          lastCover: recordedCover,
          lastAt: recordedAt,
          predicted: predicted,
          grazed: grazed,
          hasRecentNote: hasRecentNote,
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
  }

  void _toggleSelected(String paddockId) {
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
    setState(() {
      selectionMode = false;
      selectedPaddockIds.clear();
    });
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

    setState(() {
      selectionMode = false;
      selectedPaddockIds.clear();
    });

    await _refreshHome();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(selectionMode ? 'Select paddocks' : 'Pasture Walk'),
        leading: selectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: _cancelSelection,
              )
            : null,
        actions: [
          if (!selectionMode)
            IconButton(
              icon: const Icon(Icons.settings),
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SettingsScreen()),
                );
                await _refreshHome();
              },
            ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : FutureBuilder<List<_RowData>>(
              future: _rowsFuture,
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final rows = [...(snap.data ?? <_RowData>[])];
                rows.sort((a, b) => _compare(a, b));

                return Column(
                  children: [
                    if (!selectionMode) _tabs(),
                    if (!selectionMode)
                      Expanded(
                        child: _tabIndex == 0
                            ? _summaryTab(rows)
                            : _paddocksTab(rows),
                      ),
                    if (selectionMode) Expanded(child: _paddocksTab(rows)),
                  ],
                );
              },
            ),
    );
  }

  Widget _tabs() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SegmentedButton<int>(
        segments: const [
          ButtonSegment(value: 0, label: Text('Summary')),
          ButtonSegment(value: 1, label: Text('Paddocks')),
        ],
        selected: {_tabIndex},
        onSelectionChanged: (s) => setState(() => _tabIndex = s.first),
      ),
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
          child: ElevatedButton(
            onPressed: () async {
              await Navigator.of(
                context,
              ).push(MaterialPageRoute(builder: (_) => const RoundScreen()));
              await _refreshHome();
            },
            child: const Text(
              'Start / Resume Recording',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _summaryCards(avgCover: avgCover),
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
      future: Future.wait([
        storage.loadCowCount(),
        storage.loadAreaGrazedPerDayHa(),
        storage.loadPaddocks(),
        storage.loadAllGrazings(),
      ]),
      builder: (context, snap) {
        final data = snap.data;

        final cowCount = (data != null && data.isNotEmpty)
            ? (data[0] as int)
            : 0;
        final targetAreaPerDay = (data != null && data.length > 1)
            ? (data[1] as double)
            : 0.0;
        final paddocks = (data != null && data.length > 2)
            ? (data[2] as List<Paddock>)
            : <Paddock>[];
        final grazings = (data != null && data.length > 3)
            ? (data[3] as List<Grazing>)
            : <Grazing>[];

        final pById = {for (final p in paddocks) p.id: p};

        final now = DateTime.now();
        final start = DateTime(
          now.year,
          now.month,
          now.day,
        ).subtract(const Duration(days: 6));

        final grazingsWeek = grazings.where((g) {
          final d = DateTime(g.at.year, g.at.month, g.at.day);
          return !d.isBefore(start) && !d.isAfter(now);
        }).toList();

        final harvestedWeek = grazingsWeek.fold<int>(
          0,
          (sum, g) => sum + g.harvestedKgDm,
        );

        final kgDmCowDay = (cowCount <= 0)
            ? null
            : harvestedWeek / cowCount / 7.0;

        double areaWeek = 0.0;
        for (final g in grazingsWeek) {
          final p = pById[g.paddockId];
          if (p == null) continue;
          if (!p.includeInRotation) continue;
          areaWeek += p.areaHa;
        }
        final actualAreaPerDay = areaWeek / 7.0;

        final acc = (targetAreaPerDay <= 0)
            ? null
            : (actualAreaPerDay / targetAreaPerDay);
        final accPct = acc == null ? null : (acc * 100).clamp(0.0, 999.0);

        return Row(
          children: [
            Expanded(
              child: InkWell(
                onTap: _editCowCount,
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
                          'kgDM/cow/day',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          kgDmCowDay == null
                              ? '—'
                              : kgDmCowDay.toStringAsFixed(1),
                          style: const TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          cowCount <= 0
                              ? 'Tap to set cow numbers'
                              : 'Using $cowCount cows (last 7d)',
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
                          'Grazing accuracy',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.black54,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        _AccuracyBar(
                          value: acc ?? 0.0,
                          enabled: targetAreaPerDay > 0,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          targetAreaPerDay <= 0
                              ? 'Tap to set target'
                              : '${(accPct ?? 0).toStringAsFixed(0)}%  (actual ${actualAreaPerDay.toStringAsFixed(2)} ha/day vs target ${targetAreaPerDay.toStringAsFixed(2)})',
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
        );
      },
    );
  }

  Future<void> _editCowCount() async {
    final start = await storage.loadCowCount();
    final ctrl = TextEditingController(text: start <= 0 ? '' : '$start');
    if (!mounted) return;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cow numbers'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Number of cows',
            border: OutlineInputBorder(),
          ),
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
    if (t.isEmpty) {
      await storage.saveCowCount(0);
      await _refreshHome();
      return;
    }

    final v = int.tryParse(t);
    if (v == null) return;
    await storage.saveCowCount(v);
    await _refreshHome();
  }

  Widget _summaryNotes() {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
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

  Widget _summaryCards({required int avgCover}) {
    return FutureBuilder<List<dynamic>>(
      future: Future.wait([
        storage.effectiveFarmGrowthKgDmPerHaPerDay(),
        storage.loadAreaGrazedPerDayHa(),
        storage.loadCoverTrendTimescale(),
        storage.loadFeedWedgePreGrazingTarget(),
        storage.loadFeedWedgePostGrazingResidualTarget(),
        storage.loadPaddocks(),
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
        final preTarget = (data != null && data.length > 3)
            ? (data[3] as int)
            : 2800;
        final postResidual = (data != null && data.length > 4)
            ? (data[4] as int)
            : 1500;
        final allPaddocks = (data != null && data.length > 5)
            ? (data[5] as List<Paddock>)
            : <Paddock>[];

        final includedArea = allPaddocks
            .where((p) => p.includeInRotation)
            .fold<double>(0.0, (sum, p) => sum + p.areaHa);

        final roundLengthDays = (areaPerDay > 0 && includedArea > 0)
            ? (includedArea / areaPerDay)
            : null;

        final requiredGrowth = (roundLengthDays == null || roundLengthDays <= 0)
            ? null
            : (preTarget - postResidual) / roundLengthDays;

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

        final reqGrowthText = requiredGrowth == null
            ? '—'
            : requiredGrowth.toStringAsFixed(1);

        return Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const AvgCoverHistoryScreen(),
                        ),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Avg cover',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.black54,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              '$avgCover',
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 2),
                            const Text(
                              'kgDM/ha',
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
                              '$timescaleUnit  (req $reqGrowthText)',
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
    final start = await storage.loadAreaGrazedPerDayHa();
    final ctrl = TextEditingController(
      text: start <= 0 ? '' : start.toStringAsFixed(2),
    );
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Area grazed per day'),
        content: TextField(
          controller: ctrl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'ha/day',
            border: OutlineInputBorder(),
          ),
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
    if (t.isEmpty) {
      await storage.saveAreaGrazedPerDayHa(0.0);
      await _refreshHome();
      return;
    }
    final v = double.tryParse(t);
    if (v == null) return;
    await storage.saveAreaGrazedPerDayHa(v);
    await _refreshHome();
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

  Widget _paddocksTab(List<_RowData> rows) {
    return Column(
      children: [
        if (selectionMode)
          _GrazingBar(
            residual: residual,
            selectedCount: selectedPaddockIds.length,
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
                      setState(() {
                        selectionMode = false;
                        selectedPaddockIds.clear();
                      });
                      await _refreshHome();
                    }
                  },
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
      child: Container(
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

                    // note symbol
                    if (r.hasRecentNote)
                      const Icon(Icons.sticky_note_2_outlined, size: 16),

                    if (isExcluded == false &&
                        r.grazed == false &&
                        r.hasRecentNote == false)
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
    );
  }
}

class _WedgePaddock {
  final String label;
  final int cover;
  const _WedgePaddock({required this.label, required this.cover});
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

  Future<void> _editTargets(BuildContext context) async {
    final pre0 = await storage.loadFeedWedgePreGrazingTarget();
    final post0 = await storage.loadFeedWedgePostGrazingResidualTarget();
    if (!context.mounted) return;

    final preCtrl = TextEditingController(text: pre0.toString());
    final postCtrl = TextEditingController(text: post0.toString());

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Feed wedge targets'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: preCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Pre-grazing cover target',
                helperText: 'kgDM/ha',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: postCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Post-grazing residual target',
                helperText: 'kgDM/ha',
                border: OutlineInputBorder(),
              ),
            ),
          ],
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

    final pre = int.tryParse(preCtrl.text.trim());
    final post = int.tryParse(postCtrl.text.trim());
    if (pre == null || post == null) return;

    await storage.saveFeedWedgePreGrazingTarget(pre);
    await storage.saveFeedWedgePostGrazingResidualTarget(post);
    await onChanged();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<int>>(
      future: Future.wait([
        storage.loadFeedWedgePreGrazingTarget(),
        storage.loadFeedWedgePostGrazingResidualTarget(),
      ]),
      builder: (context, snap) {
        final pre = (snap.data == null || snap.data!.isEmpty)
            ? 2800
            : snap.data![0];
        final post = (snap.data == null || snap.data!.length < 2)
            ? 1500
            : snap.data![1];

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
                      child: Text('Targets: $pre → $post'),
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
  final ValueChanged<int> onResidualChanged;
  final VoidCallback? onUndo;
  final ValueChanged<DateTimeRange>? onPreview;

  const _GrazingBar({
    required this.residual,
    required this.selectedCount,
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
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
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
                    const Text(
                      'kgDM/ha',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
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
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    SizedBox(
                      height: 40,
                      child: OutlinedButton.icon(
                        onPressed: _pickRange,
                        icon: const Icon(Icons.date_range, size: 18),
                        label: const Text('Pick range'),
                      ),
                    ),
                    Text(
                      days <= 0
                          ? ''
                          : 'Scheduling ${widget.selectedCount} across $days days (~$perDay/day)',
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black87,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            children: [
              SizedBox(
                height: 44,
                child: OutlinedButton(
                  onPressed: widget.onUndo,
                  child: const Text('Undo grazing'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 44,
                child: ElevatedButton(
                  onPressed: (widget.onPreview == null || _range == null)
                      ? null
                      : () => widget.onPreview!(_range!),
                  child: Text('Preview (${widget.selectedCount})'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
