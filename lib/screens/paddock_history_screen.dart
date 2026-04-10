import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';

class PaddockHistoryScreen extends StatefulWidget {
  final Paddock paddock;

  const PaddockHistoryScreen({super.key, required this.paddock});

  @override
  State<PaddockHistoryScreen> createState() => _PaddockHistoryScreenState();
}

class _PaddockHistoryScreenState extends State<PaddockHistoryScreen>
    with SingleTickerProviderStateMixin {
  final storage = Storage();
  late final TabController _tabs;

  static const int _minCoverBar = 1200;
  static const int _maxCoverBar = 3200;

  double? annualHarvestKgDmPerHa;

  /// Bumps to reload tab FutureBuilders after edit/delete.
  int _refreshTick = 0;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _loadAnnualHarvest();
  }

  Future<void> _loadAnnualHarvest() async {
    final total = await storage.annualHarvestKgDmForPaddock(widget.paddock.id);
    final area = widget.paddock.areaHa;

    final perHa = (area <= 0) ? 0.0 : (total / area);

    if (!mounted) return;
    setState(() => annualHarvestKgDmPerHa = perHa);
  }

  void _bumpRefresh() {
    setState(() => _refreshTick++);
    _loadAnnualHarvest();
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  String _fmtDateShort(DateTime d) {
    const months = [
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
    return '$dd ${months[d.month - 1]}';
  }

  String _fmtDateLong(DateTime d) {
    const months = [
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
    return '$dd ${months[d.month - 1]} ${d.year}';
  }

  String _harvestPerHaText(Grazing g) {
    final area = widget.paddock.areaHa;
    if (area <= 0) return '—';
    final perHa = g.harvestedKgDm / area;
    return perHa.toStringAsFixed(0); // change to 1 dp if you want
  }

  Future<bool> _confirmDelete(String title, String body) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    return r == true;
  }

  Future<DateTime?> _pickDateTime(DateTime initial) async {
    final d = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (d == null || !mounted) return null;
    final t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (t == null || !mounted) return null;
    return DateTime(d.year, d.month, d.day, t.hour, t.minute);
  }

  Future<void> _editCover(Measurement m) async {
    final coverCtrl = TextEditingController(text: '${m.cover}');
    final predCtrl = TextEditingController(text: '${m.predictedCoverAtEntry}');
    var at = m.at;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit cover'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Recorded: ${_fmtDateLong(at)}'),
                TextButton(
                  onPressed: () async {
                    final next = await _pickDateTime(at);
                    if (next != null) setLocal(() => at = next);
                  },
                  child: const Text('Change date & time'),
                ),
                TextField(
                  controller: coverCtrl,
                  decoration: const InputDecoration(labelText: 'Cover (kgDM/ha)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: predCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Predicted at entry (kgDM/ha)',
                  ),
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
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final cover = int.tryParse(coverCtrl.text.trim());
    final pred = int.tryParse(predCtrl.text.trim());
    if (cover == null || pred == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid numbers.')),
      );
      return;
    }

    await storage.updateMeasurement(
      Measurement(
        id: m.id,
        paddockId: m.paddockId,
        at: at,
        cover: clampCover(cover),
        predictedCoverAtEntry: clampCover(pred),
      ),
    );
    if (!mounted) return;
    _bumpRefresh();
  }

  Future<void> _deleteCover(Measurement m) async {
    final ok = await _confirmDelete(
      'Delete cover?',
      'Remove this cover reading? This cannot be undone.',
    );
    if (!ok || !mounted) return;
    await storage.deleteMeasurementById(m.id);
    if (!mounted) return;
    _bumpRefresh();
  }

  Future<void> _editGrazing(Grazing g) async {
    final preCtrl = TextEditingController(text: '${g.preCover}');
    final resCtrl = TextEditingController(text: '${g.residual}');
    var at = g.at;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit grazing'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('When: ${_fmtDateLong(at)}'),
                TextButton(
                  onPressed: () async {
                    final next = await _pickDateTime(at);
                    if (next != null) setLocal(() => at = next);
                  },
                  child: const Text('Change date & time'),
                ),
                TextField(
                  controller: preCtrl,
                  decoration: const InputDecoration(labelText: 'Pre (kgDM/ha)'),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: resCtrl,
                  decoration: const InputDecoration(labelText: 'Residual (kgDM/ha)'),
                  keyboardType: TextInputType.number,
                ),
                Text(
                  'Harvest will be recalculated from pre, residual, and paddock area.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final pre = int.tryParse(preCtrl.text.trim());
    final res = int.tryParse(resCtrl.text.trim());
    if (pre == null || res == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter valid numbers.')),
      );
      return;
    }
    final preC = clampCover(pre);
    final resC = clampCover(res);
    final area = widget.paddock.areaHa;
    final harvested = area <= 0
        ? g.harvestedKgDm
        : ((preC - resC) * area).round().clamp(0, 999999999);

    await storage.updateGrazing(
      Grazing(
        id: g.id,
        paddockId: g.paddockId,
        at: at,
        enteredAt: g.enteredAt,
        preCover: preC,
        residual: resC,
        harvestedKgDm: harvested,
      ),
    );
    if (!mounted) return;
    _bumpRefresh();
  }

  Future<void> _deleteGrazing(Grazing g) async {
    final ok = await _confirmDelete(
      'Delete grazing?',
      'Remove this grazing event? This cannot be undone.',
    );
    if (!ok || !mounted) return;
    await storage.deleteGrazingById(g.id);
    if (!mounted) return;
    _bumpRefresh();
  }

  Future<void> _editNote(NoteEntry n) async {
    final titleCtrl = TextEditingController(text: n.title);
    var at = n.at;

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) => AlertDialog(
          title: const Text('Edit note'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('When: ${_fmtDateLong(at)}'),
                TextButton(
                  onPressed: () async {
                    final next = await _pickDateTime(at);
                    if (next != null) setLocal(() => at = next);
                  },
                  child: const Text('Change date & time'),
                ),
                TextField(
                  controller: titleCtrl,
                  decoration: const InputDecoration(labelText: 'Note'),
                  maxLines: 3,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;

    final t = titleCtrl.text.trim();
    if (t.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Note cannot be empty.')),
      );
      return;
    }

    await storage.updateNote(
      NoteEntry(
        id: n.id,
        paddockId: n.paddockId,
        at: at,
        title: t,
      ),
    );
    if (!mounted) return;
    _bumpRefresh();
  }

  Future<void> _deleteNote(NoteEntry n) async {
    final ok = await _confirmDelete(
      'Delete note?',
      'Remove this note? This cannot be undone.',
    );
    if (!ok || !mounted) return;
    await storage.deleteNoteById(n.id);
    if (!mounted) return;
    _bumpRefresh();
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.paddock;

    return Scaffold(
      appBar: AppBar(
        title: Text('Paddock ${p.name}'),
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'Covers'),
            Tab(text: 'Grazings'),
            Tab(text: 'Notes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabs,
        children: [_coversTab(), _grazingsTab(), _notesTab()],
      ),
      bottomNavigationBar: _statsBar(),
    );
  }

  // ---------------------------------------------------------------------------
  // Bottom stats bar
  // ---------------------------------------------------------------------------
  Widget _statsBar() {
    final area = widget.paddock.areaHa;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.04),
          border: const Border(top: BorderSide(color: Colors.black12)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _statCell(
                label: 'Area',
                value: area.toStringAsFixed(1),
                unit: 'ha',
                alignLeft: true,
              ),
            ),
            Expanded(
              child: _statCell(
                label: 'Annual harvest',
                value: annualHarvestKgDmPerHa == null
                    ? '—'
                    : annualHarvestKgDmPerHa!.toStringAsFixed(0),
                unit: 'kgDM/ha',
                alignLeft: false,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statCell({
    required String label,
    required String value,
    required String unit,
    required bool alignLeft,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: alignLeft
          ? CrossAxisAlignment.start
          : CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisAlignment: alignLeft
              ? MainAxisAlignment.start
              : MainAxisAlignment.end,
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(width: 6),
            Text(
              unit,
              style: const TextStyle(
                fontSize: 12,
                color: Colors.black54,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Grazings tab (columnised)
  // ---------------------------------------------------------------------------
  Widget _grazingsTab() {
    return FutureBuilder<List<Grazing>>(
      key: ValueKey('grazings_$_refreshTick'),
      future: storage.grazingsForPaddock(widget.paddock.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final grazings = snap.data!;
        if (grazings.isEmpty) {
          return const Center(child: Text('No grazing history yet.'));
        }

        final now = DateTime.now();
        final upcoming = grazings.where((g) => g.at.isAfter(now)).toList()
          ..sort((a, b) => a.at.compareTo(b.at));
        final past = grazings.where((g) => !g.at.isAfter(now)).toList()
          ..sort((a, b) => b.at.compareTo(a.at));

        final listChildren = <Widget>[];

        void addRows(List<Grazing> list, bool isUpcoming) {
          for (var i = 0; i < list.length; i++) {
            listChildren.add(
              _grazingRow(context, list[i], isUpcoming: isUpcoming),
            );
            if (i < list.length - 1) {
              listChildren.add(const Divider(height: 1));
            }
          }
        }

        if (upcoming.isNotEmpty) {
          listChildren.add(_grazingSectionHeader(context, 'Upcoming'));
          addRows(upcoming, true);
        }
        if (past.isNotEmpty) {
          if (upcoming.isNotEmpty) {
            listChildren.add(const Divider(height: 1));
          }
          listChildren.add(_grazingSectionHeader(context, 'Past'));
          addRows(past, false);
        }

        return Column(
          children: [
            _grazingHeader(),
            const Divider(height: 1),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: listChildren,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _grazingSectionHeader(BuildContext context, String title) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          letterSpacing: 0.4,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _grazingHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          const _HdrCell('Date'),
          const _HdrCell('Pre', unit: 'kgDM/ha'),
          const _HdrCell('Post', unit: 'kgDM/ha'),
          const _HdrCell('Harvest', unit: 'kgDM/ha'),
          SizedBox(
            width: 40,
            child: Icon(
              Icons.more_vert,
              size: 18,
              color: Colors.black.withValues(alpha: 0.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _grazingRow(
    BuildContext context,
    Grazing g, {
    required bool isUpcoming,
  }) {
    final cs = Theme.of(context).colorScheme;

    final menu = SizedBox(
      width: 40,
      child: PopupMenuButton<String>(
        padding: EdgeInsets.zero,
        icon: Icon(
          Icons.more_vert,
          size: 20,
          color: Colors.black.withValues(alpha: 0.55),
        ),
        onSelected: (v) async {
          if (v == 'edit') await _editGrazing(g);
          if (v == 'delete') await _deleteGrazing(g);
        },
        itemBuilder: (ctx) => const [
          PopupMenuItem(value: 'edit', child: Text('Edit')),
          PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: isUpcoming
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.schedule,
                        size: 16,
                        color: cs.tertiary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _fmtDateShort(g.at),
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              'Scheduled',
                              style: Theme.of(context).textTheme.labelSmall
                                  ?.copyWith(
                                    color: cs.tertiary,
                                    fontWeight: FontWeight.w700,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                : _Cell(_fmtDateShort(g.at)),
          ),
          _Cell(g.preCover.toString()),
          _Cell(g.residual.toString()),
          _Cell(_harvestPerHaText(g)),
          menu,
        ],
      ),
    );

    if (!isUpcoming) return row;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.tertiaryContainer.withValues(alpha: 0.45),
        border: Border(
          left: BorderSide(color: cs.tertiary, width: 3),
        ),
      ),
      child: row,
    );
  }

  // ---------------------------------------------------------------------------
  // Covers tab
  // ---------------------------------------------------------------------------
  Widget _coversTab() {
    return FutureBuilder<List<Measurement>>(
      key: ValueKey('covers_$_refreshTick'),
      future: storage.measurementsForPaddock(widget.paddock.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final ms = snap.data!;
        if (ms.isEmpty) {
          return const Center(child: Text('No cover history yet.'));
        }

        return ListView.separated(
          itemCount: ms.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final m = ms[i];
            return _coverRow(m);
          },
        );
      },
    );
  }

  Widget _coverRow(Measurement m) {
    final denom = (_maxCoverBar - _minCoverBar);
    final clamped = m.cover.clamp(_minCoverBar, _maxCoverBar);
    final t = denom <= 0 ? 0.0 : ((clamped - _minCoverBar) / denom);

    return SizedBox(
      height: 56,
      child: LayoutBuilder(
        builder: (ctx, constraints) {
          final barW = constraints.maxWidth * t;
          return Stack(
            fit: StackFit.expand,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  width: barW,
                  color: Colors.green.withValues(alpha: 0.18),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${m.cover} kgDM/ha',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _fmtDateLong(m.at),
                      style: const TextStyle(color: Colors.black54),
                    ),
                  ],
                ),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: PopupMenuButton<String>(
                  padding: EdgeInsets.zero,
                  icon: Icon(
                    Icons.more_vert,
                    size: 20,
                    color: Colors.black.withValues(alpha: 0.45),
                  ),
                  onSelected: (v) async {
                    if (v == 'edit') await _editCover(m);
                    if (v == 'delete') await _deleteCover(m);
                  },
                  itemBuilder: (ctx) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Notes tab
  // ---------------------------------------------------------------------------
  Widget _notesTab() {
    return FutureBuilder<List<NoteEntry>>(
      key: ValueKey('notes_$_refreshTick'),
      future: storage.notesForPaddock(widget.paddock.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final ns = snap.data!;
        if (ns.isEmpty) {
          return const Center(child: Text('No notes yet.'));
        }

        return ListView.separated(
          itemCount: ns.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (ctx, i) {
            final n = ns[i];
            return ListTile(
              title: Text(n.title),
              subtitle: Text(_fmtDateLong(n.at)),
              leading: const Icon(Icons.note_alt_outlined),
              trailing: PopupMenuButton<String>(
                onSelected: (v) async {
                  if (v == 'edit') await _editNote(n);
                  if (v == 'delete') await _deleteNote(n);
                },
                itemBuilder: (ctx) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Reusable header & row cells
// -----------------------------------------------------------------------------
class _HdrCell extends StatelessWidget {
  final String label;
  final String? unit;

  const _HdrCell(this.label, {this.unit});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          if (unit != null)
            Text(
              unit!,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: Colors.black54,
              ),
            ),
        ],
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  final String text;

  const _Cell(this.text);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 14),
      ),
    );
  }
}
