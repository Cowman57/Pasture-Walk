import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../storage.dart';
import 'instructions_screen.dart';
import 'paddock_import_screen.dart';
import 'paddock_ranking_screen.dart';
import 'paddocks_edit_screen.dart';
import 'recording_order_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final storage = Storage();

  int coverStep = 50;
  String noteBtn1 = 'Weeds';
  String noteBtn2 = 'Water leak';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await storage.loadCoverStep();
    final b1 = await storage.loadNoteButton1Title();
    final b2 = await storage.loadNoteButton2Title();
    if (!mounted) return;
    setState(() {
      coverStep = s;
      noteBtn1 = b1;
      noteBtn2 = b2;
    });
  }

  Future<void> _editCoverStep() async {
    final picked = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Cover adjust step'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 50),
            child: const Text('50 kgDM/ha'),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 100),
            child: const Text('100 kgDM/ha'),
          ),
        ],
      ),
    );

    if (picked == null) return;

    await storage.saveCoverStep(picked);
    await _load();
  }

  Future<void> _editNoteTitle({required int which}) async {
    final start = which == 1 ? noteBtn1 : noteBtn2;
    final ctrl = TextEditingController(text: start);

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(which == 1 ? 'Note button 1 title' : 'Note button 2 title'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Button title',
            helperText: 'This text is saved as the note',
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

    final t = ctrl.text.trim();
    if (which == 1) {
      await storage.saveNoteButton1Title(t);
    } else {
      await storage.saveNoteButton2Title(t);
    }
    await _load();
  }

  Future<void> _backup() async {
    try {
      final jsonText = await storage.exportBackupJson();
      final bytes = Uint8List.fromList(utf8.encode(jsonText));

      final now = DateTime.now();
      final stamp =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}${now.minute.toString().padLeft(2, '0')}';

      await FilePicker.platform.saveFile(
        dialogTitle: 'Save backup',
        fileName: 'PastureWalk_backup_$stamp.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: bytes,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Backup saved')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Backup failed: $e')));
    }
  }

  Future<void> _restore() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore backup?'),
        content: const Text(
          'This will overwrite all current data on this phone.\n\n'
          'Make sure you have a backup first.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (ok != true) return;

    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
        withData: true,
      );

      if (result == null || result.files.isEmpty) return;

      final file = result.files.single;
      final bytes = file.bytes;
      if (bytes == null) throw Exception('Could not read file data');

      final text = utf8.decode(bytes);
      await storage.restoreBackupJson(text);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Restore complete. Go back to Home to refresh.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Restore failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          const _SectionHeader('Backup'),
          ListTile(
            leading: const Icon(Icons.backup),
            title: const Text('Backup'),
            subtitle: const Text('Save all data to a file'),
            onTap: _backup,
          ),
          ListTile(
            leading: const Icon(Icons.restore),
            title: const Text('Restore backup'),
            subtitle: const Text('Load data from a backup file'),
            onTap: _restore,
          ),

          const Divider(height: 32),

          const _SectionHeader('Recording'),
          ListTile(
            leading: const Icon(Icons.exposure_plus_2),
            title: const Text('Cover adjust step'),
            subtitle: Text('$coverStep kgDM/ha'),
            onTap: _editCoverStep,
          ),

          const Divider(height: 32),

          const _SectionHeader('Notes'),
          ListTile(
            leading: const Icon(Icons.note_alt_outlined),
            title: const Text('Note button 1 title'),
            subtitle: Text(noteBtn1),
            onTap: () => _editNoteTitle(which: 1),
          ),
          ListTile(
            leading: const Icon(Icons.note_alt_outlined),
            title: const Text('Note button 2 title'),
            subtitle: Text(noteBtn2),
            onTap: () => _editNoteTitle(which: 2),
          ),

          const Divider(height: 32),

          const _SectionHeader('Paddocks'),
          ListTile(
            leading: const Icon(Icons.file_upload),
            title: const Text('Import paddocks'),
            subtitle: const Text('Import GeoJSON paddocks'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaddockImportScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.grass),
            title: const Text('Add / edit paddocks'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaddocksEditScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.swap_vert),
            title: const Text('Recording order'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RecordingOrderScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.emoji_events),
            title: const Text('Rankings'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const PaddockRankingScreen()),
            ),
          ),

          const Divider(height: 32),

          const _SectionHeader('Help'),
          ListTile(
            leading: const Icon(Icons.help_outline),
            title: const Text('Instructions'),
            subtitle: const Text(
              'How it works, how to use it, growth calculations',
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const InstructionsScreen()),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: Colors.black54,
        ),
      ),
    );
  }
}
