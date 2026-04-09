import 'package:flutter/material.dart';

class InstructionsScreen extends StatelessWidget {
  const InstructionsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('How to use Pasture Walk')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          _H1('1) Setup'),
          _H2('Add paddocks'),
          _Bullets([
            'Go to Paddocks and add paddocks (name + area).',
            'If you already have a list, use Import to load paddocks quickly.',
          ]),
          _H2('Set recording order & exclusions'),
          _Bullets([
            'Open Recording order to set the order you will walk paddocks in.',
            'Turn Include in rotation OFF for paddocks that are cropped or should not affect farm averages.',
            'Excluded paddocks will not appear in Recording and are ignored in Summary calculations.',
          ]),

          _H1('2) Record covers (Start / Resume Recording)'),
          _P(
            'From Home, tap Start / Resume Recording and walk paddocks in your Recording Order.',
          ),
          _Bullets([
            'Tap the left half of the screen to decrease cover, and the right half to increase cover (step size is set in Settings).',
            'Swipe left/right to move to the next/previous paddock (the current paddock is saved automatically before moving).',
            'Long-press anywhere to open the notes sheet.',
            'Tap the paddock header to jump directly to any paddock.',
            'Last cover shows the last recorded cover + how long ago it was.',
            'Predicted is the estimate for today based on the latest anchor and growth calculations.',
            'Notes: use the top note buttons (2 presets + Custom) to add dated notes for the current paddock.',
            'Finish saves the current paddock and returns to Home.',
          ]),

          _H1('3) Home screen (Summary + Paddocks tabs)'),
          _H2('Summary tab'),
          _Bullets([
            'Shows farm KPIs, the feed wedge, and recent notes.',
            'Average cover uses included paddocks only.',
            'You can clear notes from the Summary list (notes remain in paddock history).',
          ]),
          _H2('Paddocks tab'),
          _Bullets([
            'Shows paddocks with Area, last Recorded cover, and Predicted cover for today.',
            'Tap a paddock to open its History (Covers / Grazings / Notes).',
            'Long-press paddocks to enter selection mode (used for grazing entry).',
          ]),

          _H1('4) Paddock history + notes'),
          _Bullets([
            'Covers tab: all recorded covers over time.',
            'Grazings tab: grazing events (pre, residual, harvested).',
            'Notes tab: notes you add during recording (e.g. weeds, leaks).',
          ]),
          _H2('Notes buttons'),
          _P(
            'You can rename the two preset note buttons in Settings (e.g. “Weeds”, “Water leak”).',
          ),

          _H1('5) Enter grazings'),
          _P(
            'From Home → Paddocks tab, long-press a paddock to enter selection mode, select one or more paddocks, set the residual, then Save grazing.',
          ),
          _Bullets([
            'Pre cover is the paddock’s predicted cover at the time you save the grazing.',
            'Residual is what you entered in the grazing bar.',
            'Harvested kgDM = (pre - residual) × area.',
            'Undo grazing removes grazings saved in the last 24 hours for selected paddocks.',
          ]),

          _H1('6) Backup & restore'),
          _Bullets([
            'Backup saves everything (paddocks, order, settings, covers, grazings, notes) to a .json file.',
            'Restore overwrites the current device’s data with the backup file.',
            'Keep backups somewhere safe (Drive, USB, etc.).',
          ]),

          _H1('Tips'),
          _Bullets([
            'Record covers regularly (weekly is good) so the app has enough data to calculate growth.',
            'Log grazings when you shift stock so predictions reset off residuals properly.',
            'Exclude cropped paddocks so they don’t skew averages.',
          ]),
        ],
      ),
    );
  }
}

// ---------- simple text widgets ----------
class _H1 extends StatelessWidget {
  final String text;
  const _H1(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900),
      ),
    );
  }
}

class _H2 extends StatelessWidget {
  final String text;
  const _H2(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Text(
        text,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _P extends StatelessWidget {
  final String text;
  const _P(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: const TextStyle(fontSize: 14, height: 1.35)),
    );
  }
}

class _Bullets extends StatelessWidget {
  final List<String> items;
  const _Bullets(this.items);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        children: [
          for (final s in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '•  ',
                    style: TextStyle(fontSize: 14, height: 1.35),
                  ),
                  Expanded(
                    child: Text(
                      s,
                      style: const TextStyle(fontSize: 14, height: 1.35),
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
