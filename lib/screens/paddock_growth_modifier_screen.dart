import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';

class PaddockGrowthModifierScreen extends StatefulWidget {
  const PaddockGrowthModifierScreen({super.key});

  @override
  State<PaddockGrowthModifierScreen> createState() =>
      _PaddockGrowthModifierScreenState();
}

class _PaddockGrowthModifierScreenState
    extends State<PaddockGrowthModifierScreen> {
  final storage = Storage();

  bool loaded = false;
  List<Paddock> paddocks = [];
  Map<String, double> modifiers = {};

  String sortCol = 'paddock';
  bool sortAsc = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    paddocks = await storage.loadPaddocks();
    modifiers = await storage.loadGrowthModifiers();
    paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    loaded = true;
    setState(() {});
  }

  double _modFor(String paddockId) => modifiers[paddockId] ?? 1.0;

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

  void _sort(List<Paddock> list) {
    list.sort((a, b) {
      int cmp;
      if (sortCol == 'modifier') {
        cmp = _modFor(a.id).compareTo(_modFor(b.id));
      } else {
        cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      }
      return sortAsc ? cmp : -cmp;
    });
  }

  Future<void> _editModifier(Paddock p) async {
    final start = _modFor(p.id);
    final ctrl = TextEditingController(text: start.toStringAsFixed(2));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Paddock ${p.name}'),
        content: TextField(
          controller: ctrl,
          keyboardType:
          const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Growth modifier',
            helperText: '1.00 = average, >1 grows faster, <1 slower',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    final v = double.tryParse(ctrl.text.trim());
    if (v == null) return;

    modifiers[p.id] = v.clamp(0.5, 1.5);

    await storage.saveGrowthModifiers(modifiers);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paddock growth modifiers'),
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : Column(
        children: [
          _header(),
          const Divider(height: 1),
          Expanded(child: _list()),
        ],
      ),
    );
  }

  Widget _header() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: _hdrCell(
              'Paddock',
              col: 'paddock',
            ),
          ),
          Expanded(
            child: _hdrCell(
              'Modifier',
              col: 'modifier',
              center: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _hdrCell(String label,
      {required String col, bool center = false}) {
    final isSorted = sortCol == col;
    final arrow = isSorted ? (sortAsc ? ' ▲' : ' ▼') : '';

    return InkWell(
      onTap: () => _toggleSort(col),
      child: Text(
        '$label$arrow',
        textAlign: center ? TextAlign.center : TextAlign.left,
        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w800,
          color: Colors.black87,
        ),
      ),
    );
  }

  Widget _list() {
    final list = [...paddocks];
    _sort(list);

    if (list.isEmpty) {
      return const Center(child: Text('No paddocks defined.'));
    }

    return ListView.separated(
      itemCount: list.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (ctx, i) {
        final p = list[i];
        final mod = _modFor(p.id);

        return InkWell(
          onTap: () => _editModifier(p),
          child: Padding(
            padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    p.name,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Expanded(
                  child: Text(
                    mod.toStringAsFixed(2),
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
