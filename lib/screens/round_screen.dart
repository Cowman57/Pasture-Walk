import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';
import '../utils.dart';

class RoundScreen extends StatefulWidget {
  const RoundScreen({super.key});

  @override
  State<RoundScreen> createState() => _RoundScreenState();
}

class _RoundScreenState extends State<RoundScreen> {
  final storage = Storage();
  final uuid = const Uuid();

  bool loaded = false;

  List<Paddock> order = [];
  int idx = 0;

  // Predicted "now" per paddock when screen was opened
  final Map<String, int> predictedNow = {};

  // Last recorded measurement per paddock
  final Map<String, Measurement?> lastMeasured = {};

  // Growth
  double farmGrowth = 0.0;
  Map<String, double> mods = {};

  // Editable value
  int currentCover = 2500;

  // +/- step amount (settings)
  int step = 50;

  // note buttons (settings)
  String noteBtn1 = 'Weeds';
  String noteBtn2 = 'Water leak';

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    step = await storage.loadCoverStep();
    noteBtn1 = await storage.loadNoteButton1Title();
    noteBtn2 = await storage.loadNoteButton2Title();

    var all = await storage.loadPaddocks();
    all.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));

    // Exclude paddocks not included in rotation
    order = all.where((p) => p.includeInRotation).toList();

    mods = await storage.loadGrowthModifiers();
    farmGrowth = await storage.computeFarmGrowthKgDmPerHaPerDay();

    final now = DateTime.now();

    for (final p in order) {
      final lm = await storage.lastMeasurementForPaddock(p.id);
      lastMeasured[p.id] = lm;

      final anchor = await storage.latestAnchorForPaddock(p.id);
      final base = anchor?.coverKgDmHa ?? 2500;
      final days = anchor == null ? 0 : now.difference(anchor.at).inDays;

      final mod = mods[p.id] ?? 1.0;
      final gEff = farmGrowth * mod;

      predictedNow[p.id] = clampCover(base + (days * gEff).round());
    }

    if (order.isNotEmpty) {
      currentCover = predictedNow[order[idx].id] ?? 2500;
    }

    loaded = true;
    setState(() {});
  }

  Paddock get _p => order[idx];
  int get _pred => predictedNow[_p.id] ?? 2500;
  Measurement? get _last => lastMeasured[_p.id];
  double get _mod => mods[_p.id] ?? 1.0;
  double get _gEff => farmGrowth * _mod;

  Future<void> _saveCurrent() async {
    final m = Measurement(
      id: uuid.v4(),
      paddockId: _p.id,
      at: DateTime.now(),
      cover: currentCover,
      predictedCoverAtEntry: _pred,
    );

    await storage.upsertMeasurementForToday(m);
    lastMeasured[_p.id] = m;
  }

  Future<void> _addNote(String title) async {
    final n = NoteEntry(
      id: uuid.v4(),
      paddockId: _p.id,
      at: DateTime.now(),
      title: title,
    );
    await storage.appendNote(n);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Note added: $title')),
    );
  }

  Future<void> _finish() async {
    await _saveCurrent();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  Future<void> _next() async {
    await _saveCurrent();
    if (idx < order.length - 1) {
      setState(() {
        idx++;
        currentCover = predictedNow[_p.id] ?? currentCover;
      });
    }
  }

  Future<void> _prev() async {
    await _saveCurrent();
    if (idx > 0) {
      setState(() {
        idx--;
        currentCover = predictedNow[_p.id] ?? currentCover;
      });
    }
  }

  void _skip() {
    if (idx < order.length - 1) {
      setState(() {
        idx++;
        currentCover = predictedNow[_p.id] ?? currentCover;
      });
    }
  }

  void _adjust(int delta) {
    setState(() {
      currentCover = clampCover(currentCover + delta);
    });
  }

  Future<void> _enterExact() async {
    final ctrl = TextEditingController(text: currentCover.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enter cover'),
        content: TextField(
          controller: ctrl,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            isDense: true,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;
    final v = int.tryParse(ctrl.text.trim());
    if (v != null) {
      setState(() => currentCover = clampCover(v));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!loaded) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (order.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Record covers')),
        body: const Center(
          child: Text('No paddocks included in rotation.\nEnable them in Settings → Recording order.'),
        ),
      );
    }

    final now = DateTime.now();
    final lastCoverText = _last == null ? '—' : _last!.cover.toString();
    final lastDaysAgo = _last == null ? '—' : daysAgoLabel(now, _last!.at);

    final growthLine =
        '${_gEff.toStringAsFixed(1)}/day (${farmGrowth.toStringAsFixed(1)} × ${_mod.toStringAsFixed(2)})';

    return Scaffold(
      appBar: AppBar(title: const Text('Record covers')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Paddock ${_p.name}',
                style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 10),

              // Top cards
              Row(
                children: [
                  Expanded(
                    child: _InfoCard(
                      title: 'Last cover',
                      value: lastCoverText,
                      unit: 'kgDM/ha',
                      meta: lastDaysAgo,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _InfoCard(
                      title: 'Predicted',
                      value: _pred.toString(),
                      unit: 'kgDM/ha',
                      meta: growthLine,
                    ),
                  ),
                ],
              ),

              // ✅ Note buttons under the cards
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => _addNote(noteBtn1),
                        child: Text(noteBtn1, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => _addNote(noteBtn2),
                        child: Text(noteBtn2, maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ),
                ],
              ),

              const Spacer(),

              InkWell(
                onTap: _enterExact,
                child: Column(
                  children: [
                    Text(
                      currentCover.toString(),
                      style: const TextStyle(fontSize: 78, fontWeight: FontWeight.w900),
                    ),
                    const Text('kgDM/ha', style: TextStyle(fontSize: 14, color: Colors.black54)),
                  ],
                ),
              ),

              const Spacer(),

              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: OutlinedButton(
                        onPressed: () => _adjust(-step),
                        child: Text('- $step', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 60,
                      child: OutlinedButton(
                        onPressed: () => _adjust(step),
                        child: Text('+ $step', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              // Previous / Skip / Next OR Finish
              Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 72,
                      child: ElevatedButton(
                        onPressed: idx == 0 ? null : _prev,
                        child: const Text(
                          'Previous',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 56,
                    height: 56,
                    child: OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        shape: const CircleBorder(),
                        padding: EdgeInsets.zero,
                      ),
                      onPressed: idx == order.length - 1 ? null : _skip,
                      child: const Text(
                        'Skip',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 72,
                      child: ElevatedButton(
                        onPressed: idx == order.length - 1 ? _finish : _next,
                        child: Text(
                          idx == order.length - 1 ? 'Finish' : 'Next',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String title;
  final String value;
  final String unit;
  final String meta;

  const _InfoCard({
    required this.title,
    required this.value,
    required this.unit,
    required this.meta,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Colors.black.withOpacity(0.04),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 12, color: Colors.black54, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(value, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 2),
                  child: Text(unit, style: const TextStyle(fontSize: 11, color: Colors.black54, fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              meta,
              style: const TextStyle(fontSize: 11, color: Colors.black45, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
