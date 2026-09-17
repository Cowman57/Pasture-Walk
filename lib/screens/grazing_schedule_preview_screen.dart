import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';
import '../widgets/grazing_calendar_board.dart';

class GrazingSchedulePaddock {
  final String id;
  final String name;
  final double areaHa;
  final int predictedCoverKgDmHa;

  GrazingSchedulePaddock({
    required this.id,
    required this.name,
    required this.areaHa,
    required this.predictedCoverKgDmHa,
  });
}

/// Draft offshoot of the shared grazing calendar — edit new blocks, then save.
class GrazingSchedulePreviewScreen extends StatefulWidget {
  final List<GrazingSchedulePaddock> paddocks;
  final DateTimeRange range;
  final int residualKgDmHa;

  const GrazingSchedulePreviewScreen({
    super.key,
    required this.paddocks,
    required this.range,
    required this.residualKgDmHa,
  });

  @override
  State<GrazingSchedulePreviewScreen> createState() =>
      _GrazingSchedulePreviewScreenState();
}

class _GrazingSchedulePreviewScreenState
    extends State<GrazingSchedulePreviewScreen> {
  final storage = Storage();
  final uuid = const Uuid();

  List<GrazingCalendarBlock>? _blocks;
  double _targetHaDay = 0;
  bool _saving = false;

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final herds = await storage.loadHerds();
    final paddocks = await storage.loadPaddocks();
    final grazings = await storage.loadAllGrazings();
    final pById = {for (final p in paddocks) p.id: p};
    final target = Storage.totalAreaGrazedPerDayHa(herds);

    final selected = [...widget.paddocks]
      ..sort(
        (a, b) => b.predictedCoverKgDmHa.compareTo(a.predictedCoverKgDmHa),
      );

    final rangeDays = <DateTime>[];
    var cur = _day(widget.range.start);
    final end = _day(widget.range.end);
    while (!cur.isAfter(end)) {
      rangeDays.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    if (rangeDays.isEmpty) {
      rangeDays.add(_day(DateTime.now()));
    }

    final blocks = <GrazingCalendarBlock>[];

    // Existing grazings as locked context on the board.
    for (final g in grazings) {
      final p = pById[g.paddockId];
      if (p == null || !p.includeInRotation || p.shutForSilage) continue;
      blocks.add(
        GrazingCalendarBlock(
          id: g.id,
          paddockId: g.paddockId,
          paddockName: p.name,
          areaHa: p.areaHa,
          startDay: g.at,
          durationDays: g.durationDays,
          isDraft: false,
          locked: true,
          preCover: g.preCover,
          residual: g.residual,
          harvestedKgDm: g.harvestedKgDm,
          enteredAt: g.enteredAt,
        ),
      );
    }

    // New drafts for the selected paddocks (editable).
    for (var i = 0; i < selected.length; i++) {
      final p = selected[i];
      final start = rangeDays[i % rangeDays.length];
      blocks.add(
        GrazingCalendarBlock(
          id: 'draft_${uuid.v4()}',
          paddockId: p.id,
          paddockName: p.name,
          areaHa: p.areaHa,
          startDay: start,
          durationDays: 1,
          isDraft: true,
          locked: false,
        ),
      );
    }

    if (!mounted) return;
    setState(() {
      _blocks = blocks;
      _targetHaDay = target;
    });
  }

  Future<void> _save() async {
    if (_saving || _blocks == null) return;
    setState(() => _saving = true);

    final drafts = _blocks!.where((b) => b.isDraft).toList();
    final res = clampCover(widget.residualKgDmHa);
    final farmGrowth = await storage.effectiveFarmGrowthKgDmPerHaPerDay();
    final enteredAt = DateTime.now();

    for (final b in drafts) {
      final when = _day(b.startDay);
      final anchor = await storage.latestAnchorForPaddockAsOf(b.paddockId, when);
      final baseCover = anchor?.coverKgDmHa ?? 2500;
      final baseAt = anchor?.at;
      final growDays = baseAt == null ? 0 : when.difference(baseAt).inDays;
      final pre = clampCover(baseCover + (growDays * farmGrowth).round());
      final harvested =
          ((pre - res) * b.areaHa).round().clamp(0, 999999999);

      await storage.appendGrazing(
        Grazing(
          id: uuid.v4(),
          paddockId: b.paddockId,
          at: when,
          enteredAt: enteredAt,
          preCover: pre,
          residual: res,
          harvestedKgDm: harvested,
          durationDays: b.durationDays < 1 ? 1 : b.durationDays,
        ),
      );
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final rangeLabel =
        '${fmt.format(widget.range.start)} → ${fmt.format(widget.range.end)}';
    final blocks = _blocks;
    final draftCount = blocks?.where((b) => b.isDraft).length ?? 0;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
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
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back',
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: _saving
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: _saving || blocks == null ? null : _save,
                      child: Text(
                        _saving ? 'Saving…' : 'Save ($draftCount)',
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    rangeLabel,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'Residual: ${widget.residualKgDmHa} kgDM/ha',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.black54,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: blocks == null
                  ? const Center(child: CircularProgressIndicator())
                  : Padding(
                      padding: const EdgeInsets.fromLTRB(6, 0, 6, 6),
                      child: GrazingCalendarBoard(
                        blocks: blocks,
                        targetHaDay: _targetHaDay,
                        interaction: GrazingCalendarInteraction.edit,
                        focusDay: _day(widget.range.start),
                        onBlocksChanged: (next) {
                          setState(() => _blocks = [...next]);
                        },
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
