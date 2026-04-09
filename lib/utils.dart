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
