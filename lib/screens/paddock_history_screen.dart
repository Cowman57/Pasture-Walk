import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';

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
      future: storage.grazingsForPaddock(widget.paddock.id),
      builder: (context, snap) {
        if (!snap.hasData) {
          return const Center(child: CircularProgressIndicator());
        }

        final grazings = snap.data!;
        if (grazings.isEmpty) {
          return const Center(child: Text('No grazing history yet.'));
        }

        return Column(
          children: [
            _grazingHeader(),
            const Divider(height: 1),
            Expanded(
              child: ListView.separated(
                itemCount: grazings.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (ctx, i) => _grazingRow(grazings[i]),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _grazingHeader() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: const Row(
        children: [
          _HdrCell('Date'),
          _HdrCell('Pre', unit: 'kgDM/ha'),
          _HdrCell('Post', unit: 'kgDM/ha'),
          _HdrCell('Harvest', unit: 'kgDM/ha'),
        ],
      ),
    );
  }

  Widget _grazingRow(Grazing g) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _Cell(_fmtDateShort(g.at)),
          _Cell(g.preCover.toString()),
          _Cell(g.residual.toString()),
          _Cell(_harvestPerHaText(g)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Covers tab
  // ---------------------------------------------------------------------------
  Widget _coversTab() {
    return FutureBuilder<List<Measurement>>(
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
