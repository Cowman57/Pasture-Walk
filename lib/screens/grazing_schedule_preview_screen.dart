import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';

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

class _ScheduledItem {
  final String paddockId;
  final DateTime day;

  _ScheduledItem({required this.paddockId, required this.day});
}

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

  late List<GrazingSchedulePaddock> order;
  bool saving = false;

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  List<DateTime> _daysInRange(DateTimeRange r) {
    final start = _day(r.start);
    final end = _day(r.end);

    final out = <DateTime>[];
    var cur = start;
    while (!cur.isAfter(end)) {
      out.add(cur);
      cur = cur.add(const Duration(days: 1));
    }
    return out;
  }

  List<_ScheduledItem> _buildSchedule() {
    final days = _daysInRange(widget.range);
    if (days.isEmpty) return const <_ScheduledItem>[];

    final out = <_ScheduledItem>[];
    for (int i = 0; i < order.length; i++) {
      out.add(
        _ScheduledItem(paddockId: order[i].id, day: days[i % days.length]),
      );
    }
    return out;
  }

  Map<DateTime, List<GrazingSchedulePaddock>> _groupedPreview() {
    final byId = {for (final p in order) p.id: p};
    final items = _buildSchedule();

    final map = <DateTime, List<GrazingSchedulePaddock>>{};
    for (final it in items) {
      final p = byId[it.paddockId];
      if (p == null) continue;
      (map[it.day] ??= []).add(p);
    }

    final keys = map.keys.toList()..sort();
    return {for (final k in keys) k: map[k]!};
  }

  Future<void> _save() async {
    if (saving) return;

    setState(() => saving = true);

    final items = _buildSchedule();
    final res = clampCover(widget.residualKgDmHa);
    final farmGrowth = await storage.effectiveFarmGrowthKgDmPerHaPerDay();

    for (final it in items) {
      final when = _day(it.day);

      final anchor = await storage.latestAnchorForPaddockAsOf(
        it.paddockId,
        when,
      );
      final baseCover = anchor?.coverKgDmHa ?? 2500;
      final baseAt = anchor?.at;
      final days = baseAt == null ? 0 : when.difference(baseAt).inDays;
      final pre = clampCover(baseCover + (days * farmGrowth).round());

      final p = order.firstWhere((x) => x.id == it.paddockId);
      final harvestedKgDm = ((pre - res) * p.areaHa).round().clamp(
        0,
        999999999,
      );

      final g = Grazing(
        id: uuid.v4(),
        paddockId: it.paddockId,
        at: when,
        preCover: pre,
        residual: res,
        harvestedKgDm: harvestedKgDm,
      );

      await storage.appendGrazing(g);
    }

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  void initState() {
    super.initState();
    order = [
      ...widget.paddocks,
    ]..sort((a, b) => b.predictedCoverKgDmHa.compareTo(a.predictedCoverKgDmHa));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final rangeLabel =
        '${fmt.format(widget.range.start)} → ${fmt.format(widget.range.end)}';

    final bottomInset = MediaQuery.paddingOf(context).bottom;

    final grouped = _groupedPreview();

    return Scaffold(
      appBar: AppBar(title: const Text('Schedule grazings')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  rangeLabel,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Residual: ${widget.residualKgDmHa} kgDM/ha',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Colors.black54,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              children: [
                const Text(
                  'Reorder paddocks (press and hold):',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: ReorderableListView.builder(
                    itemCount: order.length,
                    buildDefaultDragHandles: true,
                    onReorder: (oldIndex, newIndex) {
                      setState(() {
                        if (newIndex > oldIndex) newIndex -= 1;
                        final item = order.removeAt(oldIndex);
                        order.insert(newIndex, item);
                      });
                    },
                    itemBuilder: (context, i) {
                      final p = order[i];
                      return ListTile(
                        key: ValueKey(p.id),
                        dense: true,
                        title: Text(
                          p.name,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          'Predicted today: ${p.predictedCoverKgDmHa} kgDM/ha',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Preview by day:',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                ...grouped.entries.map((e) {
                  final day = e.key;
                  final list = e.value;
                  final dLabel = DateFormat('EEE d MMM').format(day);
                  final pLabel = list.map((p) => p.name).join(', ');
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        border: Border.all(color: const Color(0x22000000)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            dLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              color: Colors.black87,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            pLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ],
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
            child: SizedBox(
              height: 48,
              width: double.infinity,
              child: ElevatedButton(
                onPressed: saving ? null : _save,
                child: Text(saving ? 'Saving…' : 'Confirm & Save'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
