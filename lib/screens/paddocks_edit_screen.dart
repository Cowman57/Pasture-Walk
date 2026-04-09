import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';
import '../storage.dart';

class PaddocksEditScreen extends StatefulWidget {
  const PaddocksEditScreen({super.key});

  @override
  State<PaddocksEditScreen> createState() => _PaddocksEditScreenState();
}

class _PaddocksEditScreenState extends State<PaddocksEditScreen> {
  final storage = Storage();
  final uuid = const Uuid();

  bool loaded = false;
  List<Paddock> paddocks = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    paddocks = await storage.loadPaddocks();
    paddocks.sort((a, b) => a.recordOrder.compareTo(b.recordOrder));
    loaded = true;
    setState(() {});
  }

  Future<void> _persist() async {
    await storage.savePaddocks(paddocks);
  }

  Future<void> _addOrEdit({Paddock? existing}) async {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final areaCtrl = TextEditingController(text: existing == null ? '' : existing.areaHa.toStringAsFixed(1));

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(existing == null ? 'Add paddock' : 'Edit paddock'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Paddock name/number'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: areaCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Area (ha)'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );

    if (ok != true) return;

    final name = nameCtrl.text.trim();
    final area = double.tryParse(areaCtrl.text.trim()) ?? 0.0;
    if (name.isEmpty) return;

    if (existing == null) {
      final nextOrder = paddocks.isEmpty
          ? 0
          : (paddocks.map((p) => p.recordOrder).reduce((a, b) => a > b ? a : b) + 1);

      paddocks.add(Paddock(
        id: uuid.v4(),
        name: name,
        areaHa: area,
        recordOrder: nextOrder,
        includeInRotation: true,
      ));
    } else {
      final i = paddocks.indexWhere((p) => p.id == existing.id);
      if (i >= 0) {
        paddocks[i] = Paddock(
          id: existing.id,
          name: name,
          areaHa: area,
          recordOrder: existing.recordOrder,
          includeInRotation: existing.includeInRotation,
        );
      }
    }

    await _persist();
    setState(() {});
  }

  Future<void> _delete(Paddock p) async {
    paddocks.removeWhere((x) => x.id == p.id);
    await _persist();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Paddocks'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => _addOrEdit(),
          ),
        ],
      ),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView.separated(
        itemCount: paddocks.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (ctx, i) {
          final p = paddocks[i];
          return ListTile(
            title: Text(p.name),
            subtitle: Text('${p.areaHa.toStringAsFixed(1)} ha'),
            onTap: () => _addOrEdit(existing: p),
            trailing: IconButton(
              icon: const Icon(Icons.delete_outline),
              onPressed: () => _delete(p),
            ),
          );
        },
      ),
    );
  }
}
