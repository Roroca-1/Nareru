import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);
String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

enum ReminderMode { none, fixedTime, interval }

enum HabitScheduleMode { everyDay, weekdays, interval }

class HabitSchedule {
  HabitSchedule.everyDay()
    : mode = HabitScheduleMode.everyDay, weekdays = <int>{}, intervalDays = 1, anchorDate = day(DateTime.now());
  HabitSchedule.weekdays(Set<int> days)
    : mode = HabitScheduleMode.weekdays, weekdays = days, intervalDays = 1, anchorDate = day(DateTime.now());
  HabitSchedule.interval(this.intervalDays, DateTime anchor)
    : mode = HabitScheduleMode.interval, weekdays = <int>{}, anchorDate = day(anchor);

  final HabitScheduleMode mode;
  final Set<int> weekdays;
  final int intervalDays;
  final DateTime anchorDate;

  bool isDue(DateTime value) => switch (mode) {
    HabitScheduleMode.everyDay => true,
    HabitScheduleMode.weekdays => weekdays.contains(value.weekday),
    HabitScheduleMode.interval => day(value).difference(anchorDate).inDays % intervalDays == 0,
  };

  String get label => switch (mode) {
    HabitScheduleMode.everyDay => 'Every day',
    HabitScheduleMode.weekdays => _weekdayLabel(weekdays),
    HabitScheduleMode.interval => intervalDays == 2 ? 'Every other day' : 'Every $intervalDays days',
  };

  Map<String, dynamic> toJson() => {
    'mode': mode.name, 'weekdays': weekdays.toList()..sort(),
    'interval_days': intervalDays, 'anchor_date': dateKey(anchorDate),
  };

  factory HabitSchedule.fromJson(Map<String, dynamic>? json) {
    if (json == null) return HabitSchedule.everyDay();
    final mode = HabitScheduleMode.values.firstWhere(
      (e) => e.name == json['mode'], orElse: () => HabitScheduleMode.everyDay);
    return switch (mode) {
      HabitScheduleMode.everyDay => HabitSchedule.everyDay(),
      HabitScheduleMode.weekdays => HabitSchedule.weekdays(
        (json['weekdays'] as List? ?? const []).map((e) => (e as num).toInt()).toSet()),
      HabitScheduleMode.interval => HabitSchedule.interval(
        ((json['interval_days'] as num?)?.toInt() ?? 2).clamp(2, 365),
        DateTime.tryParse(json['anchor_date']?.toString() ?? '') ?? DateTime.now()),
    };
  }

  static String _weekdayLabel(Set<int> values) {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    if (values.isEmpty) return 'No days selected';
    return [for (var i = 1; i <= 7; i++) if (values.contains(i)) names[i - 1]].join(', ');
  }
}

class Reminder {
  const Reminder.none() : mode = ReminderMode.none, time = null, minutes = null, start = null, end = null;
  const Reminder.fixed(this.time) : mode = ReminderMode.fixedTime, minutes = null, start = null, end = null;
  const Reminder.interval(this.minutes, this.start, this.end) : mode = ReminderMode.interval, time = null;
  final ReminderMode mode;
  final TimeOfDay? time, start, end;
  final int? minutes;

  String label(BuildContext c) => switch (mode) {
    ReminderMode.none => 'No reminder',
    ReminderMode.fixedTime => 'Every day at ${time!.format(c)}',
    ReminderMode.interval => 'Every $minutes min • ${start!.format(c)}–${end!.format(c)}',
  };

  Map<String, dynamic> toJson() => {
    'mode': mode.name, 'time': _time(time), 'minutes': minutes,
    'start': _time(start), 'end': _time(end),
  };
  factory Reminder.fromJson(Map<String, dynamic>? json) {
    if (json == null) {
      return const Reminder.none();
    }
    final mode = ReminderMode.values.firstWhere((e) => e.name == json['mode'], orElse: () => ReminderMode.none);
    return switch (mode) {
      ReminderMode.none => const Reminder.none(),
      ReminderMode.fixedTime => Reminder.fixed(_parseTime(json['time']) ?? const TimeOfDay(hour: 9, minute: 0)),
      ReminderMode.interval => Reminder.interval(
        (json['minutes'] as num?)?.toInt() ?? 45,
        _parseTime(json['start']) ?? const TimeOfDay(hour: 9, minute: 0),
        _parseTime(json['end']) ?? const TimeOfDay(hour: 21, minute: 0)),
    };
  }
  static String? _time(TimeOfDay? value) => value == null ? null : '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';
  static TimeOfDay? _parseTime(Object? value) {
    final parts = value?.toString().split(':');
    if (parts == null || parts.length != 2) {
      return null;
    }
    return TimeOfDay(hour: int.parse(parts[0]), minute: int.parse(parts[1]));
  }
}

class Habit {
  Habit({
    String? id, required this.name, required this.emoji, required this.goal,
    required this.unit, required this.category, required this.reminder,
    required this.color, HabitSchedule? schedule, this.imageBytes, Map<DateTime, int>? history,
    DateTime? createdAt, DateTime? updatedAt,
  }) : id = id ?? const Uuid().v4(),
       schedule = schedule ?? HabitSchedule.everyDay(), history = history ?? {},
       createdAt = createdAt ?? DateTime.now().toUtc(),
       updatedAt = updatedAt ?? DateTime.now().toUtc();

  final String id;
  String name, emoji, unit, category;
  int goal;
  Reminder reminder;
  HabitSchedule schedule;
  Color color;
  Uint8List? imageBytes;
  final Map<DateTime, int> history;
  final DateTime createdAt;
  DateTime updatedAt;
  int count(DateTime d) => history[day(d)] ?? 0;
  void touch() => updatedAt = DateTime.now().toUtc();

  Map<String, dynamic> toJson() => {
    'id': id, 'name': name, 'emoji': emoji, 'goal': goal, 'unit': unit,
    'category': category, 'reminder': reminder.toJson(), 'schedule': schedule.toJson(),
    'color': color.toARGB32(), 'image': imageBytes == null ? null : base64Encode(imageBytes!),
    'created_at': createdAt.toIso8601String(), 'updated_at': updatedAt.toIso8601String(),
    'history': {for (final e in history.entries) dateKey(e.key): e.value},
  };

  factory Habit.fromJson(Map<String, dynamic> json) {
    final history = <DateTime, int>{};
    for (final entry in (json['history'] as Map<String, dynamic>? ?? {}).entries) {
      history[DateTime.parse(entry.key)] = (entry.value as num).toInt();
    }
    final image = json['image'] as String?;
    return Habit(
      id: json['id'] as String?, name: json['name'] as String? ?? 'Untitled',
      emoji: json['emoji'] as String? ?? '🌱', goal: (json['goal'] as num?)?.toInt() ?? 1,
      unit: json['unit'] as String? ?? 'times', category: json['category'] as String? ?? '',
      reminder: Reminder.fromJson(json['reminder'] as Map<String, dynamic>?),
      schedule: HabitSchedule.fromJson(json['schedule'] as Map<String, dynamic>?),
      color: Color((json['color'] as num?)?.toInt() ?? 0xff507d61),
      imageBytes: image == null ? null : base64Decode(image), history: history,
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ?? ''),
    );
  }
}
