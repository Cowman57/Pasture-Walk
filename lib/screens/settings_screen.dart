import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../storage.dart';
import 'instructions_screen.dart';
import 'farm_map_import_screen.dart';
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
  bool gpsMeasuring = false;
  String _versionText = '';
  bool _updateAvailable = false;
  String? _latestVersion;
  String? _latestUrl;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final infoFuture = PackageInfo.fromPlatform();
    final s = await storage.loadCoverStep();
    final b1 = await storage.loadNoteButton1Title();
    final b2 = await storage.loadNoteButton2Title();
    final gps = await storage.loadGpsMeasuringEnabled();
    final info = await infoFuture;
    if (!mounted) return;
    setState(() {
      coverStep = s;
      noteBtn1 = b1;
      noteBtn2 = b2;
      gpsMeasuring = gps;
      _versionText = 'v${info.version}';
    });

    await _checkForUpdate(currentVersion: info.version);
  }

  static List<int> _parseSemver(String v) {
    final cleaned = v.trim().toLowerCase().startsWith('v')
        ? v.trim().substring(1)
        : v.trim();
    final main = cleaned.split('-').first;
    final parts = main.split('.');
    int partAt(int i) {
      if (i >= parts.length) return 0;
      return int.tryParse(parts[i].replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
    }

    return <int>[partAt(0), partAt(1), partAt(2)];
  }

  static int _compareSemver(String a, String b) {
    final pa = _parseSemver(a);
    final pb = _parseSemver(b);
    for (int i = 0; i < 3; i++) {
      final d = pa[i] - pb[i];
      if (d != 0) return d;
    }
    return 0;
  }

  Future<void> _checkForUpdate({required String currentVersion}) async {
    try {
      final uri = Uri.parse(
        'https://api.github.com/repos/Cowman57/Pasture-Walk/releases/latest',
      );
      final resp = await http.get(
        uri,
        headers: const {'Accept': 'application/vnd.github+json'},
      );

      if (resp.statusCode < 200 || resp.statusCode >= 300) return;

      final data = jsonDecode(resp.body);
      if (data is! Map) return;

      final tag = data['tag_name'];
      final url = data['html_url'];
      if (tag is! String || tag.trim().isEmpty) return;
      if (url is! String || url.trim().isEmpty) return;

      final newer = _compareSemver(tag, currentVersion) > 0;
      if (!mounted) return;
      setState(() {
        _latestVersion = tag.trim();
        _latestUrl = url.trim();
        _updateAvailable = newer;
      });
    } catch (_) {
      return;
    }
  }

  Future<void> _openLatestRelease() async {
    final url = _latestUrl;
    if (url == null || url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

      final paddocks = await storage.loadPaddocks();
      final measurements = await storage.loadAllMeasurements();
      final grazingsBefore = await storage.loadAllGrazings();
      final notes = await storage.loadAllNotes();

      DateTime? minDate;
      DateTime? maxDate;
      void consider(DateTime d) {
        if (minDate == null || d.isBefore(minDate!)) minDate = d;
        if (maxDate == null || d.isAfter(maxDate!)) maxDate = d;
      }

      for (final m in measurements) {
        consider(m.at);
      }
      for (final g in grazingsBefore) {
        consider(g.at);
      }

      final cleanup = await storage.cleanupDuplicateGrazingsAllPaddocks();
      final grazingsAfter = await storage.loadAllGrazings();

      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          String fmtDate(DateTime d) {
            final dd = d.day.toString().padLeft(2, '0');
            final mm = d.month.toString().padLeft(2, '0');
            return '${d.year}-$mm-$dd';
          }

          final rangeText = (minDate == null || maxDate == null)
              ? '—'
              : '${fmtDate(minDate!)} → ${fmtDate(maxDate!)}';

          return AlertDialog(
            title: const Text('Restore summary'),
            content: Text(
              'Paddocks: ${paddocks.length}\n'
              'Measurements: ${measurements.length}\n'
              'Grazings: ${grazingsBefore.length}\n'
              'Notes: ${notes.length}\n'
              '\n'
              'Date range: $rangeText\n'
              '\n'
              'Duplicate grazings deleted: ${cleanup.deletedGrazings}\n'
              'Affected paddocks: ${cleanup.affectedPaddocks}\n'
              'Grazings after cleanup: ${grazingsAfter.length}',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );

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
          SwitchListTile(
            secondary: const Icon(Icons.my_location),
            title: const Text('GPS measuring'),
            subtitle: const Text(
              'Auto-select the paddock you are in when recording covers (requires a farm map).',
            ),
            value: gpsMeasuring,
            onChanged: (v) async {
              setState(() => gpsMeasuring = v);
              await storage.saveGpsMeasuringEnabled(v);
            },
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
            title: const Text('Import paddocks + map'),
            subtitle: const Text('GeoJSON polygons or Shapefile zip'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const FarmMapImportScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.table_view),
            title: const Text('Import paddocks (CSV)'),
            subtitle: const Text('Names and areas only (no map)'),
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

          const Divider(height: 32),

          const _SectionHeader('About'),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_versionText.isEmpty ? '-' : _versionText),
          ),
          if (_updateAvailable)
            ListTile(
              leading: const Icon(Icons.system_update_alt),
              title: const Text('Update available'),
              subtitle: Text(
                _latestVersion == null
                    ? 'Tap to open the latest release'
                    : 'Latest: ${_latestVersion!}',
              ),
              onTap: _openLatestRelease,
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
