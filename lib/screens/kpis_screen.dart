import 'dart:math';
import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';

class KPIsScreen extends StatefulWidget {
  const KPIsScreen({super.key});

  @override
  State<KPIsScreen> createState() => _KPIsScreenState();
}

class _KPIsScreenState extends State<KPIsScreen> {
  final storage = Storage();

  bool loaded = false;

  DateTimeRange? range;

  // Series
  List<_Point> growthSeries = [];
  List<_Point> coverSeries = [];
  List<_Point> roundSeries = [];

  double avgGrowth = 0; // kgDM/ha/day
  double avgCover = 0; // kgDM/ha
  double avgRound = 0; // days

  List<_ProblemRow> problem = [];

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day).subtract(const Duration(days: 60));
    range = DateTimeRange(start: start, end: DateTime(now.year, now.month, now.day));
    await _load();
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: range,
    );
    if (picked == null) return;
    setState(() => range = picked);
    await _load();
  }

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  String _fmtDateShort(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd ${m[d.month - 1]}';
  }

  String _fmt1(double v) => v.toStringAsFixed(1);

  Future<void> _load() async {
    final r = range!;
    setState(() => loaded = false);

    // Load base data
    final paddocks = await storage.loadPaddocks();
    final included = paddocks.where((p) => p.includeInRotation).toList();
    final includedIds = included.map((p) => p.id).toSet();

    final msAll = await storage.loadAllMeasurements();
    final gsAll = await storage.loadAllGrazings();

    // Filter to included paddocks only
    final ms = msAll.where((m) => includedIds.contains(m.paddockId)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));
    final gs = gsAll.where((g) => includedIds.contains(g.paddockId)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));

    // Build daily buckets within range
    final startDay = _day(r.start);
    final endDay = _day(r.end);

    final days = <DateTime>[];
    for (DateTime d = startDay;
    !d.isAfter(endDay);
    d = d.add(const Duration(days: 1))) {
      days.add(d);
    }

    // -----------------------------
    // 1) Growth series (farm avg growth per day)
    // For each measurement, compare to previous measurement on same paddock
    // and attribute the computed growth rate to the day of the later measurement.
    // Excludes segments that include a grazing between the two measurements.
    // -----------------------------
    final growthByDay = <DateTime, List<double>>{};
    final msByPdk = <String, List<Measurement>>{};
    for (final m in ms) {
      (msByPdk[m.paddockId] ??= []).add(m);
    }

    for (final entry in msByPdk.entries) {
      final list = entry.value..sort((a, b) => a.at.compareTo(b.at));
      for (int i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final cur = list[i];

        // Must land inside range (by cur day)
        final curDay = _day(cur.at);
        if (curDay.isBefore(startDay) || curDay.isAfter(endDay)) continue;

        final daysDiff = cur.at.difference(prev.at).inDays;
        if (daysDiff <= 0) continue;

        // exclude if grazed between prev and cur
        final grazedBetween = await storage.paddockGrazedBetween(entry.key, prev.at, cur.at);
        if (grazedBetween) continue;

        final rate = (cur.cover - prev.cover) / daysDiff;
        (growthByDay[curDay] ??= []).add(rate);
      }
    }

    growthSeries = days.map((d) {
      final arr = growthByDay[d];
      final v = (arr == null || arr.isEmpty) ? double.nan : arr.reduce((a, b) => a + b) / arr.length;
      return _Point(d, v);
    }).toList();

    // Avg growth (ignoring NaNs)
    final growthVals = growthSeries.where((p) => p.y.isFinite).map((p) => p.y).toList();
    avgGrowth = growthVals.isEmpty ? 0 : growthVals.reduce((a, b) => a + b) / growthVals.length;

    // -----------------------------
    // 2) Cover series (farm avg measured cover per day)
    // Uses recorded covers on that day (simple + robust).
    // -----------------------------
    final coverByDay = <DateTime, List<double>>{};
    for (final m in ms) {
      final d = _day(m.at);
      if (d.isBefore(startDay) || d.isAfter(endDay)) continue;
      (coverByDay[d] ??= []).add(m.cover.toDouble());
    }

    coverSeries = days.map((d) {
      final arr = coverByDay[d];
      final v = (arr == null || arr.isEmpty) ? double.nan : arr.reduce((a, b) => a + b) / arr.length;
      return _Point(d, v);
    }).toList();

    final coverVals = coverSeries.where((p) => p.y.isFinite).map((p) => p.y).toList();
    avgCover = coverVals.isEmpty ? 0 : coverVals.reduce((a, b) => a + b) / coverVals.length;

    // -----------------------------
    // 3) Round length series (avg days between grazings per day)
    // For each grazing, compare to previous grazing for that paddock.
    // Attribute interval to the day of the later grazing.
    // -----------------------------
    final roundByDay = <DateTime, List<double>>{};
    final gsByPdk = <String, List<Grazing>>{};
    for (final g in gs) {
      (gsByPdk[g.paddockId] ??= []).add(g);
    }

    for (final entry in gsByPdk.entries) {
      final list = entry.value..sort((a, b) => a.at.compareTo(b.at));
      for (int i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final cur = list[i];

        final curDay = _day(cur.at);
        if (curDay.isBefore(startDay) || curDay.isAfter(endDay)) continue;

        final dd = cur.at.difference(prev.at).inDays;
        if (dd <= 0) continue;

        (roundByDay[curDay] ??= []).add(dd.toDouble());
      }
    }

    roundSeries = days.map((d) {
      final arr = roundByDay[d];
      final v = (arr == null || arr.isEmpty) ? double.nan : arr.reduce((a, b) => a + b) / arr.length;
      return _Point(d, v);
    }).toList();

    final roundVals = roundSeries.where((p) => p.y.isFinite).map((p) => p.y).toList();
    avgRound = roundVals.isEmpty ? 0 : roundVals.reduce((a, b) => a + b) / roundVals.length;

    // -----------------------------
    // 4) Problem paddocks (worst growth over range)
    // Compute per paddock average growth from measurement-to-measurement segments in range.
    // -----------------------------
    final growthByPdk = <String, List<double>>{};
    for (final entry in msByPdk.entries) {
      final list = entry.value..sort((a, b) => a.at.compareTo(b.at));
      for (int i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final cur = list[i];

        // consider only segments where both endpoints are in range
        if (cur.at.isBefore(r.start) || cur.at.isAfter(r.end)) continue;
        if (prev.at.isBefore(r.start) || prev.at.isAfter(r.end)) continue;

        final daysDiff = cur.at.difference(prev.at).inDays;
        if (daysDiff <= 0) continue;

        final grazedBetween = await storage.paddockGrazedBetween(entry.key, prev.at, cur.at);
        if (grazedBetween) continue;

        final rate = (cur.cover - prev.cover) / daysDiff;
        (growthByPdk[entry.key] ??= []).add(rate);
      }
    }

    final pdkNameById = {for (final p in included) p.id: p.name};
    final problems = <_ProblemRow>[];
    for (final id in includedIds) {
      final arr = growthByPdk[id];
      if (arr == null || arr.isEmpty) continue;
      final v = arr.reduce((a, b) => a + b) / arr.length;
      problems.add(_ProblemRow(pdkNameById[id] ?? id, v));
    }
    problems.sort((a, b) => a.avgGrowth.compareTo(b.avgGrowth));
    problem = problems.take(10).toList();

    if (!mounted) return;
    setState(() => loaded = true);
  }

  @override
  Widget build(BuildContext context) {
    final r = range!;
    return Scaffold(
      appBar: AppBar(
        title: const Text('KPIs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.date_range),
            onPressed: _pickRange,
            tooltip: 'Date range',
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _RangeChip(
            text: '${_fmtDateShort(r.start)} → ${_fmtDateShort(r.end)}',
            onTap: _pickRange,
          ),
          const SizedBox(height: 12),

          _KpiCard(
            title: 'Average farm growth',
            value: '${_fmt1(avgGrowth)} kgDM/ha/day',
            child: _LineChart(
              points: growthSeries,
              yLabel: 'kgDM/ha/day',
            ),
          ),

          const SizedBox(height: 12),

          _KpiCard(
            title: 'Average pasture cover',
            value: avgCover <= 0 ? '—' : '${_fmt1(avgCover)} kgDM/ha',
            child: _LineChart(
              points: coverSeries,
              yLabel: 'kgDM/ha',
            ),
          ),

          const SizedBox(height: 12),

          _KpiCard(
            title: 'Average round length',
            value: avgRound <= 0 ? '—' : '${_fmt1(avgRound)} days',
            child: _LineChart(
              points: roundSeries,
              yLabel: 'days',
            ),
          ),

          const SizedBox(height: 12),

          _KpiCard(
            title: 'Problem paddocks (worst growth)',
            value: 'Bottom ${problem.length} (excluded paddocks ignored)',
            child: problem.isEmpty
                ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Text('Not enough data in this date range.'),
            )
                : Column(
              children: [
                for (final p in problem)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            p.name,
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${_fmt1(p.avgGrowth)} /day',
                          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
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

// -----------------------------------------------------------------------------
// UI bits
// -----------------------------------------------------------------------------
class _KpiCard extends StatelessWidget {
  final String title;
  final String value;
  final Widget child;

  const _KpiCard({
    required this.title,
    required this.value,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.black.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

class _RangeChip extends StatelessWidget {
  final String text;
  final VoidCallback onTap;

  const _RangeChip({required this.text, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
              Text(text, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
            ],
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Chart (pan/zoom using InteractiveViewer + CustomPainter)
// -----------------------------------------------------------------------------
class _LineChart extends StatefulWidget {
  final List<_Point> points;
  final String yLabel;

  const _LineChart({required this.points, required this.yLabel});

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  final TransformationController _tc = TransformationController();

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Give it a wide canvas so pan makes sense
    final width = max(600.0, MediaQuery.of(context).size.width - 48);
    const height = 220.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.yLabel, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SizedBox(
          height: height,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              color: Colors.white,
              child: InteractiveViewer(
                transformationController: _tc,
                minScale: 1,
                maxScale: 6,
                boundaryMargin: const EdgeInsets.all(100),
                child: SizedBox(
                  width: width,
                  height: height,
                  child: CustomPaint(
                    painter: _LineChartPainter(widget.points),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            TextButton.icon(
              onPressed: () => setState(() => _tc.value = Matrix4.identity()),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset zoom'),
            ),
          ],
        ),
      ],
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final List<_Point> points;

  _LineChartPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final padL = 44.0;
    final padR = 12.0;
    final padT = 12.0;
    final padB = 26.0;

    final plot = Rect.fromLTWH(padL, padT, size.width - padL - padR, size.height - padT - padB);

    // Background
    final bg = Paint()..color = const Color(0xFFFFFFFF);
    canvas.drawRect(Offset.zero & size, bg);

    // Border
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x11000000);
    canvas.drawRect(plot, border);

    final finite = points.where((p) => p.y.isFinite).toList();
    if (finite.length < 2) {
      _drawNoData(canvas, size, plot);
      return;
    }

    final minX = finite.first.x.millisecondsSinceEpoch.toDouble();
    final maxX = finite.last.x.millisecondsSinceEpoch.toDouble();

    double minY = finite.map((p) => p.y).reduce(min);
    double maxY = finite.map((p) => p.y).reduce(max);
    if (minY == maxY) {
      minY -= 1;
      maxY += 1;
    }

    // Light grid
    final grid = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x0A000000);
    for (int i = 1; i <= 3; i++) {
      final y = plot.top + plot.height * (i / 4);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), grid);
    }

    Offset toPt(_Point p) {
      final x = p.x.millisecondsSinceEpoch.toDouble();
      final nx = (x - minX) / (maxX - minX);
      final ny = (p.y - minY) / (maxY - minY);
      final px = plot.left + nx * plot.width;
      final py = plot.bottom - ny * plot.height;
      return Offset(px, py);
    }

    // Line
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xFF1E7A3E);

    final path = Path();
    bool started = false;
    for (final p in points) {
      if (!p.y.isFinite) continue;
      final o = toPt(p);
      if (!started) {
        path.moveTo(o.dx, o.dy);
        started = true;
      } else {
        path.lineTo(o.dx, o.dy);
      }
    }
    canvas.drawPath(path, line);

    // Y labels (min/max)
    _drawText(canvas, '${minY.toStringAsFixed(0)}', Offset(6, plot.bottom - 10),
        const TextStyle(fontSize: 10, color: Color(0x99000000), fontWeight: FontWeight.w700));
    _drawText(canvas, '${maxY.toStringAsFixed(0)}', Offset(6, plot.top - 2),
        const TextStyle(fontSize: 10, color: Color(0x99000000), fontWeight: FontWeight.w700));

    // X labels (start/end)
    final start = points.first.x;
    final end = points.last.x;
    _drawText(canvas, _shortDate(start), Offset(plot.left, plot.bottom + 6),
        const TextStyle(fontSize: 10, color: Color(0x77000000), fontWeight: FontWeight.w700));
    _drawText(canvas, _shortDate(end), Offset(plot.right - 64, plot.bottom + 6),
        const TextStyle(fontSize: 10, color: Color(0x77000000), fontWeight: FontWeight.w700));
  }

  void _drawNoData(Canvas canvas, Size size, Rect plot) {
    _drawText(
      canvas,
      'Not enough data',
      Offset(plot.left + 12, plot.top + plot.height / 2 - 8),
      const TextStyle(fontSize: 14, color: Color(0x77000000), fontWeight: FontWeight.w800),
    );
  }

  String _shortDate(DateTime d) {
    const m = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
    return '${d.day.toString().padLeft(2, '0')} ${m[d.month - 1]}';
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
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    // repaint if points differ length or last timestamps differ
    if (oldDelegate.points.length != points.length) return true;
    if (points.isEmpty) return false;
    return oldDelegate.points.last.x != points.last.x || oldDelegate.points.last.y != points.last.y;
  }
}

// -----------------------------------------------------------------------------
// Data structs
// -----------------------------------------------------------------------------
class _Point {
  final DateTime x;
  final double y;
  _Point(this.x, this.y);
}

class _ProblemRow {
  final String name;
  final double avgGrowth;
  _ProblemRow(this.name, this.avgGrowth);
}
