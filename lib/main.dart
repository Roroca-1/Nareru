import 'dart:math';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

void main() => runApp(const NareruApp());
DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

enum ReminderMode { none, fixedTime, interval }

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
}

class Habit {
  Habit({required this.name, required this.emoji, required this.goal, required this.unit,
    required this.category, required this.reminder, required this.color, this.imageBytes,
    Map<DateTime, int>? history}) : history = history ?? {};
  String name, emoji, unit, category;
  int goal;
  Reminder reminder;
  Color color;
  Uint8List? imageBytes;
  final Map<DateTime, int> history;
  int count(DateTime d) => history[day(d)] ?? 0;
}

class NareruApp extends StatefulWidget {
  const NareruApp({super.key});
  @override State<NareruApp> createState() => _NareruAppState();
}

class _NareruAppState extends State<NareruApp> {
  ThemeMode mode = ThemeMode.system;
  Color seed = const Color(0xff507d61);
  @override Widget build(BuildContext context) {
    ThemeData theme(Brightness b) => ThemeData(
      useMaterial3: true, brightness: b,
      colorScheme: ColorScheme.fromSeed(seedColor: seed, brightness: b),
      cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false, title: 'Nareru',
      theme: theme(Brightness.light), darkTheme: theme(Brightness.dark), themeMode: mode,
      home: HabitShell(themeMode: mode, seed: seed, onTheme: (m, s) => setState(() { mode = m; seed = s; })),
    );
  }
}

class HabitShell extends StatefulWidget {
  const HabitShell({super.key, required this.themeMode, required this.seed, required this.onTheme});
  final ThemeMode themeMode; final Color seed; final void Function(ThemeMode, Color) onTheme;
  @override State<HabitShell> createState() => _HabitShellState();
}

class _HabitShellState extends State<HabitShell> {
  int page = 0;
  final habits = <Habit>[];

  void log(Habit h, [int delta = 1]) => setState(() {
    final d = day(DateTime.now());
    h.history[d] = max(0, h.count(d) + delta);
  });

  Future<void> edit([Habit? old]) async {
    final h = await showModalBottomSheet<Habit>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => HabitEditor(existing: old),
    );
    if (h == null) return;
    setState(() {
      if (old == null) {
        habits.add(h);
      } else {
        old
          ..name = h.name
          ..emoji = h.emoji
          ..goal = h.goal
          ..unit = h.unit
          ..category = h.category
          ..reminder = h.reminder
          ..color = h.color
          ..imageBytes = h.imageBytes;
      }
    });
  }

  Future<void> remove(Habit h) async {
    final yes = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: Text('Delete ${h.name}?'),
      content: const Text('The habit and its completion history will be deleted.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
      ],
    ));
    if (yes == true) setState(() => habits.remove(h));
  }

  void appearance() => showModalBottomSheet<void>(
    context: context, showDragHandle: true,
    builder: (_) => AppearanceSheet(mode: widget.themeMode, seed: widget.seed, onChanged: widget.onTheme),
  );

  @override Widget build(BuildContext context) {
    final pages = [
      TodayPage(habits: habits, onLog: log, onCreate: () => edit()),
      HabitsPage(habits: habits, onCreate: () => edit(), onEdit: edit, onDelete: remove),
      TrackingPage(habits: habits),
    ];
    const nav = [
      NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'This week'),
      NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Habits'),
      NavigationDestination(icon: Icon(Icons.insights_outlined), selectedIcon: Icon(Icons.insights), label: 'Tracking'),
    ];
    final body = IndexedStack(index: page, children: pages);
    if (MediaQuery.sizeOf(context).width < 760) {
      return Scaffold(
        appBar: AppBar(actions: [IconButton(onPressed: appearance, icon: const Icon(Icons.palette_outlined), tooltip: 'Appearance')]),
        body: body,
        bottomNavigationBar: NavigationBar(selectedIndex: page, destinations: nav, onDestinationSelected: (v) => setState(() => page = v)),
      );
    }
    return Scaffold(body: Row(children: [
      NavigationRail(
        selectedIndex: page, labelType: NavigationRailLabelType.all,
        onDestinationSelected: (v) => setState(() => page = v),
        trailing: Expanded(child: Align(alignment: Alignment.bottomCenter,
          child: Padding(padding: const EdgeInsets.only(bottom: 16), child: IconButton(onPressed: appearance, icon: const Icon(Icons.palette_outlined), tooltip: 'Appearance')))),
        destinations: nav.map((n) => NavigationRailDestination(icon: n.icon, selectedIcon: n.selectedIcon, label: Text(n.label))).toList(),
      ),
      const VerticalDivider(width: 1), Expanded(child: body),
    ]));
  }
}

class Frame extends StatelessWidget {
  const Frame({super.key, required this.child}); final Widget child;
  @override Widget build(BuildContext context) => SafeArea(child: Align(alignment: Alignment.topCenter,
    child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 920),
      child: Padding(padding: const EdgeInsets.all(20), child: child))));
}

class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon; final String title, message; final Widget? action;
  @override Widget build(BuildContext context) => Center(child: ConstrainedBox(
    constraints: const BoxConstraints(maxWidth: 360),
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 16),
      Text(title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 8), Text(message, textAlign: TextAlign.center,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      if (action != null) ...[const SizedBox(height: 20), action!],
    ]),
  ));
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.habits, required this.onLog, required this.onCreate});
  final List<Habit> habits; final void Function(Habit, [int]) onLog; final VoidCallback onCreate;
  @override Widget build(BuildContext context) => Frame(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('This week', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
    const SizedBox(height: 16),
    Expanded(child: habits.isEmpty
      ? EmptyState(icon: Icons.spa_outlined, title: 'Start with one small thing',
          message: 'Nareru has no default habits. Create only what matters to you.',
          action: FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('Create habit')))
      : ListView.separated(
          itemCount: habits.length, separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (_, i) {
            final h = habits[i], n = h.count(DateTime.now());
            return Card(child: ListTile(
              leading: HabitAvatar(habit: h), title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
              subtitle: Text('$n / ${h.goal} ${h.unit} • ${h.reminder.label(context)}'),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                if (n > 0) IconButton(onPressed: () => onLog(h, -1), icon: const Icon(Icons.undo), tooltip: 'Undo'),
                FilledButton.tonal(onPressed: () => onLog(h), child: Text(n >= h.goal ? '+1' : 'Done')),
              ]),
            ));
          })),
  ]));
}

class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key, required this.habits, required this.onCreate, required this.onEdit, required this.onDelete});
  final List<Habit> habits; final VoidCallback onCreate; final ValueChanged<Habit> onEdit, onDelete;
  @override Widget build(BuildContext context) {
    final groups = <String, List<Habit>>{};
    for (final h in habits) {
      groups.putIfAbsent(h.category.isEmpty ? 'Uncategorized' : h.category, () => []).add(h);
    }
    return Frame(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Expanded(child: Text('Habits', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700))),
        FilledButton.icon(onPressed: onCreate, icon: const Icon(Icons.add), label: const Text('New habit')),
      ]),
      const SizedBox(height: 16),
      Expanded(child: habits.isEmpty
        ? const EmptyState(icon: Icons.checklist, title: 'No habits yet', message: 'Create habits here, then edit, categorize, or delete them at any time.')
        : ListView(children: groups.entries.expand((g) => [
            Padding(padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
              child: Text(g.key, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            ...g.value.map((h) => Padding(padding: const EdgeInsets.only(bottom: 8), child: Card(child: ListTile(
              leading: HabitAvatar(habit: h), title: Text(h.name), subtitle: Text(h.reminder.label(context)),
              onTap: () => onEdit(h),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'edit' ? onEdit(h) : onDelete(h),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: ListTile(leading: Icon(Icons.edit_outlined), title: Text('Edit'))),
                  PopupMenuItem(value: 'delete', child: ListTile(leading: Icon(Icons.delete_outline), title: Text('Delete'))),
                ],
              ),
            )))),
          ]).toList())),
    ]));
  }
}

class TrackingPage extends StatelessWidget {
  const TrackingPage({super.key, required this.habits}); final List<Habit> habits;
  @override Widget build(BuildContext context) => Frame(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Text('Tracking', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
    const SizedBox(height: 6), Text('Choose a habit to see its history.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
    const SizedBox(height: 16),
    Expanded(child: habits.isEmpty
      ? const EmptyState(icon: Icons.insights_outlined, title: 'Nothing to track yet', message: 'Progress will appear here after you create a habit.')
      : ListView.separated(
          itemCount: habits.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (_, i) {
            final h = habits[i];
            return Card(child: ListTile(
              leading: HabitAvatar(habit: h), title: Text(h.name),
              subtitle: Text(h.category.isEmpty ? 'Uncategorized' : h.category),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitDetailPage(habit: h))),
            ));
          })),
  ]));
}

class HabitAvatar extends StatelessWidget {
  const HabitAvatar({super.key, required this.habit}); final Habit habit;
  @override Widget build(BuildContext context) => CircleAvatar(
    backgroundColor: habit.color.withValues(alpha: .18),
    backgroundImage: habit.imageBytes == null ? null : MemoryImage(habit.imageBytes!),
    child: habit.imageBytes == null ? Text(habit.emoji) : null,
  );
}

class HabitDetailPage extends StatelessWidget {
  const HabitDetailPage({super.key, required this.habit}); final Habit habit;
  @override Widget build(BuildContext context) {
    final days = List.generate(140, (i) => day(DateTime.now()).subtract(Duration(days: 139 - i)));
    final completed = days.where((d) => habit.count(d) >= habit.goal).length;
    return Scaffold(appBar: AppBar(title: Text(habit.name)), body: Frame(child: ListView(children: [
      Text('$completed days completed', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      Card(child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Last 20 weeks', style: TextStyle(fontWeight: FontWeight.w700)), const SizedBox(height: 14),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(20, (w) =>
          Padding(padding: const EdgeInsets.only(right: 4), child: Column(children: List.generate(7, (wd) {
            final d = days[w * 7 + wd], n = habit.count(d);
            return Tooltip(message: '${d.year}-${d.month}-${d.day}: $n ${habit.unit}',
              child: Container(width: 18, height: 18, margin: const EdgeInsets.only(bottom: 4),
                decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
                  color: n == 0 ? Theme.of(context).colorScheme.surfaceContainerHighest
                    : Color.lerp(habit.color.withValues(alpha: .25), habit.color, min(1.0, n / habit.goal)))));
          })))))),
        const SizedBox(height: 10), Text('Darker squares mean more completions.', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ]))),
    ])));
  }
}

class HabitEditor extends StatefulWidget {
  const HabitEditor({super.key, this.existing}); final Habit? existing;
  @override State<HabitEditor> createState() => _HabitEditorState();
}

class _HabitEditorState extends State<HabitEditor> {
  static const emojis = ['🌱','💪','📖','🧘','🎨','✍️','🏃','🧹','💊','⭐','🎵','🧠'];
  static const colors = [Color(0xff507d61), Color(0xff3f78b5), Color(0xff8b64b1), Color(0xffc06d42), Color(0xffb54d69), Color(0xff00897b)];
  late final TextEditingController name, unit, category;
  late int goal, interval;
  late String emoji;
  late Color color;
  late ReminderMode reminderMode;
  late TimeOfDay fixedTime, windowStart, windowEnd;
  Uint8List? image;

  @override void initState() {
    super.initState(); final h = widget.existing;
    name = TextEditingController(text: h?.name ?? '');
    unit = TextEditingController(text: h?.unit ?? 'times');
    category = TextEditingController(text: h?.category ?? '');
    goal = h?.goal ?? 1; emoji = h?.emoji ?? '🌱'; color = h?.color ?? colors.first; image = h?.imageBytes;
    reminderMode = h?.reminder.mode ?? ReminderMode.none;
    fixedTime = h?.reminder.time ?? const TimeOfDay(hour: 9, minute: 0);
    interval = h?.reminder.minutes ?? 45;
    windowStart = h?.reminder.start ?? const TimeOfDay(hour: 9, minute: 0);
    windowEnd = h?.reminder.end ?? const TimeOfDay(hour: 21, minute: 0);
  }
  @override void dispose() { name.dispose(); unit.dispose(); category.dispose(); super.dispose(); }

  Future<void> chooseImage() async {
    final file = await FilePicker.pickFile(type: FileType.image);
    if (file != null) {
      final bytes = await file.readAsBytes();
      if (mounted) setState(() => image = bytes);
    }
  }
  Future<void> chooseTime(String target) async {
    final initial = target == 'fixed' ? fixedTime : target == 'start' ? windowStart : windowEnd;
    final value = await showTimePicker(context: context, initialTime: initial);
    if (value == null) return;
    setState(() { if (target == 'fixed') fixedTime = value; else if (target == 'start') windowStart = value; else windowEnd = value; });
  }

  @override Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
    child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(widget.existing == null ? 'Create habit' : 'Edit habit', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      TextField(controller: name, autofocus: widget.existing == null, onChanged: (_) => setState(() {}),
        decoration: const InputDecoration(labelText: 'Name', border: OutlineInputBorder())), const SizedBox(height: 12),
      TextField(controller: category, decoration: const InputDecoration(labelText: 'Category', hintText: 'Health, study, home…', border: OutlineInputBorder())),
      const SizedBox(height: 16), Text('Icon or image', style: Theme.of(context).textTheme.titleMedium), const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 8, children: [
        ...emojis.map((e) => ChoiceChip(label: Text(e), selected: image == null && emoji == e,
          onSelected: (_) => setState(() { emoji = e; image = null; }))),
        ActionChip(avatar: const Icon(Icons.image_outlined), label: Text(image == null ? 'Custom image' : 'Image selected'), onPressed: chooseImage),
      ]),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: colors.map((c) => ChoiceChip(label: CircleAvatar(radius: 9, backgroundColor: c),
        selected: color == c, onSelected: (_) => setState(() => color = c))).toList()),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: TextField(controller: unit, decoration: const InputDecoration(labelText: 'Unit', border: OutlineInputBorder()))),
        const SizedBox(width: 8), const Text('Goal'),
        IconButton(onPressed: goal > 1 ? () => setState(() => goal--) : null, icon: const Icon(Icons.remove)),
        Text('$goal'), IconButton(onPressed: () => setState(() => goal++), icon: const Icon(Icons.add)),
      ]),
      const SizedBox(height: 12),
      DropdownButtonFormField<ReminderMode>(
        initialValue: reminderMode, decoration: const InputDecoration(labelText: 'Reminder', border: OutlineInputBorder()),
        items: const [
          DropdownMenuItem(value: ReminderMode.none, child: Text('No reminder')),
          DropdownMenuItem(value: ReminderMode.fixedTime, child: Text('At a certain time')),
          DropdownMenuItem(value: ReminderMode.interval, child: Text('At regular intervals')),
        ],
        onChanged: (v) => setState(() => reminderMode = v!),
      ),
      if (reminderMode == ReminderMode.fixedTime)
        ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.schedule), title: const Text('Reminder time'),
          subtitle: Text(fixedTime.format(context)), onTap: () => chooseTime('fixed')),
      if (reminderMode == ReminderMode.interval) ...[
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          initialValue: interval, decoration: const InputDecoration(labelText: 'Remind every', border: OutlineInputBorder()),
          items: [15, 30, 45, 60, 90, 120, 180].map((m) => DropdownMenuItem(value: m, child: Text('$m minutes'))).toList(),
          onChanged: (v) => setState(() => interval = v!),
        ),
        Row(children: [
          Expanded(child: ListTile(contentPadding: EdgeInsets.zero, title: const Text('Start'), subtitle: Text(windowStart.format(context)), onTap: () => chooseTime('start'))),
          Expanded(child: ListTile(contentPadding: EdgeInsets.zero, title: const Text('End'), subtitle: Text(windowEnd.format(context)), onTap: () => chooseTime('end'))),
        ]),
      ],
      const SizedBox(height: 16),
      FilledButton(
        onPressed: name.text.trim().isEmpty ? null : () {
          final reminder = switch (reminderMode) {
            ReminderMode.none => const Reminder.none(),
            ReminderMode.fixedTime => Reminder.fixed(fixedTime),
            ReminderMode.interval => Reminder.interval(interval, windowStart, windowEnd),
          };
          Navigator.pop(context, Habit(
            name: name.text.trim(), emoji: emoji, goal: goal,
            unit: unit.text.trim().isEmpty ? 'times' : unit.text.trim(),
            category: category.text.trim(), reminder: reminder, color: color, imageBytes: image,
          ));
        },
        child: Text(widget.existing == null ? 'Create habit' : 'Save changes'),
      ),
    ])),
  );
}

class AppearanceSheet extends StatefulWidget {
  const AppearanceSheet({super.key, required this.mode, required this.seed, required this.onChanged});
  final ThemeMode mode; final Color seed; final void Function(ThemeMode, Color) onChanged;
  @override State<AppearanceSheet> createState() => _AppearanceSheetState();
}
class _AppearanceSheetState extends State<AppearanceSheet> {
  late ThemeMode mode = widget.mode; late Color seed = widget.seed;
  static const colors = [Color(0xff507d61), Color(0xff426bba), Color(0xff7655a6), Color(0xffa85468), Color(0xffbd642f), Color(0xff00897b)];
  @override Widget build(BuildContext context) => Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 28),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Appearance', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)), const SizedBox(height: 12),
      SegmentedButton<ThemeMode>(
        segments: const [
          ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.settings_brightness)),
          ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
          ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
        ],
        selected: {mode}, onSelectionChanged: (v) { setState(() => mode = v.first); widget.onChanged(mode, seed); },
      ),
      const SizedBox(height: 20), const Text('Material color'), const SizedBox(height: 10),
      Wrap(spacing: 10, children: colors.map((c) => ChoiceChip(
        label: CircleAvatar(backgroundColor: c), selected: seed == c,
        onSelected: (_) { setState(() => seed = c); widget.onChanged(mode, seed); },
      )).toList()),
    ]),
  );
}
