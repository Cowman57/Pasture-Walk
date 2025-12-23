import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';
import 'round_screen.dart';
import 'settings_screen.dart';
import 'paddock_history_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
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

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    paddocks = await storage.loadPaddocks();
    paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    loaded = true;
    if (mounted) setState(() {});
  }

  Future<void> _refreshHome() async {
    await _load();
    if (mounted) setState(() {});
  }

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  Future<List<_RowData>> _buildRows() async {
    final now = DateTime.now();

    // 🌱 farm-measured growth rate (should already exclude cropped paddocks in your calcs)
    final farmGrowth = await storage.computeFarmGrowthKgDmPerHaPerDay();

    // per paddock modifier
    final modifiers = await storage.loadGrowthModifiers();

    final out = <_RowData>[];
    for (final p in paddocks) {
      final lastCoverM = await storage.lastMeasurementForPaddock(p.id);
      final anchor = await storage.latestAnchorForPaddock(p.id);
      final grazed = await storage.isCurrentlyGrazed(p.id);

      // ✅ note icon: show if note added today
      final lastNote = await storage.lastNoteForPaddock(p.id);
      final hasRecentNote = lastNote != null && _sameDay(lastNote.at, now);

      final recordedCover = lastCoverM?.cover;
      final recordedAt = lastCoverM?.at;

      int predicted;

      // ✅ Cropped paddocks: predicted cover should be 0 so sorting doesn't float them up at 2500
      if (!p.includeInRotation) {
        predicted = 0;
      } else {
        final baseCover = anchor?.coverKgDmHa ?? 2500;
        final baseAt = anchor?.at;
        final days = baseAt == null ? 0 : now.difference(baseAt).inDays;

        final mod = modifiers[p.id] ?? 1.0;
        final gEff = farmGrowth * mod;

        predicted = clampCover(baseCover + (days * gEff).round());
      }

      out.add(_RowData(
        paddock: p,
        lastCover: recordedCover,
        lastAt: recordedAt,
        predicted: predicted,
        grazed: grazed,
        hasRecentNote: hasRecentNote,
      ));
    }
    return out;
  }

  void _toggleSort(String col) {
    setState(() {
      if (sortCol == col) {
        sortAsc = !sortAsc;
      } else {
        sortCol = col;
        sortAsc = true;
      }
    });
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
        cmp = a.paddock.name.toLowerCase().compareTo(b.paddock.name.toLowerCase());
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

  Future<void> _saveGrazing(List<_RowData> allRows) async {
    if (selectedPaddockIds.isEmpty) return;

    final now = DateTime.now();
    final res = clampCover(residual);

    for (final r in allRows) {
      if (!selectedPaddockIds.contains(r.paddock.id)) continue;

      final pre = r.predicted;
      final harvestedKgDm =
      ((pre - res) * r.paddock.areaHa).round().clamp(0, 999999999);

      final g = Grazing(
        id: uuid.v4(),
        paddockId: r.paddock.id,
        at: now,
        preCover: pre,
        residual: res,
        harvestedKgDm: harvestedKgDm,
      );

      await storage.appendGrazing(g);
    }

    setState(() {
      selectionMode = false;
      selectedPaddockIds.clear();
    });

    await _refreshHome();
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
            ? IconButton(icon: const Icon(Icons.close), onPressed: _cancelSelection)
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
        future: _buildRows(),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rows = [...(snap.data ?? <_RowData>[])];
          rows.sort((a, b) => _compare(a, b));

          return Column(
            children: [
              if (!selectionMode)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 64,
                    child: ElevatedButton(
                      onPressed: () async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const RoundScreen()),
                        );
                        await _refreshHome();
                      },
                      child: const Text(
                        'Start / Resume Recording',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ),
                ),

              if (selectionMode)
                _GrazingBar(
                  residual: residual,
                  selectedCount: selectedPaddockIds.length,
                  onResidualChanged: (v) =>
                      setState(() => residual = clampCover(v)),
                  onUndo: selectedPaddockIds.isEmpty ? null : _undoGrazing,
                  onSave:
                  selectedPaddockIds.isEmpty ? null : () => _saveGrazing(rows),
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
        },
      ),
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
            child: _hdrCell(Storage.colPaddock, 'Pdk', unit: '', alignLeft: true),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Row(
              children: [
                Expanded(child: _hdrCell(Storage.colArea, 'Area', unit: 'ha')),
                Expanded(child: _hdrCell(colRecorded, 'Recorded', unit: 'kgDM/ha')),
                Expanded(child: _hdrCell(colPredicted, 'Predicted', unit: 'kgDM/ha')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdrCell(String col, String label, {required String unit, bool alignLeft = false}) {
    final isSorted = sortCol == col;
    final arrow = isSorted ? (sortAsc ? ' ▲' : ' ▼') : '';
    return InkWell(
      onTap: () => _toggleSort(col),
      child: Column(
        crossAxisAlignment: alignLeft ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Text(
            '$label$arrow',
            style: const TextStyle(fontSize: 11, color: Colors.black87, fontWeight: FontWeight.w700),
            textAlign: alignLeft ? TextAlign.left : TextAlign.center,
          ),
          if (unit.isNotEmpty)
            Text(
              unit,
              style: const TextStyle(fontSize: 10, color: Colors.black54, fontWeight: FontWeight.w600),
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
        : (r.lastAt == null ? 'Prev —' : 'Prev ${daysAgoLabel(now, r.lastAt!)}');

    // ✅ Grey out if grazed OR excluded
    final rowGreyed = r.grazed || isExcluded;

    final isSelected = selectedPaddockIds.contains(r.paddock.id);
    final bg = selectionMode && isSelected ? Colors.lightBlue.withOpacity(0.15) : Colors.transparent;
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
            MaterialPageRoute(builder: (_) => PaddockHistoryScreen(paddock: r.paddock)),
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

                    if (isExcluded == false && r.grazed == false && r.hasRecentNote == false)
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

// -------------------------
// Selection mode grazing bar
// -------------------------
class _GrazingBar extends StatefulWidget {
  final int residual;
  final int selectedCount;
  final ValueChanged<int> onResidualChanged;
  final VoidCallback? onUndo;
  final VoidCallback? onSave;

  const _GrazingBar({
    required this.residual,
    required this.selectedCount,
    required this.onResidualChanged,
    required this.onUndo,
    required this.onSave,
  });

  @override
  State<_GrazingBar> createState() => _GrazingBarState();
}

class _GrazingBarState extends State<_GrazingBar> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.residual.toString());
  }

  @override
  void didUpdateWidget(covariant _GrazingBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.residual != widget.residual && _ctrl.text != widget.residual.toString()) {
      _ctrl.text = widget.residual.toString();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: Colors.black.withOpacity(0.04),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Post grazing residual',
                    style: TextStyle(fontSize: 12, color: Colors.black54)),
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
                          contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        ),
                        onChanged: (s) {
                          final v = int.tryParse(s.trim());
                          if (v != null) widget.onResidualChanged(v);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text('kgDM/ha',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
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
                  onPressed: widget.onSave,
                  child: Text('Save (${widget.selectedCount})'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
