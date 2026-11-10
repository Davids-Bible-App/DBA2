import 'package:flutter/foundation.dart';

/// Immutable streak record. Dates are stored as local "YYYY-MM-DD" strings,
/// exactly like the SolidJS version, so the JSON shape is identical.
@immutable
class StreakData {
  const StreakData({
    this.firstDate,
    this.currentDate,
    this.currentStreak = 0,
    this.longestStreak = 0,
    this.longestStreakStartDate,
    this.longestStreakEndDate,
  });

  final String? firstDate;
  final String? currentDate;
  final int currentStreak;
  final int longestStreak;
  final String? longestStreakStartDate;
  final String? longestStreakEndDate;

  static const empty = StreakData();

  /// Shallow validation with safe defaults (same idea as loadStreak()).
  factory StreakData.fromJson(Map<String, dynamic> json) {
    String? str(String k) => json[k] is String ? json[k] as String : null;
    int count(String k) {
      final v = json[k];
      return v is int && v >= 0 ? v : 0;
    }

    return StreakData(
      firstDate: str('firstDate'),
      currentDate: str('currentDate'),
      currentStreak: count('currentStreak'),
      longestStreak: count('longestStreak'),
      longestStreakStartDate: str('longestStreakStartDate'),
      longestStreakEndDate: str('longestStreakEndDate'),
    );
  }

  Map<String, dynamic> toJson() => {
    'firstDate': firstDate,
    'currentDate': currentDate,
    'currentStreak': currentStreak,
    'longestStreak': longestStreak,
    'longestStreakStartDate': longestStreakStartDate,
    'longestStreakEndDate': longestStreakEndDate,
  };

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is StreakData &&
          other.firstDate == firstDate &&
          other.currentDate == currentDate &&
          other.currentStreak == currentStreak &&
          other.longestStreak == longestStreak &&
          other.longestStreakStartDate == longestStreakStartDate &&
          other.longestStreakEndDate == longestStreakEndDate;

  @override
  int get hashCode => Object.hash(
    firstDate,
    currentDate,
    currentStreak,
    longestStreak,
    longestStreakStartDate,
    longestStreakEndDate,
  );
}

/// "YYYY-MM-DD" in the device's local timezone.
String dateKey(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Given the stored record and "now", returns the updated record.
/// Returns [prev] itself (same instance) when nothing changes, so callers can
/// cheaply skip saving/notifying.
///
/// Opening the app 20 times in one day hits the early return below.
StreakData computeUpdated(StreakData prev, DateTime now) {
  final today = dateKey(now);
  // DateTime normalises day overflow/underflow (day 0 => last day of previous month).
  final yesterday = dateKey(DateTime(now.year, now.month, now.day - 1));

  // First-ever open, or storage was empty.
  if (prev.currentDate == null) {
    final hadLongest = prev.longestStreak >= 1;
    return StreakData(
      firstDate: today,
      currentDate: today,
      currentStreak: 1,
      longestStreak: hadLongest ? prev.longestStreak : 1,
      longestStreakStartDate: hadLongest ? prev.longestStreakStartDate : today,
      longestStreakEndDate: hadLongest ? prev.longestStreakEndDate : today,
    );
  }

  // Already counted today -> no-op.
  if (prev.currentDate == today) return prev;

  final continued = prev.currentDate == yesterday;
  final streak = continued ? prev.currentStreak + 1 : 1;
  final streakStart = dateKey(
    DateTime(now.year, now.month, now.day - (streak - 1)),
  );

  var longest = prev.longestStreak;
  var longestStart = prev.longestStreakStartDate;
  var longestEnd = prev.longestStreakEndDate;
  if (streak > longest) {
    longest = streak;
    longestStart = streakStart;
    longestEnd = today;
  } else if (streak == longest && continued) {
    // Tie while extending: the current run becomes the "official" longest.
    longestStart = streakStart;
    longestEnd = today;
  }

  return StreakData(
    firstDate: prev.firstDate ?? today,
    currentDate: today,
    currentStreak: streak,
    longestStreak: longest,
    longestStreakStartDate: longestStart,
    longestStreakEndDate: longestEnd,
  );
}
