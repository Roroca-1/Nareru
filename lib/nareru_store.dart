import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';
import 'models.dart';
import 'linux_notifications.dart';
import 'native_notifications.dart';

class NareruStore extends ChangeNotifier {
  static const schemaVersion = 1;
  final habits = <Habit>[];
  final deletedHabits = <String, DateTime>{};
  bool loading = true, syncing = false;
  DateTime? lastSync;
  String? syncError;
  String linuxReminderMode = 'systemService';
  Timer? _appReminderTimer;

  bool get cloudConfigured => const String.fromEnvironment('SUPABASE_URL').isNotEmpty &&
    const String.fromEnvironment('SUPABASE_ANON_KEY').isNotEmpty;
  User? get user => cloudConfigured ? Supabase.instance.client.auth.currentUser : null;

  Future<File> get _file async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}${Platform.pathSeparator}nareru-data.json');
  }

  Future<void> load() async {
    try {
      final file = await _file;
      if (await file.exists()) {
        _replaceFromJson(jsonDecode(await file.readAsString()) as Map<String, dynamic>);
      }
      await _configureNotifications(file);
    } catch (error) {
      syncError = error.toString();
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Map<String, dynamic> toJson() => {
    'schema_version': schemaVersion,
    'exported_at': DateTime.now().toUtc().toIso8601String(),
    'habits': habits.map((h) => h.toJson()).toList(),
    'deleted_habits': deletedHabits.map((id, time) => MapEntry(id, time.toIso8601String())),
    'linux_reminder_mode': linuxReminderMode,
  };

  void _replaceFromJson(Map<String, dynamic> json) {
    linuxReminderMode = json['linux_reminder_mode']?.toString() == 'appOnly' ? 'appOnly' : 'systemService';
    habits
      ..clear()
      ..addAll((json['habits'] as List? ?? []).map((e) => Habit.fromJson(Map<String, dynamic>.from(e as Map))));
    deletedHabits
      ..clear()
      ..addAll((json['deleted_habits'] as Map? ?? {}).map((k, v) => MapEntry(k.toString(), DateTime.parse(v.toString()))));
  }

  Future<void> save({bool refreshNotifications = false}) async {
    final file = await _file;
    await file.parent.create(recursive: true);
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(const JsonEncoder.withIndent('  ').convert(toJson()), flush: true);
    if (Platform.isWindows) {
      await temp.copy(file.path);
      await temp.delete();
    } else {
      await temp.rename(file.path);
    }
    if (refreshNotifications) {
      try {
        await _configureNotifications(file);
      } catch (error) {
        syncError = 'Reminder setup failed: $error';
      }
    }
    notifyListeners();
  }

  Future<void> add(Habit habit) async { habits.add(habit); await save(refreshNotifications: true); }
  Future<void> update(Habit habit) async { habit.touch(); await save(refreshNotifications: true); }
  Future<void> remove(Habit habit) async {
    habits.remove(habit); deletedHabits[habit.id] = DateTime.now().toUtc(); await save(refreshNotifications: true);
  }
  Future<void> removeMany(Iterable<Habit> selected) async {
    for (final habit in selected.toList()) {
      habits.remove(habit);
      deletedHabits[habit.id] = DateTime.now().toUtc();
    }
    await save(refreshNotifications: true);
  }
  Future<void> categorizeMany(Iterable<Habit> selected, String category) async {
    for (final habit in selected) {
      habit.category = category.trim();
      habit.touch();
    }
    await save();
  }
  Future<void> log(Habit habit, int delta, [DateTime? date]) async {
    final d = day(date ?? DateTime.now());
    habit.history[d] = (habit.count(d) + delta).clamp(0, 9999);
    habit.touch();
    await save();
  }

  Future<String?> exportBackup() async {
    final bytes = Uint8List.fromList(utf8.encode(const JsonEncoder.withIndent('  ').convert(toJson())));
    if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
      final directory = await FilePicker.getDirectoryPath(
        dialogTitle: 'Choose backup folder',
        initialDirectory: File(Platform.resolvedExecutable).parent.path,
      );
      if (directory == null) return null;
      final file = File('$directory${Platform.pathSeparator}nareru-data.json');
      await file.writeAsBytes(bytes, flush: true);
      return file.path;
    }
    final uri = await FilePicker.saveFile(
      fileName: 'nareru-data.json', bytes: bytes, mimeType: 'application/json',
      type: FileType.custom, allowedExtensions: const ['json']);
    return uri?.toString();
  }

  Future<String> notificationStatus() => Platform.isLinux
    ? linuxReminderMode == 'appOnly'
      ? Future.value('Nareru checks reminders while this app is open')
      : LinuxNotifications.status()
    : Future.value('Uses ${Platform.operatingSystem} native notifications');
  Future<void> repairNotifications() async {
    await _configureNotifications(await _file);
  }
  Future<void> setLinuxReminderMode(String mode) async {
    linuxReminderMode = mode;
    await save();
    await _configureNotifications(await _file);
    notifyListeners();
  }

  Future<void> _configureNotifications(File file) async {
    if (Platform.isLinux) {
      _appReminderTimer?.cancel();
      _appReminderTimer = null;
      if (linuxReminderMode == 'appOnly') {
        await LinuxNotifications.disable();
        await NativeNotifications.checkDueNow(habits);
        _appReminderTimer = Timer.periodic(const Duration(seconds: 20), (_) {
          NativeNotifications.checkDueNow(habits);
        });
      } else {
        await LinuxNotifications.refresh(file);
      }
      return;
    }
    await NativeNotifications.reschedule(habits);
  }

  @override
  void dispose() {
    _appReminderTimer?.cancel();
    super.dispose();
  }
  Future<void> testNotification() => NativeNotifications.test();

  Future<void> importBackup() async {
    final picked = await FilePicker.pickFile(type: FileType.custom, allowedExtensions: const ['json']);
    if (picked == null) {
      return;
    }
    final decoded = jsonDecode(utf8.decode(await picked.readAsBytes())) as Map<String, dynamic>;
    if ((decoded['schema_version'] as num?)?.toInt() != schemaVersion) {
      throw const FormatException('Unsupported Nareru backup version');
    }
    _replaceFromJson(decoded);
    await save(refreshNotifications: true);
  }

  Future<void> signIn() async {
    if (!cloudConfigured) {
      throw StateError('Cloud sync is not configured in this build.');
    }
    await Supabase.instance.client.auth.signInWithOAuth(
      OAuthProvider.google, redirectTo: 'io.supabase.nareru://login-callback');
  }

  Future<void> signOut() async {
    await Supabase.instance.client.auth.signOut();
    lastSync = null; notifyListeners();
  }

  Future<void> sync() async {
    if (!cloudConfigured || user == null || syncing) {
      return;
    }
    syncing = true; syncError = null; notifyListeners();
    try {
      final client = Supabase.instance.client;
      final uid = user!.id;
      final remote = await client.from('habits').select().eq('user_id', uid);
      final remoteById = {for (final row in remote) row['id'].toString(): row};

      for (final habit in List<Habit>.from(habits)) {
        final row = remoteById[habit.id];
        if (row != null && row['deleted_at'] != null) {
          habits.remove(habit);
          deletedHabits[habit.id] = DateTime.parse(row['deleted_at'].toString());
          continue;
        }
        final remoteUpdated = row == null ? null : DateTime.tryParse(row['updated_at']?.toString() ?? '');
        if (row != null && remoteUpdated != null && remoteUpdated.isAfter(habit.updatedAt)) {
          _applyRemoteHabit(habit, row);
        } else {
          await client.from('habits').upsert(_habitRow(habit, uid));
        }
      }
      for (final entry in deletedHabits.entries) {
        await client.from('habits').update({'deleted_at': entry.value.toIso8601String()}).eq('id', entry.key).eq('user_id', uid);
      }
      for (final row in remote) {
        final id = row['id'].toString();
        if (row['deleted_at'] != null || deletedHabits.containsKey(id) || habits.any((h) => h.id == id)) {
          continue;
        }
        habits.add(_habitFromRemote(row));
      }
      final entries = await client.from('habit_entries').select().eq('user_id', uid);
      final remoteEntries = <String, Map<String, dynamic>>{
        for (final row in entries)
          '${row['habit_id']}|${row['local_date']}': Map<String, dynamic>.from(row),
      };
      for (final habit in habits) {
        for (final entry in habit.history.entries) {
          final key = '${habit.id}|${dateKey(entry.key)}';
          final remoteEntry = remoteEntries[key];
          final remoteUpdated = remoteEntry == null ? null : DateTime.tryParse(remoteEntry['updated_at']?.toString() ?? '');
          if (remoteEntry != null && remoteUpdated != null && remoteUpdated.isAfter(habit.updatedAt)) {
            habit.history[entry.key] = (remoteEntry['count'] as num).toInt();
          } else {
            await client.from('habit_entries').upsert({
              'id': remoteEntry?['id'] ?? const Uuid().v4(), 'habit_id': habit.id, 'user_id': uid,
              'local_date': dateKey(entry.key), 'count': entry.value,
            }, onConflict: 'habit_id,local_date');
          }
        }
      }
      for (final row in entries) {
        Habit? habit;
        for (final candidate in habits) {
          if (candidate.id == row['habit_id']) {
            habit = candidate;
            break;
          }
        }
        if (habit != null && row['deleted_at'] == null) {
          habit.history[DateTime.parse(row['local_date'].toString())] = (row['count'] as num).toInt();
        }
      }
      lastSync = DateTime.now(); await save(refreshNotifications: true);
    } catch (error) {
      syncError = error.toString();
    } finally {
      syncing = false; notifyListeners();
    }
  }

  Map<String, dynamic> _habitRow(Habit h, String uid) => {
    'id': h.id, 'user_id': uid, 'name': h.name, 'emoji': h.emoji,
    'color': h.color.toARGB32(), 'daily_goal': h.goal, 'unit': h.unit,
    'category': h.category, 'reminder': h.reminder.toJson(), 'schedule': h.schedule.toJson(),
    'icon_base64': h.imageBytes == null ? null : base64Encode(h.imageBytes!),
    'created_at': h.createdAt.toIso8601String(), 'updated_at': h.updatedAt.toIso8601String(),
    'deleted_at': null,
  };
  Habit _habitFromRemote(Map<String, dynamic> row) => Habit.fromJson({
    'id': row['id'], 'name': row['name'], 'emoji': row['emoji'], 'color': row['color'],
    'goal': row['daily_goal'], 'unit': row['unit'], 'category': row['category'],
    'reminder': row['reminder'], 'schedule': row['schedule'], 'image': row['icon_base64'],
    'created_at': row['created_at'], 'updated_at': row['updated_at'], 'history': <String, int>{},
  });
  void _applyRemoteHabit(Habit h, Map<String, dynamic> row) {
    final remote = _habitFromRemote(row);
    h
      ..name = remote.name
      ..emoji = remote.emoji
      ..goal = remote.goal
      ..unit = remote.unit
      ..category = remote.category
      ..reminder = remote.reminder
      ..schedule = remote.schedule
      ..color = remote.color
      ..imageBytes = remote.imageBytes
      ..updatedAt = remote.updatedAt;
  }
}
