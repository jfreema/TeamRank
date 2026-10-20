/// Travel-ball seasons run from August 1 through July 31. Fall ball belongs
/// to the next year's season, because players are already at their new age.
class Season {
  Season(this.start, this.end);

  /// The season that [day] falls in.
  factory Season.containing(DateTime day) {
    final startYear = day.month >= 8 ? day.year : day.year - 1;
    return Season(DateTime(startYear, 8, 1), DateTime(startYear + 1, 7, 31));
  }

  final DateTime start;
  final DateTime end;

  /// For example `2026-27`.
  String get label =>
      '${start.year}-${(start.year + 1).toString().substring(2)}';

  bool contains(DateTime d) => !d.isBefore(start) && !d.isAfter(end);
}

String isoDate(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// An event is final once a couple of days have passed since it ended, which
/// leaves time for late score corrections.
bool isEventFinal(String endDate, DateTime today) {
  final end = DateTime.tryParse(endDate);
  if (end == null) return false;
  return today.difference(end).inDays >= 3;
}
