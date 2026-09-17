import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../storage.dart';
import '../utils.dart';

enum _BarBasis { area, harvest }

class GrazingAccuracyScreen extends StatefulWidget {
  const GrazingAccuracyScreen({super.key});

  @override
  State<GrazingAccuracyScreen> createState() => _GrazingAccuracyScreenState();
}

class _SeriesPoint {
  final DateTime day;
  final double value;
  const _SeriesPoint(this.day, this.value);
}

class _StackSeg {
  final String paddockId;
  final String name;
  final double value;
  final bool planned;
  const _StackSeg({
    required this.paddockId,
    required this.name,
    required this.value,
    required this.planned,
  });
}

class _DayStack {
  final DateTime day;
  /// Primary target for green/red (area ha/day, or grass kgDM/day).
  final double target;
  /// Optional total demand (grass + supplement) in harvest mode.
  final double? secondaryTarget;
  /// Daily supplement kgDM drawn as a blue bar (harvest mode).
  final double supplementKgDm;
  final List<_StackSeg> segs;

  const _DayStack({
    required this.day,
    required this.target,
    this.secondaryTarget,
    this.supplementKgDm = 0,
    required this.segs,
  });

  double get pastureTotal => segs.fold(0.0, (s, e) => s + e.value);
  double get total => pastureTotal + supplementKgDm;
}

class _ScreenData {
  final DateTimeRange range;
  final _AccuracyBundle bundle;
  const _ScreenData(this.range, this.bundle);
}

class _GrazingAccuracyScreenState extends State<GrazingAccuracyScreen> {
  final storage = Storage();

  /// Default: last 7 days + planned ahead.
  String preset = 'recent';
  DateTimeRange? custom;
  _BarBasis barBasis = _BarBasis.area;
  late Future<_ScreenData> _future;

  @override
  void initState() {
    super.initState();
    _future = _loadScreen();
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  Future<DateTimeRange> _resolveRange() async {
    final now = DateTime.now();
    final today = _day(now);

    if (preset == 'recent') {
      final start = today.subtract(const Duration(days: 7));
      var end = today;
      final gs = await storage.loadAllGrazings();
      for (final g in gs) {
        if (!g.at.isAfter(now)) continue;
        final d = _day(g.at);
        if (d.isAfter(end)) end = d;
      }
      return DateTimeRange(start: start, end: end);
    }

    if (preset == 'custom' || preset == 'all') {
      return custom ??
          DateTimeRange(
            start: today.subtract(const Duration(days: 30)),
            end: today,
          );
    }

    switch (preset) {
      case 'week':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 7)),
          end: today,
        );
      case '3m':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 90)),
          end: today,
        );
      case '6m':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 180)),
          end: today,
        );
      case 'year':
        return DateTimeRange(
          start: today.subtract(const Duration(days: 365)),
          end: today,
        );
      case 'month':
      default:
        return DateTimeRange(
          start: today.subtract(const Duration(days: 30)),
          end: today,
        );
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final today = _day(now);
    var last = today.add(const Duration(days: 365));
    final gs = await storage.loadAllGrazings();
    for (final g in gs) {
      final d = _day(g.at);
      if (d.isAfter(last)) last = d;
    }
    if (!mounted) return;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: last,
      initialDateRange: custom ??
          DateTimeRange(
            start: today.subtract(const Duration(days: 7)),
            end: today,
          ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      preset = 'custom';
      custom = DateTimeRange(start: _day(picked.start), end: _day(picked.end));
      _future = _loadScreen();
    });
  }

  String _fmtRange(DateTimeRange r) {
    final fmt = DateFormat('d MMM yyyy');
    return '${fmt.format(r.start)} → ${fmt.format(r.end)}';
  }

  int _daysInclusive(DateTimeRange r) {
    final a = _day(r.start);
    final b = _day(r.end);
    return b.difference(a).inDays + 1;
  }

  Future<_ScreenData> _loadScreen() async {
    final range = await _resolveRange();
    final bundle = await _loadBundle(range);
    return _ScreenData(range, bundle);
  }

  Future<_AccuracyBundle> _loadBundle(DateTimeRange range) async {
    final herds = await storage.loadHerds();
    final paddocks = await storage.loadPaddocks();
    final grazings = await storage.loadAllGrazings();
    final targetHistory = await storage.ensureHerdTargetHistory();
    final pById = {for (final p in paddocks) p.id: p};
    final includedIds = paddocks
        .where((p) => p.includeInRotation && !p.shutForSilage)
        .map((p) => p.id)
        .toSet();

    final currentTargetHaDay = Storage.totalAreaGrazedPerDayHa(herds);
    final start = _day(range.start);
    final end = _day(range.end);
    final days = _daysInclusive(range);
    final today = _day(DateTime.now());
    final now = DateTime.now();

    // Grazings whose duration overlaps chart window (plus lookback for rolling 7d).
    final lookbackStart = start.subtract(const Duration(days: 6));
    final inWindow = grazings.where((g) {
      final gStart = _day(g.at);
      final gEnd = gStart.add(Duration(days: (g.durationDays < 1 ? 1 : g.durationDays) - 1));
      if (gEnd.isBefore(lookbackStart) || gStart.isAfter(end)) return false;
      final p = pById[g.paddockId];
      if (p == null || !p.includeInRotation || p.shutForSilage) return false;
      return includedIds.contains(g.paddockId);
    }).toList();

    final areaByDay = <DateTime, double>{};
    final harvestByDay = <DateTime, double>{};
    final segsAreaByDay = <DateTime, List<_StackSeg>>{};
    final segsHarvestByDay = <DateTime, List<_StackSeg>>{};

    for (final g in inWindow) {
      final p = pById[g.paddockId]!;
      final planned = g.at.isAfter(now);
      forEachGrazingAllocationDay(
        g.at,
        g.durationDays,
        areaHa: p.areaHa,
        harvestedKgDm: g.harvestedKgDm.toDouble(),
        fn: (d, area, harvest) {
          if (d.isBefore(lookbackStart) || d.isAfter(end)) return;
          areaByDay[d] = (areaByDay[d] ?? 0) + area;
          harvestByDay[d] = (harvestByDay[d] ?? 0) + harvest;
          segsAreaByDay.putIfAbsent(d, () => []).add(
                _StackSeg(
                  paddockId: p.id,
                  name: p.name,
                  value: area,
                  planned: planned,
                ),
              );
          segsHarvestByDay.putIfAbsent(d, () => []).add(
                _StackSeg(
                  paddockId: p.id,
                  name: p.name,
                  value: harvest,
                  planned: planned,
                ),
              );
        },
      );
    }

    // KPIs: past days in range only (through today).
    final kpiEnd = end.isBefore(today) ? end : today;
    final kpiDays = kpiEnd.isBefore(start)
        ? 0
        : kpiEnd.difference(start).inDays + 1;
    double areaPast = 0;
    var harvestPast = 0;
    var grazingCountPast = 0;
    final counted = <String>{};
    for (final g in inWindow) {
      if (g.at.isAfter(now)) continue;
      var touched = false;
      forEachGrazingAllocationDay(
        g.at,
        g.durationDays,
        areaHa: pById[g.paddockId]!.areaHa,
        harvestedKgDm: g.harvestedKgDm.toDouble(),
        fn: (d, area, harvest) {
          if (d.isBefore(start) || d.isAfter(kpiEnd)) return;
          areaPast += area;
          harvestPast += harvest.round();
          touched = true;
        },
      );
      if (touched && counted.add(g.id)) grazingCountPast++;
    }
    final actualHaDay = kpiDays > 0 ? areaPast / kpiDays : 0.0;

    final areaSeries = <_SeriesPoint>[];
    final targetSeries = <_SeriesPoint>[];
    final dayStacksArea = <_DayStack>[];
    final dayStacksHarvest = <_DayStack>[];
    var targetSumPast = 0.0;

    final totalCows = herds.fold<int>(0, (s, h) => s + h.cowCount);
    final pasturePerCowDay = (totalCows > 0 && kpiDays > 0)
        ? harvestPast / totalCows / kpiDays
        : 0.0;
    final supplementKgDay = herds.fold<double>(
      0.0,
      (s, h) => s + h.cowCount * h.supplementKgDmPerCowPerDay,
    );
    // Convert area target → grass kgDM using period harvest intensity.
    final avgHarvestKgPerHa = areaPast > 0 ? harvestPast / areaPast : 0.0;

    for (var i = 0; i < days; i++) {
      final d = start.add(Duration(days: i));
      var windowArea = 0.0;
      for (var w = 0; w < 7; w++) {
        windowArea += areaByDay[d.subtract(Duration(days: w))] ?? 0;
      }
      final dayTargetHa = Storage.targetHaDayOn(
        targetHistory,
        d.isAfter(today) ? today : d,
        fallback: currentTargetHaDay,
      );
      if (!d.isAfter(kpiEnd) && !d.isBefore(start)) {
        targetSumPast += dayTargetHa;
      }
      areaSeries.add(_SeriesPoint(d, windowArea / 7.0));
      targetSeries.add(_SeriesPoint(d, dayTargetHa));

      dayStacksArea.add(
        _DayStack(
          day: d,
          target: dayTargetHa,
          segs: List<_StackSeg>.from(segsAreaByDay[d] ?? const []),
        ),
      );

      final grassTargetKg = avgHarvestKgPerHa > 0
          ? dayTargetHa * avgHarvestKgPerHa
          : (totalCows * pasturePerCowDay);
      dayStacksHarvest.add(
        _DayStack(
          day: d,
          target: grassTargetKg,
          secondaryTarget: grassTargetKg + supplementKgDay,
          supplementKgDm: supplementKgDay,
          segs: List<_StackSeg>.from(segsHarvestByDay[d] ?? const []),
        ),
      );
    }

    final periodTargetHaDay =
        kpiDays > 0 ? targetSumPast / kpiDays : currentTargetHaDay;
    final accuracy =
        periodTargetHaDay > 0 ? actualHaDay / periodTargetHaDay : null;

    // Planned: first → last day covered by future scheduled grazings.
    DateTime? planStart;
    DateTime? planEnd;
    double plannedArea = 0;
    var plannedCount = 0;
    for (final g in grazings) {
      if (!g.at.isAfter(now)) continue;
      final d0 = _day(g.at);
      final d1 = d0.add(Duration(days: (g.durationDays < 1 ? 1 : g.durationDays) - 1));
      final p = pById[g.paddockId];
      if (p == null || !p.includeInRotation || p.shutForSilage) continue;
      plannedArea += p.areaHa;
      plannedCount++;
      if (planStart == null || d0.isBefore(planStart)) planStart = d0;
      if (planEnd == null || d1.isAfter(planEnd)) planEnd = d1;
    }
    final plannedDays = (planStart != null && planEnd != null)
        ? planEnd.difference(planStart).inDays + 1
        : 0;
    final plannedHaDay =
        plannedDays > 0 ? plannedArea / plannedDays : 0.0;
    final plannedAcc =
        currentTargetHaDay > 0 && plannedDays > 0
            ? plannedHaDay / currentTargetHaDay
            : null;

    return _AccuracyBundle(
      targetHaDay: periodTargetHaDay,
      currentTargetHaDay: currentTargetHaDay,
      actualHaDay: actualHaDay,
      accuracy: accuracy,
      days: days,
      grazingCount: grazingCountPast,
      harvestKg: harvestPast,
      areaSeries: areaSeries,
      targetSeries: targetSeries,
      plannedHaDay: plannedHaDay,
      plannedAccuracy: plannedAcc,
      plannedCount: plannedCount,
      plannedArea: plannedArea,
      plannedDays: plannedDays,
      plannedStart: planStart,
      plannedEnd: planEnd,
      dayStacksArea: dayStacksArea,
      dayStacksHarvest: dayStacksHarvest,
      today: today,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grazing accuracy'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'custom') {
                await _pickCustomRange();
                return;
              }
              if (v == 'all') {
                final gs = await storage.loadAllGrazings();
                final now = DateTime.now();
                final today = _day(now);
                var end = today;
                for (final g in gs) {
                  final d = _day(g.at);
                  if (d.isAfter(end)) end = d;
                }
                if (gs.isEmpty) {
                  setState(() {
                    preset = 'all';
                    custom = DateTimeRange(
                      start: today.subtract(const Duration(days: 365)),
                      end: today,
                    );
                    _future = _loadScreen();
                  });
                  return;
                }
                gs.sort((a, b) => a.at.compareTo(b.at));
                setState(() {
                  preset = 'all';
                  custom = DateTimeRange(start: _day(gs.first.at), end: end);
                  _future = _loadScreen();
                });
                return;
              }
              setState(() {
                preset = v;
                _future = _loadScreen();
              });
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'recent',
                child: Text('7 days + planned'),
              ),
              PopupMenuItem(value: 'week', child: Text('Past week')),
              PopupMenuItem(value: 'month', child: Text('Past month')),
              PopupMenuItem(value: '3m', child: Text('3 months')),
              PopupMenuItem(value: '6m', child: Text('6 months')),
              PopupMenuItem(value: 'year', child: Text('Year')),
              PopupMenuItem(value: 'all', child: Text('All time')),
              PopupMenuItem(value: 'custom', child: Text('Custom…')),
            ],
          ),
        ],
      ),
      body: FutureBuilder<_ScreenData>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final range = snap.data!.range;
          final b = snap.data!.bundle;
          final accPct = b.accuracy == null ? null : (b.accuracy! * 100);
          final planPct =
              b.plannedAccuracy == null ? null : (b.plannedAccuracy! * 100);
          final stacks = barBasis == _BarBasis.area
              ? b.dayStacksArea
              : b.dayStacksHarvest;
          final barUnit = barBasis == _BarBasis.area ? 'ha' : 'kgDM';
          final targetLabel = barBasis == _BarBasis.area
              ? 'Target ha/day'
              : 'Grass target';

          return ListView(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
            children: [
              Text(
                preset == 'recent'
                    ? '${_fmtRange(range)} · 7 days + planned'
                    : _fmtRange(range),
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 12),
              _kpiGrid([
                _Kpi(
                  'Accuracy',
                  accPct == null ? '—' : '${accPct.toStringAsFixed(0)}%',
                ),
                _Kpi(
                  'Target (avg)',
                  '${b.targetHaDay.toStringAsFixed(2)} ha/d',
                ),
                _Kpi('Actual', '${b.actualHaDay.toStringAsFixed(2)} ha/d'),
                _Kpi(
                  'Difference',
                  '${b.actualHaDay >= b.targetHaDay ? '+' : ''}${(b.actualHaDay - b.targetHaDay).toStringAsFixed(2)} ha/d',
                ),
                _Kpi('Grazings', b.grazingCount.toString()),
                _Kpi('Harvested', '${b.harvestKg} kgDM'),
              ]),
              if ((b.currentTargetHaDay - b.targetHaDay).abs() > 1e-6)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'Current herd target: ${b.currentTargetHaDay.toStringAsFixed(2)} ha/d',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Colors.black54,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Daily paddocks vs target',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  SegmentedButton<_BarBasis>(
                    segments: const [
                      ButtonSegment(
                        value: _BarBasis.area,
                        label: Text('Area'),
                      ),
                      ButtonSegment(
                        value: _BarBasis.harvest,
                        label: Text('Harvest'),
                      ),
                    ],
                    selected: {barBasis},
                    onSelectionChanged: (s) {
                      setState(() => barBasis = s.first);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                barBasis == _BarBasis.area
                    ? 'Stacked paddock area per day. Green below target, red/orange above. Tap a bar for paddocks.'
                    : 'Harvested pasture (green/red vs grass target). Blue = daily supplement. Orange = grass target, brown = grass + supplement.',
                style: const TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              _StackedPaddockChart(
                days: stacks,
                today: b.today,
                unit: barUnit,
                targetLabel: targetLabel,
              ),
              const SizedBox(height: 20),
              const Text(
                'Area grazed vs target',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              const Text(
                'Rolling 7-day ha/day (blue, includes scheduled) vs herd target (orange)',
                style: TextStyle(fontSize: 12, color: Colors.black54),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 220,
                child: _DualLineChart(
                  a: b.areaSeries,
                  b: b.targetSeries,
                  aLabel: 'Actual 7d',
                  bLabel: 'Target',
                  aColor: const Color(0xFF2F66E3),
                  bColor: const Color(0xFFE67E22),
                  unit: 'ha/day',
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Planned grazing',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                color: Colors.black.withValues(alpha: 0.04),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        b.plannedStart == null || b.plannedEnd == null
                            ? 'No scheduled grazings'
                            : b.plannedDays == 1
                                ? 'On ${DateFormat('d MMM yyyy').format(b.plannedStart!)}'
                                : '${DateFormat('d MMM yyyy').format(b.plannedStart!)} → ${DateFormat('d MMM yyyy').format(b.plannedEnd!)} · ${b.plannedDays} days',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black54,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (b.plannedCount > 0) ...[
                        const SizedBox(height: 10),
                        _detailRow(
                          'Scheduled events',
                          b.plannedCount.toString(),
                        ),
                        _detailRow(
                          'Scheduled area',
                          '${b.plannedArea.toStringAsFixed(2)} ha',
                        ),
                        _detailRow(
                          'Planned ha/day',
                          b.plannedHaDay.toStringAsFixed(2),
                        ),
                        _detailRow(
                          'vs target',
                          b.currentTargetHaDay <= 0 || planPct == null
                              ? '—'
                              : '${planPct.toStringAsFixed(0)}% '
                                  '(${b.plannedHaDay >= b.currentTargetHaDay ? '+' : ''}${(b.plannedHaDay - b.currentTargetHaDay).toStringAsFixed(2)} ha/d)',
                        ),
                      ],
                      if (b.plannedCount == 0)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text(
                            'Schedule grazings from the Paddocks or Map tab to see planned accuracy.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.black54,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _detailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: Colors.black54,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _kpiGrid(List<_Kpi> items) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final k in items)
          SizedBox(
            width: (MediaQuery.sizeOf(context).width - 32 - 8) / 2,
            child: Card(
              elevation: 0,
              color: Colors.black.withValues(alpha: 0.04),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      k.label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      k.value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Kpi {
  final String label;
  final String value;
  const _Kpi(this.label, this.value);
}

class _AccuracyBundle {
  final double targetHaDay;
  final double currentTargetHaDay;
  final double actualHaDay;
  final double? accuracy;
  final int days;
  final int grazingCount;
  final int harvestKg;
  final List<_SeriesPoint> areaSeries;
  final List<_SeriesPoint> targetSeries;
  final double plannedHaDay;
  final double? plannedAccuracy;
  final int plannedCount;
  final double plannedArea;
  final int plannedDays;
  final DateTime? plannedStart;
  final DateTime? plannedEnd;
  final List<_DayStack> dayStacksArea;
  final List<_DayStack> dayStacksHarvest;
  final DateTime today;

  const _AccuracyBundle({
    required this.targetHaDay,
    required this.currentTargetHaDay,
    required this.actualHaDay,
    required this.accuracy,
    required this.days,
    required this.grazingCount,
    required this.harvestKg,
    required this.areaSeries,
    required this.targetSeries,
    required this.plannedHaDay,
    required this.plannedAccuracy,
    required this.plannedCount,
    required this.plannedArea,
    required this.plannedDays,
    required this.plannedStart,
    required this.plannedEnd,
    required this.dayStacksArea,
    required this.dayStacksHarvest,
    required this.today,
  });
}

// ---------------------------------------------------------------------------
// Stacked paddock bar chart
// ---------------------------------------------------------------------------

class _StackedPaddockChart extends StatefulWidget {
  final List<_DayStack> days;
  final DateTime today;
  final String unit;
  final String targetLabel;

  const _StackedPaddockChart({
    required this.days,
    required this.today,
    required this.unit,
    required this.targetLabel,
  });

  @override
  State<_StackedPaddockChart> createState() => _StackedPaddockChartState();
}

class _StackedPaddockChartState extends State<_StackedPaddockChart> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    if (widget.days.isEmpty) {
      return const SizedBox(
        height: 220,
        child: Center(child: Text('No days in this range.')),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 220,
          child: LayoutBuilder(
            builder: (context, c) {
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: (d) {
                  const leftPad = 44.0;
                  const rightPad = 12.0;
                  final plotW = c.maxWidth - leftPad - rightPad;
                  final x =
                      d.localPosition.dx.clamp(leftPad, leftPad + plotW);
                  final n = widget.days.length;
                  final i =
                      ((x - leftPad) / plotW * n).floor().clamp(0, n - 1);
                  setState(() => selected = i);
                },
                child: CustomPaint(
                  size: Size(c.maxWidth, c.maxHeight),
                  painter: _StackedPaddockPainter(
                    days: widget.days,
                    today: widget.today,
                    unit: widget.unit,
                    targetLabel: widget.targetLabel,
                    selectedIndex: selected,
                  ),
                ),
              );
            },
          ),
        ),
        if (selected != null &&
            selected! >= 0 &&
            selected! < widget.days.length)
          _dayDetail(widget.days[selected!]),
      ],
    );
  }

  Widget _dayDetail(_DayStack day) {
    final fmt = DateFormat('EEE d MMM');
    final isFuture = day.day.isAfter(widget.today);
    final supp = day.supplementKgDm;
    final grassLabel = day.target >= 100
        ? day.target.toStringAsFixed(0)
        : day.target.toStringAsFixed(2);
    final totalLabel = day.pastureTotal >= 100
        ? day.pastureTotal.toStringAsFixed(0)
        : day.pastureTotal.toStringAsFixed(2);
    final base = day.segs.isEmpty && supp <= 0
        ? '${fmt.format(day.day)}: no grazings'
        : '${fmt.format(day.day)}${isFuture ? ' (planned)' : ''}: '
            '${day.segs.isEmpty ? 'no pasture' : day.segs.map((s) => '${s.name} ${s.value >= 100 ? s.value.toStringAsFixed(0) : s.value.toStringAsFixed(2)}').join(' · ')}'
            ' · pasture $totalLabel / grass target $grassLabel'
            '${supp > 0 ? ' · supp ${supp >= 100 ? supp.toStringAsFixed(0) : supp.toStringAsFixed(1)}' : ''}';
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          base,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

class _StackedPaddockPainter extends CustomPainter {
  final List<_DayStack> days;
  final DateTime today;
  final String unit;
  final String targetLabel;
  final int? selectedIndex;

  static const _greens = [
    Color(0xFF1B5E20),
    Color(0xFF2E7D32),
    Color(0xFF388E3C),
    Color(0xFF43A047),
    Color(0xFF66BB6A),
    Color(0xFF81C784),
  ];
  static const _reds = [
    Color(0xFFBF360C),
    Color(0xFFE64A19),
    Color(0xFFF57C00),
    Color(0xFFFB8C00),
    Color(0xFFFFA726),
    Color(0xFFEF5350),
  ];

  _StackedPaddockPainter({
    required this.days,
    required this.today,
    required this.unit,
    required this.targetLabel,
    required this.selectedIndex,
  });

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 44.0;
    const topPad = 28.0;
    const rightPad = 12.0;
    const bottomPad = 34.0;
    final plot = Rect.fromLTWH(
      leftPad,
      topPad,
      size.width - leftPad - rightPad,
      size.height - topPad - bottomPad,
    );

    final axis = Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plot, axis);

    if (days.isEmpty) return;

    var yMax = 0.0;
    for (final d in days) {
      if (d.total > yMax) yMax = d.total;
      if (d.target > yMax) yMax = d.target;
      final sec = d.secondaryTarget;
      if (sec != null && sec > yMax) yMax = sec;
    }
    if (yMax < 1e-6) yMax = 1;
    yMax *= 1.12;
    const yMin = 0.0;
    final ySpan = yMax - yMin;

    double yFor(double v) =>
        plot.bottom - ((v - yMin) / ySpan) * plot.height;

    final grid = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    const steps = 4;
    for (var i = 0; i <= steps; i++) {
      final frac = i / steps;
      final yy = plot.bottom - frac * plot.height;
      final yv = yMin + frac * ySpan;
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: yv >= 100 ? yv.toStringAsFixed(0) : yv.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0x99000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(8, yy - 6));
    }

    final n = days.length;
    final slot = plot.width / n;
    final barW = (slot * 0.72).clamp(4.0, 36.0);
    const suppBlue = Color(0xFF1E88E5);

    for (var i = 0; i < n; i++) {
      final day = days[i];
      final cx = plot.left + slot * (i + 0.5);
      final left = cx - barW / 2;
      var cursor = 0.0;
      var gIdx = 0;
      var rIdx = 0;
      final isFuture = day.day.isAfter(today);

      void drawBand(double lo, double hi, Color color) {
        if (hi <= lo) return;
        final rect = Rect.fromLTRB(left, yFor(hi), left + barW, yFor(lo));
        canvas.drawRect(
          rect,
          Paint()..color = color.withValues(alpha: isFuture ? 0.55 : 1.0),
        );
        canvas.drawRect(
          rect,
          Paint()
            ..color = const Color(0x22000000)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 0.5,
        );
      }

      for (final seg in day.segs) {
        if (seg.value <= 0) continue;
        final bottom = cursor;
        final top = cursor + seg.value;

        if (top <= day.target + 1e-9) {
          drawBand(bottom, top, _greens[gIdx++ % _greens.length]);
        } else if (bottom >= day.target - 1e-9) {
          drawBand(bottom, top, _reds[rIdx++ % _reds.length]);
        } else {
          drawBand(bottom, day.target, _greens[gIdx++ % _greens.length]);
          drawBand(day.target, top, _reds[rIdx++ % _reds.length]);
        }
        cursor = top;
      }

      // Supplement allocation (blue) stacked on top of pasture harvest.
      if (day.supplementKgDm > 0) {
        drawBand(cursor, cursor + day.supplementKgDm, suppBlue);
        cursor += day.supplementKgDm;
      }

      if (selectedIndex == i) {
        canvas.drawRect(
          Rect.fromLTRB(left - 2, plot.top, left + barW + 2, plot.bottom),
          Paint()
            ..color = const Color(0x332F66E3)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2,
        );
      }
    }

    Path stepPath(double Function(_DayStack d) valueOf) {
      final path = Path();
      for (var i = 0; i < n; i++) {
        final day = days[i];
        final x0 = plot.left + slot * i;
        final x1 = plot.left + slot * (i + 1);
        final ty = yFor(valueOf(day));
        if (i == 0) {
          path.moveTo(x0, ty);
        } else {
          path.lineTo(x0, ty);
        }
        path.lineTo(x1, ty);
      }
      return path;
    }

    // Grass / primary target (orange)
    canvas.drawPath(
      stepPath((d) => d.target),
      Paint()
        ..color = const Color(0xFFE67E22)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // Total demand = grass + supplement (brown), when present
    final hasSecondary = days.any(
      (d) => d.secondaryTarget != null && d.secondaryTarget! > 0,
    );
    if (hasSecondary) {
      canvas.drawPath(
        stepPath((d) => d.secondaryTarget ?? d.target),
        Paint()
          ..color = const Color(0xFF6D4C41)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke,
      );
    }

    final title = TextPainter(
      text: TextSpan(
        children: [
          const TextSpan(
            text: 'Below  ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF2E7D32),
            ),
          ),
          const TextSpan(
            text: 'Above  ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFFE64A19),
            ),
          ),
          if (hasSecondary)
            const TextSpan(
              text: 'Supp  ',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: Color(0xFF1E88E5),
              ),
            ),
          TextSpan(
            text: hasSecondary
                ? 'Grass (orange) · Total (brown) · $unit'
                : '$targetLabel · $unit',
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0x88000000),
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, const Offset(12, 6));

    final labelFmt = DateFormat('d MMM');
    final labelIdx = n <= 3
        ? [for (var i = 0; i < n; i++) i]
        : [0, n ~/ 2, n - 1];
    for (final i in labelIdx) {
      final cx = plot.left + slot * (i + 0.5);
      final tp = TextPainter(
        text: TextSpan(
          text: labelFmt.format(days[i].day),
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: days[i].day.isAfter(today)
                ? const Color(0xFF1565C0)
                : const Color(0x99000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var x = cx - tp.width / 2;
      x = x.clamp(plot.left, plot.right - tp.width);
      tp.paint(canvas, Offset(x, plot.bottom + 6));
    }
  }

  @override
  bool shouldRepaint(covariant _StackedPaddockPainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.days != days ||
        oldDelegate.unit != unit;
  }
}

// ---------------------------------------------------------------------------
// Dual line chart
// ---------------------------------------------------------------------------

class _DualLineChart extends StatefulWidget {
  final List<_SeriesPoint> a;
  final List<_SeriesPoint> b;
  final String aLabel;
  final String bLabel;
  final Color aColor;
  final Color bColor;
  final String unit;

  const _DualLineChart({
    required this.a,
    required this.b,
    required this.aLabel,
    required this.bLabel,
    required this.aColor,
    required this.bColor,
    required this.unit,
  });

  @override
  State<_DualLineChart> createState() => _DualLineChartState();
}

class _DualLineChartState extends State<_DualLineChart> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    final pts = widget.a.length >= widget.b.length ? widget.a : widget.b;
    if (pts.length < 2) {
      return const Center(child: Text('Not enough data in this range.'));
    }

    return LayoutBuilder(
      builder: (context, c) {
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final n = pts.length;
            final plotLeft = 44.0;
            final plotRight = c.maxWidth - 12.0;
            final x = d.localPosition.dx.clamp(plotLeft, plotRight);
            final frac = (x - plotLeft) / (plotRight - plotLeft);
            setState(() {
              selected = (frac * (n - 1)).round().clamp(0, n - 1);
            });
          },
          child: CustomPaint(
            size: Size(c.maxWidth, c.maxHeight),
            painter: _DualLinePainter(
              a: widget.a,
              b: widget.b,
              aLabel: widget.aLabel,
              bLabel: widget.bLabel,
              aColor: widget.aColor,
              bColor: widget.bColor,
              unit: widget.unit,
              selectedIndex: selected,
            ),
          ),
        );
      },
    );
  }
}

class _DualLinePainter extends CustomPainter {
  final List<_SeriesPoint> a;
  final List<_SeriesPoint> b;
  final String aLabel;
  final String bLabel;
  final Color aColor;
  final Color bColor;
  final String unit;
  final int? selectedIndex;

  _DualLinePainter({
    required this.a,
    required this.b,
    required this.aLabel,
    required this.bLabel,
    required this.aColor,
    required this.bColor,
    required this.unit,
    required this.selectedIndex,
  });

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 44.0;
    const topPad = 28.0;
    const rightPad = 12.0;
    const bottomPad = 34.0;
    final plot = Rect.fromLTWH(
      leftPad,
      topPad,
      size.width - leftPad - rightPad,
      size.height - topPad - bottomPad,
    );

    final axis = Paint()
      ..color = const Color(0x22000000)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plot, axis);

    final series = a.length >= 2 ? a : b;
    if (series.length < 2) return;

    final allVals = <double>[
      ...a.map((p) => p.value),
      ...b.map((p) => p.value),
    ];
    var yMin = allVals.reduce((x, y) => x < y ? x : y);
    var yMax = allVals.reduce((x, y) => x > y ? x : y);
    if ((yMax - yMin).abs() < 1e-6) {
      yMin = yMin - 1;
      yMax = yMax + 1;
    }
    final pad = (yMax - yMin) * 0.08;
    yMin -= pad;
    yMax += pad;
    if (yMin > 0 && yMin < (yMax - yMin) * 0.2) yMin = 0;
    final ySpan = yMax - yMin;

    final first = _day(series.first.day);
    final last = _day(series.last.day);
    final spanDays = last.difference(first).inDays;
    final xSpan = spanDays <= 0 ? 1 : spanDays;

    Offset pt(List<_SeriesPoint> s, int i) {
      final d = _day(s[i].day);
      final xFrac = d.difference(first).inDays / xSpan;
      final yFrac = (s[i].value - yMin) / ySpan;
      return Offset(
        plot.left + xFrac * plot.width,
        plot.bottom - yFrac * plot.height,
      );
    }

    final grid = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;
    const steps = 4;
    for (var i = 0; i <= steps; i++) {
      final frac = i / steps;
      final yy = plot.bottom - frac * plot.height;
      final yv = yMin + frac * ySpan;
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);
      final tp = TextPainter(
        text: TextSpan(
          text: yv >= 100 ? yv.toStringAsFixed(0) : yv.toStringAsFixed(1),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0x99000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(8, yy - 6));
    }

    void drawSeries(List<_SeriesPoint> s, Color color) {
      if (s.length < 2) return;
      final paint = Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2;
      final path = Path()..moveTo(pt(s, 0).dx, pt(s, 0).dy);
      for (var i = 1; i < s.length; i++) {
        final p = pt(s, i);
        path.lineTo(p.dx, p.dy);
      }
      canvas.drawPath(path, paint);
    }

    drawSeries(a, aColor);
    drawSeries(b, bColor);

    final title = TextPainter(
      text: TextSpan(
        children: [
          TextSpan(
            text: '$aLabel  ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: aColor,
            ),
          ),
          TextSpan(
            text: '$bLabel  ',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: bColor,
            ),
          ),
          TextSpan(
            text: unit,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: Color(0x88000000),
            ),
          ),
        ],
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    title.paint(canvas, const Offset(12, 6));

    final labelFmt = DateFormat('d MMM');
    for (final i in [0, series.length ~/ 2, series.length - 1]) {
      final p = pt(series, i);
      final tp = TextPainter(
        text: TextSpan(
          text: labelFmt.format(series[i].day),
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: Color(0x99000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var x = p.dx - tp.width / 2;
      x = x.clamp(plot.left, plot.right - tp.width);
      tp.paint(canvas, Offset(x, plot.bottom + 6));
    }

    if (selectedIndex != null &&
        selectedIndex! >= 0 &&
        selectedIndex! < series.length) {
      final i = selectedIndex!;
      final p = pt(series, i);
      canvas.drawLine(
        Offset(p.dx, plot.top),
        Offset(p.dx, plot.bottom),
        Paint()
          ..color = const Color(0x442F66E3)
          ..strokeWidth = 1,
      );
      final aVal = i < a.length ? a[i].value : null;
      final bVal = i < b.length ? b[i].value : null;
      final label =
          '${labelFmt.format(series[i].day)}  '
          '${aVal == null ? '—' : aVal.toStringAsFixed(1)} / '
          '${bVal == null ? '—' : bVal.toStringAsFixed(1)}';
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            color: Color(0xFF222222),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      var bx = p.dx - tp.width / 2;
      bx = bx.clamp(plot.left, plot.right - tp.width);
      final by = (plot.top - tp.height - 8).clamp(0.0, plot.top);
      final bubble = RRect.fromRectAndRadius(
        Rect.fromLTWH(bx - 6, by - 4, tp.width + 12, tp.height + 8),
        const Radius.circular(8),
      );
      canvas.drawRRect(bubble, Paint()..color = Colors.white);
      canvas.drawRRect(bubble, axis);
      tp.paint(canvas, Offset(bx, by));
    }
  }

  @override
  bool shouldRepaint(covariant _DualLinePainter oldDelegate) {
    return oldDelegate.selectedIndex != selectedIndex ||
        oldDelegate.a != a ||
        oldDelegate.b != b;
  }
}
