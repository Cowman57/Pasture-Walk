import 'package:flutter/material.dart';

import '../models.dart';
import '../storage.dart';

class RecordingOrderScreen extends StatefulWidget {
  const RecordingOrderScreen({super.key});

  @override
  State<RecordingOrderScreen> createState() => _RecordingOrderScreenState();
}

class _RecordingOrderScreenState extends State<RecordingOrderScreen> {
  final storage = Storage();

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

  Future<void> _saveAll() async {
    await storage.savePaddocks(paddocks);
  }

  Future<void> _saveOrderOnly() async {
    // Keep everything the same, just rewrite recordOrder based on current list order.
    final updated = <Paddock>[];
    for (int i = 0; i < paddocks.length; i++) {
      final p = paddocks[i];
      updated.add(Paddock(
        id: p.id,
        name: p.name,
        areaHa: p.areaHa,
        recordOrder: i + 1,
        includeInRotation: p.includeInRotation,
      ));
    }
    paddocks = updated;
    await _saveAll();
  }

  void _toggleInclude(String paddockId, bool include) async {
    final i = paddocks.indexWhere((p) => p.id == paddockId);
    if (i < 0) return;

    setState(() {
      final p = paddocks[i];
      paddocks[i] = Paddock(
        id: p.id,
        name: p.name,
        areaHa: p.areaHa,
        recordOrder: p.recordOrder,
        includeInRotation: include,
      );
    });

    await _saveAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Recording order')),
      body: !loaded
          ? const Center(child: CircularProgressIndicator())
          : ReorderableListView.builder(
        itemCount: paddocks.length,
        onReorder: (oldIndex, newIndex) async {
          setState(() {
            if (newIndex > oldIndex) newIndex -= 1;
            final item = paddocks.removeAt(oldIndex);
            paddocks.insert(newIndex, item);
          });
          await _saveOrderOnly();
        },
        itemBuilder: (ctx, i) {
          final p = paddocks[i];
          return ListTile(
            key: ValueKey(p.id),
            title: Text(p.name),
            subtitle: Text('Include in rotation'),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: p.includeInRotation,
                  onChanged: (v) => _toggleInclude(p.id, v ?? true),
                ),
                const Icon(Icons.drag_handle),
              ],
            ),
          );
        },
      ),
    );
  }
}
