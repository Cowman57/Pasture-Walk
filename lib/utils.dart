int clampCover(int v) {
  // sensible bounds (adjust if you want)
  if (v < 1200) return 1200;
  if (v > 4500) return 4500;
  return v;
}

String daysAgoLabel(DateTime now, DateTime then) {
  final diff = now.difference(then);
  final days = diff.inDays;
  if (days <= 0) return "today";
  if (days == 1) return "yesterday";
  return "$days days ago";
}

/// Simple thousands separator without intl (e.g. 1234567 -> 1,234,567)
String formatIntWithCommas(int n) {
  final s = n.toString();
  final buf = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final idxFromEnd = s.length - i;
    buf.write(s[i]);
    if (idxFromEnd > 1 && idxFromEnd % 3 == 1) buf.write(',');
  }
  return buf.toString();
}

DateTime calendarDay(DateTime d) => DateTime(d.year, d.month, d.day);

/// Spreads a grazing's area / harvest across its [durationDays] for daily charts.
void forEachGrazingAllocationDay(
  DateTime at,
  int durationDays, {
  required double areaHa,
  required double harvestedKgDm,
  required void Function(DateTime day, double areaHa, double harvestedKgDm) fn,
}) {
  final start = calendarDay(at);
  final days = durationDays < 1 ? 1 : durationDays;
  final areaShare = areaHa / days;
  final harvestShare = harvestedKgDm / days;
  for (var i = 0; i < days; i++) {
    // Calendar-add so a run never drifts/skips across a DST change.
    fn(
      DateTime(start.year, start.month, start.day + i),
      areaShare,
      harvestShare,
    );
  }
}
