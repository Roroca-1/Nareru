import 'dart:convert';
import 'dart:io';

class LinuxNotifications {
  static Future<void> refresh(File dataFile) async {
    if (!Platform.isLinux) {
      return;
    }
    final home = Platform.environment['HOME'];
    if (home == null) {
      return;
    }
    final dir = Directory('$home/.config/systemd/user');
    await dir.create(recursive: true);
    final executable = Platform.resolvedExecutable.replaceAll('"', r'\"');
    final dataPath = dataFile.path.replaceAll('"', r'\"');
    await File('${dir.path}/nareru-reminders.service').writeAsString('''
[Unit]
Description=Check Nareru habit reminders

[Service]
Type=oneshot
ExecStart="$executable" --notification-worker "$dataPath"
''');
    await File('${dir.path}/nareru-reminders.timer').writeAsString('''
[Unit]
Description=Nareru habit reminder timer

[Timer]
OnCalendar=*-*-* *:*:00
AccuracySec=1s

[Install]
WantedBy=timers.target
''');
    await Process.run('systemctl', ['--user', 'daemon-reload']);
    await Process.run('systemctl', ['--user', 'enable', '--now', 'nareru-reminders.timer']);
  }

  static Future<void> runWorker(String dataPath) async {
    if (!Platform.isLinux) {
      return;
    }
    final file = File(dataPath);
    if (!await file.exists()) {
      return;
    }
    final data = jsonDecode(await file.readAsString()) as Map<String, dynamic>;
    final now = DateTime.now();
    final date = '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
    final minuteOfDay = now.hour * 60 + now.minute;
    for (final raw in data['habits'] as List? ?? const []) {
      final habit = Map<String, dynamic>.from(raw as Map);
      final reminder = Map<String, dynamic>.from(habit['reminder'] as Map? ?? const {});
      final goal = (habit['goal'] as num?)?.toInt() ?? 1;
      final count = ((habit['history'] as Map?)?[date] as num?)?.toInt() ?? 0;
      if (count >= goal) {
        continue;
      }
      final mode = reminder['mode'];
      var due = false;
      if (mode == 'fixedTime') {
        due = reminder['time'] == '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
      } else if (mode == 'interval') {
        final start = _minutes(reminder['start']?.toString());
        final end = _minutes(reminder['end']?.toString());
        final interval = (reminder['minutes'] as num?)?.toInt() ?? 45;
        if (start != null && end != null) {
          final inWindow = start <= end ? minuteOfDay >= start && minuteOfDay <= end : minuteOfDay >= start || minuteOfDay <= end;
          final elapsed = (minuteOfDay - start + 1440) % 1440;
          due = inWindow && elapsed % interval == 0;
        }
      }
      if (due) {
        await Process.run('notify-send', [
          '--app-name=Nareru', '--icon=appointment-soon',
          '${habit['emoji'] ?? '🌱'} ${habit['name'] ?? 'Habit'}',
          'Time for your habit • $count / $goal ${habit['unit'] ?? 'times'} today',
        ]);
      }
    }
  }

  static int? _minutes(String? value) {
    final parts = value?.split(':');
    if (parts == null || parts.length != 2) {
      return null;
    }
    return int.tryParse(parts[0]) == null || int.tryParse(parts[1]) == null
      ? null : int.parse(parts[0]) * 60 + int.parse(parts[1]);
  }
}
