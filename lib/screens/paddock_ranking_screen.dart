import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';

class PaddockRankingScreen extends StatefulWidget {
  const PaddockRankingScreen({super.key});

  @override
  State<PaddockRankingScreen> createState() => _PaddockRankingScreenState();
}

class _RankRow {
  final Paddock paddock;
  final double harvestKgDmPerHa;
  final double avgGrowthKgDmPerHaPerDay;
  final int grazings;

  _RankRow({
    required this.paddock,
    required this.harvestKgDmPerHa,
    required this.avgGrowthKgDmPerHaPerDay,
    required this.grazings,
  });
}

class _PaddockRankingScreenState extends State<PaddockRankingScreen> {
  final storage = Storage();

  bool loaded = false;
  List<_RankRow> rows = [];

  DateTimeRange? range;

  String sortCol = 'harvest';
  bool sortAsc = false; // default: biggest first

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    final start = end.subtract(const Duration(days: 30));
    range = DateTimeRange(start: start, end: end);
    await _load();
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

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
    return '$dd ${m[d.month - 1]} ${d.year}';
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: range,
    );
    if (picked == null) return;
    setState(() => range = picked);
    await _load();
  }

  Future<void> _setRangePreset(String preset) async {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);
    if (preset == 'custom') {
      await _pickCustomRange();
      return;
    }

    if (preset == 'month') {
      setState(() {
        range = DateTimeRange(
          start: end.subtract(const Duration(days: 30)),
          end: end,
        );
      });
      await _load();
      return;
    }

    if (preset == 'year') {
      setState(() {
        range = DateTimeRange(
          start: end.subtract(const Duration(days: 365)),
          end: end,
        );
      });
      await _load();
      return;
    }

    if (preset == 'all') {
      final ms = await storage.loadAllMeasurements();
      final gs = await storage.loadAllGrazings();
      final allDates = <DateTime>[
        ...ms.map((m) => m.at),
        ...gs.map((g) => g.at),
      ];
      if (allDates.isEmpty) {
        setState(() {
          range = DateTimeRange(
            start: end.subtract(const Duration(days: 365)),
            end: end,
          );
        });
        await _load();
        return;
      }

      allDates.sort();
      final start = _day(allDates.first);
      setState(() {
        range = DateTimeRange(start: start, end: end);
      });
      await _load();
      return;
    }
  }

  Future<void> _load() async {
    if (range == null) return;
    final r = range!;
    setState(() => loaded = false);

    final paddocks = await storage.loadPaddocks();
    final msAll = await storage.loadAllMeasurements();
    final gsAll = await storage.loadAllGrazings();

    final startDay = _day(r.start);
    final endDay = _day(r.end);

    final out = <_RankRow>[];
    for (final p in paddocks) {
      final ms = msAll.where((m) => m.paddockId == p.id).toList()
        ..sort((a, b) => a.at.compareTo(b.at));
      final gs = gsAll.where((g) => g.paddockId == p.id).toList()
        ..sort((a, b) => a.at.compareTo(b.at));

      // Grazings count + harvest within range (by grazing date)
      final grazingsInRange = gs.where((g) {
        final d = _day(g.at);
        return !d.isBefore(startDay) && !d.isAfter(endDay);
      }).toList();
      final totalHarvestKgDm = grazingsInRange.fold<int>(
        0,
        (sum, g) => sum + g.harvestedKgDm,
      );
      final harvestPerHa = (p.areaHa <= 0)
          ? 0.0
          : (totalHarvestKgDm / p.areaHa);

      // Avg growth within range from measurement-to-measurement segments.
      // Only consider segments fully inside range and ignore segments grazed between.
      final growthRates = <double>[];
      for (int i = 1; i < ms.length; i++) {
        final prev = ms[i - 1];
        final cur = ms[i];

        if (cur.at.isBefore(r.start) || cur.at.isAfter(r.end)) continue;
        if (prev.at.isBefore(r.start) || prev.at.isAfter(r.end)) continue;

        final daysDiff = cur.at.difference(prev.at).inDays;
        if (daysDiff <= 0) continue;

        final grazedBetween = await storage.paddockGrazedBetween(
          p.id,
          prev.at,
          cur.at,
        );
        if (grazedBetween) continue;

        final rate = (cur.cover - prev.cover) / daysDiff;
        if (rate.isFinite && rate > 0) {
          growthRates.add(rate);
        }
      }
      final avgGrowth = growthRates.isEmpty
          ? 0.0
          : growthRates.reduce((a, b) => a + b) / growthRates.length;

      out.add(
        _RankRow(
          paddock: p,
          harvestKgDmPerHa: harvestPerHa,
          avgGrowthKgDmPerHaPerDay: avgGrowth,
          grazings: grazingsInRange.length,
        ),
      );
    }

    rows = out;
    loaded = true;
    if (mounted) setState(() {});
  }

  void _toggleSort(String col) {
    setState(() {
      if (sortCol == col) {
        sortAsc = !sortAsc;
      } else {
        sortCol = col;
        sortAsc =
            (col == 'paddock'); // paddock default asc, harvest default desc
        if (col == 'harvest') sortAsc = false;
      }
    });
  }

  List<_RankRow> _sorted() {
    final list = [...rows];
    list.sort((a, b) {
      int cmp;
      if (sortCol == 'paddock') {
        cmp = a.paddock.name.toLowerCase().compareTo(
          b.paddock.name.toLowerCase(),
        );
      } else if (sortCol == 'growth') {
        cmp = a.avgGrowthKgDmPerHaPerDay.compareTo(b.avgGrowthKgDmPerHaPerDay);
      } else if (sortCol == 'grazings') {
        cmp = a.grazings.compareTo(b.grazings);
      } else {
        cmp = a.harvestKgDmPerHa.compareTo(b.harvestKgDmPerHa);
      }
      return sortAsc ? cmp : -cmp;
    });
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final r = range;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rankings'),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.date_range),
            onSelected: _setRangePreset,
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'month', child: Text('Last month')),
              PopupMenuItem(value: 'year', child: Text('Last year')),
              PopupMenuItem(value: 'all', child: Text('All time')),
              PopupMenuItem(value: 'custom', child: Text('Custom range…')),
            ],
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : rows.isEmpty
          ? const Center(child: Text('No paddocks found.'))
          : Column(
              children: [
                if (r != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: InkWell(
                        onTap: _pickCustomRange,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: Colors.black12),
                            color: Colors.white,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.date_range, size: 18),
                              const SizedBox(width: 8),
                              Text(
                                '${_fmtDateShort(r.start)} → ${_fmtDateShort(r.end)}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      _header(),
                      const Divider(height: 1),
                      Expanded(
                        child: ListView.separated(
                          itemCount: _sorted().length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (ctx, i) {
                            final list = _sorted();
                            final row = list[i];

                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      row.paddock.name,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      row.harvestKgDmPerHa.toStringAsFixed(0),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      row.avgGrowthKgDmPerHaPerDay
                                          .toStringAsFixed(1),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Text(
                                      row.grazings.toString(),
                                      textAlign: TextAlign.center,
                                      style: const TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  Widget _header() {
    final isPdk = sortCol == 'paddock';
    final isHarv = sortCol == 'harvest';
    final isGrowth = sortCol == 'growth';
    final isGrazings = sortCol == 'grazings';

    final pdkArrow = isPdk ? (sortAsc ? ' ▲' : ' ▼') : '';
    final harvArrow = isHarv ? (sortAsc ? ' ▲' : ' ▼') : '';
    final growthArrow = isGrowth ? (sortAsc ? ' ▲' : ' ▼') : '';
    final grazingsArrow = isGrazings ? (sortAsc ? ' ▲' : ' ▼') : '';

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: InkWell(
              onTap: () => _toggleSort('paddock'),
              child: Text(
                'Paddock$pdkArrow',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _toggleSort('harvest'),
              child: Text(
                'Harvest$harvArrow',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _toggleSort('growth'),
              child: Text(
                'Growth$growthArrow',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
          Expanded(
            child: InkWell(
              onTap: () => _toggleSort('grazings'),
              child: Text(
                'Grazings$grazingsArrow',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
