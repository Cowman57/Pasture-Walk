import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import '../storage.dart';

class AvgCoverHistoryScreen extends StatefulWidget {
  const AvgCoverHistoryScreen({super.key});

  @override
  State<AvgCoverHistoryScreen> createState() => _AvgCoverHistoryScreenState();
}

class _DayPoint {
  final DateTime day;
  final double avg;

  _DayPoint(this.day, this.avg);
}

class _AvgCoverHistoryScreenState extends State<AvgCoverHistoryScreen> {
  final storage = Storage();

  String preset = 'month';
  DateTimeRange? custom;

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  DateTimeRange _rangeForPreset() {
    final now = DateTime.now();
    final end = DateTime(now.year, now.month, now.day);

    switch (preset) {
      case 'week':
        return DateTimeRange(
          start: end.subtract(const Duration(days: 7)),
          end: end,
        );
      case '3m':
        return DateTimeRange(
          start: end.subtract(const Duration(days: 90)),
          end: end,
        );
      case '6m':
        return DateTimeRange(
          start: end.subtract(const Duration(days: 180)),
          end: end,
        );
      case 'year':
        return DateTimeRange(
          start: end.subtract(const Duration(days: 365)),
          end: end,
        );
      case 'all':
        return custom ??
            DateTimeRange(
              start: end.subtract(const Duration(days: 365)),
              end: end,
            );
      case 'custom':
        return custom ??
            DateTimeRange(
              start: end.subtract(const Duration(days: 30)),
              end: end,
            );
      case 'month':
      default:
        return DateTimeRange(
          start: end.subtract(const Duration(days: 30)),
          end: end,
        );
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year, now.month, now.day),
      initialDateRange: custom,
    );
    if (picked == null) return;
    setState(() {
      preset = 'custom';
      custom = DateTimeRange(start: _day(picked.start), end: _day(picked.end));
    });
  }

  Future<List<_DayPoint>> _loadSeries(DateTimeRange range) async {
    final paddocks = await storage.loadPaddocks();
    final includedIds = paddocks
        .where((p) => p.includeInRotation)
        .map((p) => p.id)
        .toSet();

    final msAll = await storage.loadAllMeasurements();
    final ms = msAll.where((m) => includedIds.contains(m.paddockId)).toList();

    final startDay = _day(range.start);
    final endDay = _day(range.end);

    final byDay = <DateTime, List<int>>{};
    for (final m in ms) {
      final d = _day(m.at);
      if (d.isBefore(startDay) || d.isAfter(endDay)) continue;
      (byDay[d] ??= []).add(m.cover);
    }

    final days = byDay.keys.toList()..sort();
    final out = <_DayPoint>[];

    for (final d in days) {
      final list = byDay[d]!;
      if (list.isEmpty) continue;
      final avg = list.reduce((a, b) => a + b) / list.length;
      out.add(_DayPoint(d, avg.toDouble()));
    }

    return out;
  }

  Future<List<_DayPoint>> _loadGrowthSeries(DateTimeRange range) async {
    final paddocks = await storage.loadPaddocks();
    final includedIds = paddocks
        .where((p) => p.includeInRotation)
        .map((p) => p.id)
        .toSet();

    final msAll = await storage.loadAllMeasurements();
    final ms = msAll.where((m) => includedIds.contains(m.paddockId)).toList()
      ..sort((a, b) => a.at.compareTo(b.at));

    final startDay = _day(range.start);
    final endDay = _day(range.end);

    final byPdk = <String, List<dynamic>>{};
    for (final m in ms) {
      (byPdk[m.paddockId] ??= []).add(m);
    }

    final byDay = <DateTime, List<double>>{};

    for (final entry in byPdk.entries) {
      final list = entry.value;
      list.sort((a, b) => (a.at as DateTime).compareTo(b.at as DateTime));

      for (int i = 1; i < list.length; i++) {
        final prev = list[i - 1];
        final cur = list[i];

        final prevAt = prev.at as DateTime;
        final curAt = cur.at as DateTime;
        final curDay = _day(curAt);

        if (curDay.isBefore(startDay) || curDay.isAfter(endDay)) continue;

        final daysDiff = curAt.difference(prevAt).inDays;
        if (daysDiff <= 0) continue;

        final grazedBetween = await storage.paddockGrazedBetween(
          entry.key,
          prevAt,
          curAt,
        );
        if (grazedBetween) continue;

        final prevCover = prev.cover as int;
        final curCover = cur.cover as int;
        final rate = (curCover - prevCover) / daysDiff;
        if (!rate.isFinite || rate <= 0) continue;

        (byDay[curDay] ??= []).add(rate);
      }
    }

    final days = byDay.keys.toList()..sort();
    final out = <_DayPoint>[];
    for (final d in days) {
      final list = byDay[d]!;
      if (list.isEmpty) continue;
      final avg = list.reduce((a, b) => a + b) / list.length;
      out.add(_DayPoint(d, avg));
    }
    return out;
  }

  String _fmtRange(DateTimeRange r) {
    final fmt = DateFormat('d MMM yyyy');
    return '${fmt.format(r.start)} → ${fmt.format(r.end)}';
  }

  @override
  Widget build(BuildContext context) {
    final range = _rangeForPreset();
    final bottomInset = MediaQuery.paddingOf(context).bottom;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Average cover history'),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'custom') {
                await _pickCustomRange();
                return;
              }
              if (v == 'all') {
                // set custom all-time range based on measurement min date
                final ms = await storage.loadAllMeasurements();
                final now = DateTime.now();
                final end = DateTime(now.year, now.month, now.day);
                if (ms.isEmpty) {
                  setState(() {
                    preset = 'all';
                    custom = DateTimeRange(
                      start: end.subtract(const Duration(days: 365)),
                      end: end,
                    );
                  });
                  return;
                }
                ms.sort((a, b) => a.at.compareTo(b.at));
                setState(() {
                  preset = 'all';
                  custom = DateTimeRange(start: _day(ms.first.at), end: end);
                });
                return;
              }
              setState(() => preset = v);
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'week', child: Text('Week')),
              PopupMenuItem(value: 'month', child: Text('Month')),
              PopupMenuItem(value: '3m', child: Text('3 months')),
              PopupMenuItem(value: '6m', child: Text('6 months')),
              PopupMenuItem(value: 'year', child: Text('Year')),
              PopupMenuItem(value: 'all', child: Text('All time')),
              PopupMenuItem(value: 'custom', child: Text('Custom…')),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + bottomInset),
        children: [
          Text(
            _fmtRange(range),
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black54,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: 260,
            child: FutureBuilder<List<_DayPoint>>(
              future: _loadSeries(range),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final pts = snap.data ?? <_DayPoint>[];
                if (pts.length < 2) {
                  return const Center(
                    child: Text('Not enough recorded cover data in range.'),
                  );
                }

                final minY = pts
                    .map((p) => p.avg)
                    .reduce((a, b) => a < b ? a : b);
                final maxY = pts
                    .map((p) => p.avg)
                    .reduce((a, b) => a > b ? a : b);

                return _LineChart(
                  title: 'Average cover (recorded)',
                  unit: 'kgDM/ha',
                  yStep: 50,
                  points: pts,
                  minY: minY,
                  maxY: maxY,
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 260,
            child: FutureBuilder<List<_DayPoint>>(
              future: _loadGrowthSeries(range),
              builder: (context, snap) {
                if (!snap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }

                final pts = snap.data ?? <_DayPoint>[];
                if (pts.length < 2) {
                  return const Center(
                    child: Text('Not enough growth data in range.'),
                  );
                }

                final minY = pts
                    .map((p) => p.avg)
                    .reduce((a, b) => a < b ? a : b);
                final maxY = pts
                    .map((p) => p.avg)
                    .reduce((a, b) => a > b ? a : b);

                return _LineChart(
                  title: 'Growth (measured)',
                  unit: 'kgDM/ha/day',
                  yStep: 10,
                  points: pts,
                  minY: minY,
                  maxY: maxY,
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LineChart extends StatefulWidget {
  final String title;
  final String unit;
  final double yStep;
  final List<_DayPoint> points;
  final double minY;
  final double maxY;

  const _LineChart({
    required this.title,
    required this.unit,
    required this.yStep,
    required this.points,
    required this.minY,
    required this.maxY,
  });

  @override
  State<_LineChart> createState() => _LineChartState();
}

class _LineChartState extends State<_LineChart> {
  int? selected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final h = c.maxHeight;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) {
            final n = widget.points.length;
            final plotLeft = 12.0;
            final plotRight = w - 12.0;
            final x = d.localPosition.dx.clamp(plotLeft, plotRight);
            final frac = (x - plotLeft) / (plotRight - plotLeft);
            final idx = (frac * (n - 1)).round().clamp(0, n - 1);
            setState(() => selected = idx);
          },
          child: CustomPaint(
            painter: _LineChartPainter(
              title: widget.title,
              unit: widget.unit,
              yStep: widget.yStep,
              points: widget.points,
              minY: widget.minY,
              maxY: widget.maxY,
              selectedIndex: selected,
            ),
            size: Size(w, h),
          ),
        );
      },
    );
  }
}

class _LineChartPainter extends CustomPainter {
  final String title;
  final String unit;
  final double yStep;
  final List<_DayPoint> points;
  final double minY;
  final double maxY;
  final int? selectedIndex;

  _LineChartPainter({
    required this.title,
    required this.unit,
    required this.yStep,
    required this.points,
    required this.minY,
    required this.maxY,
    required this.selectedIndex,
  });

  DateTime _day(DateTime d) => DateTime(d.year, d.month, d.day);

  double _floorTo(double v, double step) {
    if (step <= 0) return v;
    return (v / step).floorToDouble() * step;
  }

  double _ceilTo(double v, double step) {
    if (step <= 0) return v;
    return (v / step).ceilToDouble() * step;
  }

  int _niceDayStep(int spanDays) {
    if (spanDays <= 7) return 1;
    if (spanDays <= 14) return 2;
    if (spanDays <= 31) return 7;
    if (spanDays <= 90) return 14;
    if (spanDays <= 180) return 30;
    if (spanDays <= 365) return 60;
    return 90;
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    TextAlign align = TextAlign.left,
    FontWeight weight = FontWeight.w700,
    double size = 11,
    Color color = const Color(0x99000000),
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: size, fontWeight: weight, color: color),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
      maxLines: 1,
    )..layout();
    tp.paint(canvas, offset);
  }

  Path _smoothPath(List<Offset> pts) {
    if (pts.length < 2) return Path();

    final path = Path()..moveTo(pts.first.dx, pts.first.dy);
    if (pts.length == 2) {
      path.lineTo(pts[1].dx, pts[1].dy);
      return path;
    }

    for (int i = 0; i < pts.length - 1; i++) {
      final p0 = i == 0 ? pts[i] : pts[i - 1];
      final p1 = pts[i];
      final p2 = pts[i + 1];
      final p3 = (i + 2 < pts.length) ? pts[i + 2] : p2;

      final c1 = Offset(
        p1.dx + (p2.dx - p0.dx) / 6.0,
        p1.dy + (p2.dy - p0.dy) / 6.0,
      );
      final c2 = Offset(
        p2.dx - (p3.dx - p1.dx) / 6.0,
        p2.dy - (p3.dy - p1.dy) / 6.0,
      );

      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p2.dx, p2.dy);
    }

    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    const leftPad = 44.0;
    const topPad = 26.0;
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

    if (points.length < 2) return;

    final safeStep = yStep <= 0 ? 1.0 : yStep;
    final yMin = _floorTo(minY, safeStep);
    final yMax = _ceilTo(maxY, safeStep);
    final ySpan = (yMax - yMin).abs() < 1 ? 1.0 : (yMax - yMin);

    final firstDay = _day(points.first.day);
    final lastDay = _day(points.last.day);
    final spanDays = lastDay.difference(firstDay).inDays;
    final xSpanDays = spanDays <= 0 ? 1 : spanDays;

    Offset pt(int i) {
      final d = _day(points[i].day);
      final xFrac = d.difference(firstDay).inDays / xSpanDays;
      final yFrac = (points[i].avg - yMin) / ySpan;
      final x = plot.left + xFrac * plot.width;
      final y = plot.bottom - yFrac * plot.height;
      return Offset(x, y);
    }

    final grid = Paint()
      ..color = const Color(0x14000000)
      ..strokeWidth = 1;

    // Horizontal grid + y labels
    for (double y = yMin; y <= yMax + 0.0001; y += safeStep) {
      final frac = (y - yMin) / ySpan;
      final yy = plot.bottom - frac * plot.height;
      canvas.drawLine(Offset(plot.left, yy), Offset(plot.right, yy), grid);

      _drawText(
        canvas,
        y.toStringAsFixed(0),
        Offset(8, yy - 6),
        align: TextAlign.right,
      );
    }

    // Vertical grid + x labels
    final dayStep = _niceDayStep(spanDays);
    for (int dd = 0; dd <= xSpanDays; dd += dayStep) {
      final d = firstDay.add(Duration(days: dd));
      final xFrac = dd / xSpanDays;
      final xx = plot.left + xFrac * plot.width;
      canvas.drawLine(Offset(xx, plot.top), Offset(xx, plot.bottom), grid);

      final labelFmt = spanDays <= 14
          ? DateFormat('d MMM')
          : DateFormat('d MMM');
      final label = labelFmt.format(d);
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.w800,
            color: Color(0x99000000),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      var x = xx - tp.width / 2;
      x = x.clamp(plot.left, plot.right - tp.width);
      tp.paint(canvas, Offset(x, plot.bottom + 6));
    }

    final line = Paint()
      ..color = const Color(0xFF2F66E3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    final offsets = <Offset>[];
    for (int i = 0; i < points.length; i++) {
      offsets.add(pt(i));
    }

    final smooth = _smoothPath(offsets);
    canvas.drawPath(smooth, line);

    final dot = Paint()..color = const Color(0xFF2F66E3);
    for (int i = 0; i < points.length; i++) {
      final p = pt(i);
      canvas.drawCircle(p, 2.5, dot);
    }

    // Title + axes context
    _drawText(
      canvas,
      title,
      const Offset(12, 4),
      weight: FontWeight.w900,
      size: 13,
      color: const Color(0xDD000000),
    );
    _drawText(
      canvas,
      unit,
      Offset(12, topPad + 2),
      weight: FontWeight.w800,
      size: 10,
      color: const Color(0x88000000),
    );

    // (y labels + grid + x labels drawn above)

    if (selectedIndex != null) {
      final i = selectedIndex!.clamp(0, points.length - 1);
      final p = pt(i);

      final cross = Paint()
        ..color = const Color(0x552F66E3)
        ..strokeWidth = 1;
      canvas.drawLine(Offset(p.dx, plot.top), Offset(p.dx, plot.bottom), cross);

      final sel = Paint()..color = const Color(0xFF2F66E3);
      canvas.drawCircle(p, 5, sel);

      final fmt = DateFormat('d MMM');
      final label =
          '${fmt.format(points[i].day)}  ${points[i].avg.toStringAsFixed(1)}';

      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: Color(0xFF222222),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      final bubblePad = 6.0;
      var bx = p.dx - tp.width / 2;
      bx = bx.clamp(plot.left, plot.right - tp.width);
      final by = (plot.top - tp.height - 10).clamp(0, plot.top - 2);

      final bubble = Rect.fromLTWH(
        bx - bubblePad,
        by - bubblePad,
        tp.width + bubblePad * 2,
        tp.height + bubblePad * 2,
      );

      final bubblePaint = Paint()..color = Colors.white;
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubble, const Radius.circular(8)),
        bubblePaint,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(bubble, const Radius.circular(8)),
        axis,
      );

      tp.paint(canvas, Offset(bubble.left + bubblePad, bubble.top + bubblePad));
    }
  }

  @override
  bool shouldRepaint(covariant _LineChartPainter oldDelegate) {
    return oldDelegate.title != title ||
        oldDelegate.unit != unit ||
        oldDelegate.yStep != yStep ||
        oldDelegate.points != points ||
        oldDelegate.minY != minY ||
        oldDelegate.maxY != maxY ||
        oldDelegate.selectedIndex != selectedIndex;
  }
}
