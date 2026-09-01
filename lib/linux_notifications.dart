import 'dart:convert';
import 'dart:io';

class LinuxNotifications {
  static Future<void> disable() async {
    if (!Platform.isLinux) return;
    await Process.run('systemctl', ['--user', 'disable', '--now', 'nareru-reminders.timer']);
  }

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
Environment=DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus
ExecStart="$executable" --notification-worker "$dataPath"
''');
    await File('${dir.path}/nareru-reminders.timer').writeAsString('''
[Unit]
Description=Nareru habit reminder timer

[Timer]
OnBootSec=15s
OnUnitActiveSec=30s
AccuracySec=5s
Persistent=true

[Install]
WantedBy=timers.target
''');
    await _runChecked('systemctl', ['--user', 'daemon-reload']);
    await _runChecked('systemctl', ['--user', 'enable', 'nareru-reminders.timer']);
    await _runChecked('systemctl', ['--user', 'restart', 'nareru-reminders.timer']);
  }

  static Future<String> status() async {
    if (!Platform.isLinux) return 'Desktop reminders are currently available on Linux.';
    final notifier = await Process.run('which', ['notify-send']);
    if (notifier.exitCode != 0) return 'notify-send is missing. Install libnotify-bin/libnotify.';
    final timer = await Process.run('systemctl', ['--user', 'is-active', 'nareru-reminders.timer']);
    if (timer.exitCode != 0) {
      final detail = '${timer.stderr}'.trim();
      return 'Reminder timer is not active${detail.isEmpty ? '' : ': $detail'}';
    }
    final service = await Process.run('systemctl', ['--user', 'show', 'nareru-reminders.service', '--property=Result', '--value']);
    final result = '${service.stdout}'.trim();
    if (result.isNotEmpty && result != 'success') return 'Timer is active, but the last reminder check failed: $result';
    return 'Reminder timer is active • notify-send is available';
  }

  static Future<void> test() async {
    if (!Platform.isLinux) throw StateError('Test notifications are currently available on Linux.');
    await _runChecked('notify-send', [
      '--app-name=Nareru', '--icon=appointment-soon', 'Nareru test',
      'Notifications are working. You can close this message.',
    ]);
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
    final stateFile = File('$dataPath.reminder-state.json');
    final delivered = <String>{};
    if (await stateFile.exists()) {
      try {
        delivered.addAll((jsonDecode(await stateFile.readAsString()) as List).map((e) => e.toString()));
      } catch (_) {
        // A damaged delivery cache should never stop reminders.
      }
    }
    final oldest = now.subtract(const Duration(days: 2));
    delivered.removeWhere((key) {
      final stamp = key.split('|').last;
      return (DateTime.tryParse(stamp) ?? now).isBefore(oldest);
    });
    for (final raw in data['habits'] as List? ?? const []) {
      final habit = Map<String, dynamic>.from(raw as Map);
      final reminder = Map<String, dynamic>.from(habit['reminder'] as Map? ?? const {});
      final goal = (habit['goal'] as num?)?.toInt() ?? 1;
      for (var ago = 0; ago <= 2; ago++) {
        final candidate = DateTime(now.year, now.month, now.day, now.hour, now.minute).subtract(Duration(minutes: ago));
        final date = _date(candidate);
        final count = ((habit['history'] as Map?)?[date] as num?)?.toInt() ?? 0;
        final key = '${habit['id'] ?? habit['name']}|${candidate.toIso8601String()}';
        if (count >= goal || delivered.contains(key) || !_isScheduled(habit['schedule'], candidate) || !_isDue(reminder, candidate)) {
          continue;
        }
        await _runChecked('notify-send', [
          '--app-name=Nareru', '--icon=appointment-soon',
          '${habit['emoji'] ?? '🌱'} ${habit['name'] ?? 'Habit'}',
          'Time for your habit • $count / $goal ${habit['unit'] ?? 'times'} today',
        ]);
        delivered.add(key);
      }
    }
    await stateFile.writeAsString(jsonEncode(delivered.toList()), flush: true);
  }

  static bool _isDue(Map<String, dynamic> reminder, DateTime candidate) {
    final minuteOfDay = candidate.hour * 60 + candidate.minute;
    if (reminder['mode'] == 'fixedTime') {
      return _minutes(reminder['time']?.toString()) == minuteOfDay;
    }
    if (reminder['mode'] != 'interval') return false;
    final start = _minutes(reminder['start']?.toString());
    final end = _minutes(reminder['end']?.toString());
    final interval = (reminder['minutes'] as num?)?.toInt() ?? 45;
    if (start == null || end == null || interval < 1) return false;
    final inWindow = start <= end ? minuteOfDay >= start && minuteOfDay <= end : minuteOfDay >= start || minuteOfDay <= end;
    return inWindow && (minuteOfDay - start + 1440) % 1440 % interval == 0;
  }

  static bool _isScheduled(Object? raw, DateTime now) {
    final schedule = Map<String, dynamic>.from(raw as Map? ?? const {});
    final mode = schedule['mode'] ?? 'everyDay';
    if (mode == 'weekdays') {
      return (schedule['weekdays'] as List? ?? const []).any((e) => (e as num).toInt() == now.weekday);
    }
    if (mode == 'everyXDays' || mode == 'interval') {
      final interval = ((schedule['interval_days'] as num?)?.toInt() ?? 1).clamp(1, 365);
      final anchor = DateTime.tryParse(schedule['anchor_date']?.toString() ?? '') ?? now;
      final today = DateTime(now.year, now.month, now.day);
      final origin = DateTime(anchor.year, anchor.month, anchor.day);
      return today.difference(origin).inDays % interval == 0;
    }
    return true;
  }

  static String _date(DateTime value) => '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static Future<void> _runChecked(String command, List<String> arguments) async {
    final result = await Process.run(command, arguments);
    if (result.exitCode != 0) {
      final detail = '${result.stderr}'.trim().isEmpty ? '${result.stdout}'.trim() : '${result.stderr}'.trim();
      throw StateError('$command failed (${result.exitCode})${detail.isEmpty ? '' : ': $detail'}');
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
