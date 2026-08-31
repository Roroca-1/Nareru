import 'dart:math';
import 'package:flutter/material.dart';

void main() => runApp(const NareruApp());

class NareruApp extends StatelessWidget {
  const NareruApp({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = ColorScheme.fromSeed(
      seedColor: const Color(0xff507d61),
      brightness: Brightness.light,
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Nareru',
      theme: ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xfff7f8f4),
        cardTheme: const CardThemeData(elevation: 0, margin: EdgeInsets.zero),
      ),
      home: const HabitShell(),
    );
  }
}

class Habit {
  Habit({required this.name, required this.emoji, required this.goal,
    required this.unit, required this.reminder, required this.color,
    Map<DateTime, int>? history}) : history = history ?? {};

  final String name, emoji, unit, reminder;
  final int goal;
  final Color color;
  final Map<DateTime, int> history;

  int count(DateTime date) => history[day(date)] ?? 0;
  bool complete(DateTime date) => count(date) >= goal;
}

DateTime day(DateTime d) => DateTime(d.year, d.month, d.day);

class HabitShell extends StatefulWidget {
  const HabitShell({super.key});
  @override State<HabitShell> createState() => _HabitShellState();
}

class _HabitShellState extends State<HabitShell> {
  int page = 0;
  late final List<Habit> habits = _demoHabits();

  void increment(Habit habit, [int delta = 1]) {
    setState(() {
      final today = day(DateTime.now());
      habit.history[today] = max(0, habit.count(today) + delta);
    });
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 720;
    final body = IndexedStack(index: page, children: [
      TodayPage(habits: habits, onIncrement: increment),
      HabitsPage(habits: habits, onAdd: _showCreate),
    ]);
    if (wide) {
      return Scaffold(
        body: Row(children: [
          NavigationRail(
            selectedIndex: page,
            onDestinationSelected: (v) => setState(() => page = v),
            labelType: NavigationRailLabelType.all,
            destinations: const [
              NavigationRailDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: Text('This week')),
              NavigationRailDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: Text('Habits')),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: body),
        ]),
      );
    }
    return Scaffold(
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: page,
        onDestinationSelected: (v) => setState(() => page = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.today_outlined), selectedIcon: Icon(Icons.today), label: 'This week'),
          NavigationDestination(icon: Icon(Icons.checklist_outlined), selectedIcon: Icon(Icons.checklist), label: 'Habits'),
        ],
      ),
    );
  }

  void _showCreate() {
    showModalBottomSheet<void>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => CreateHabitSheet(onCreate: (habit) {
        setState(() => habits.add(habit));
        Navigator.pop(context);
      }),
    );
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.child});
  final Widget child;
  @override Widget build(BuildContext context) => SafeArea(
    child: Align(alignment: Alignment.topCenter, child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 920),
      child: Padding(padding: const EdgeInsets.all(20), child: child),
    )),
  );
}

class TodayPage extends StatelessWidget {
  const TodayPage({super.key, required this.habits, required this.onIncrement});
  final List<Habit> habits;
  final void Function(Habit, [int]) onIncrement;

  @override Widget build(BuildContext context) {
    final now = DateTime.now();
    final done = habits.where((h) => h.complete(now)).length;
    return PageFrame(child: ListView(children: [
      Text('This week', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 4),
      Text('$done of ${habits.length} habits complete today', style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: Colors.black54)),
      const SizedBox(height: 20),
      WeekStrip(habits: habits),
      const SizedBox(height: 24),
      Text('Today', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 12),
      ...habits.map((h) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: HabitTodayCard(habit: h, onIncrement: onIncrement),
      )),
      if (done == habits.length) Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Text('Everything for today is done. Nice work — you can stop thinking about it.', textAlign: TextAlign.center,
          style: TextStyle(color: Theme.of(context).colorScheme.primary, fontWeight: FontWeight.w600)),
      ),
    ]));
  }
}

class WeekStrip extends StatelessWidget {
  const WeekStrip({super.key, required this.habits});
  final List<Habit> habits;
  @override Widget build(BuildContext context) {
    final today = day(DateTime.now());
    final monday = today.subtract(Duration(days: today.weekday - 1));
    return Card(color: Colors.white, child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Row(children: List.generate(7, (i) {
        final d = monday.add(Duration(days: i));
        final completed = habits.where((h) => h.complete(d)).length;
        final ratio = habits.isEmpty ? 0.0 : completed / habits.length;
        return Expanded(child: Column(children: [
          Text(['M','T','W','T','F','S','S'][i], style: const TextStyle(color: Colors.black54)),
          const SizedBox(height: 8),
          Container(width: 34, height: 34, alignment: Alignment.center,
            decoration: BoxDecoration(shape: BoxShape.circle,
              color: d == today ? Theme.of(context).colorScheme.primaryContainer : Colors.transparent,
              border: Border.all(color: Colors.black12)),
            child: Text('${d.day}', style: TextStyle(fontWeight: d == today ? FontWeight.w700 : FontWeight.w400))),
          const SizedBox(height: 8),
          ClipRRect(borderRadius: BorderRadius.circular(3), child: LinearProgressIndicator(value: ratio, minHeight: 5, backgroundColor: Colors.black12)),
        ]));
      })),
    ));
  }
}

class HabitTodayCard extends StatelessWidget {
  const HabitTodayCard({super.key, required this.habit, required this.onIncrement});
  final Habit habit;
  final void Function(Habit, [int]) onIncrement;
  @override Widget build(BuildContext context) {
    final count = habit.count(DateTime.now());
    final complete = count >= habit.goal;
    return Card(color: Colors.white, child: Padding(
      padding: const EdgeInsets.all(14),
      child: Row(children: [
        CircleAvatar(backgroundColor: habit.color.withValues(alpha: .15), child: Text(habit.emoji)),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(habit.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text('$count / ${habit.goal} ${habit.unit}  •  ${habit.reminder}', style: const TextStyle(color: Colors.black54)),
        ])),
        if (count > 0) IconButton(tooltip: 'Undo one', onPressed: () => onIncrement(habit, -1), icon: const Icon(Icons.undo)),
        FilledButton.tonalIcon(
          onPressed: () => onIncrement(habit),
          icon: Icon(complete ? Icons.add : Icons.check),
          label: Text(complete ? '+1' : 'Done'),
        ),
      ]),
    ));
  }
}

class HabitsPage extends StatelessWidget {
  const HabitsPage({super.key, required this.habits, required this.onAdd});
  final List<Habit> habits;
  final VoidCallback onAdd;
  @override Widget build(BuildContext context) => PageFrame(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Row(children: [
      Expanded(child: Text('Your habits', style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700))),
      FilledButton.icon(onPressed: onAdd, icon: const Icon(Icons.add), label: const Text('New habit')),
    ]),
    const SizedBox(height: 6),
    const Text('Tap a habit to see its history.', style: TextStyle(color: Colors.black54)),
    const SizedBox(height: 18),
    Expanded(child: ListView.separated(
      itemCount: habits.length, separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final h = habits[i];
        return Card(color: Colors.white, child: ListTile(
          leading: CircleAvatar(backgroundColor: h.color.withValues(alpha: .15), child: Text(h.emoji)),
          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text('${h.goal} ${h.unit} • ${h.reminder}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => HabitDetailPage(habit: h))),
        ));
      },
    )),
  ]));
}

class HabitDetailPage extends StatelessWidget {
  const HabitDetailPage({super.key, required this.habit});
  final Habit habit;
  @override Widget build(BuildContext context) {
    final days = List.generate(140, (i) => day(DateTime.now()).subtract(Duration(days: 139 - i)));
    final completed = days.where(habit.complete).length;
    final total = days.fold<int>(0, (sum, d) => sum + habit.count(d));
    return Scaffold(appBar: AppBar(title: Text('${habit.emoji}  ${habit.name}')), body: PageFrame(child: ListView(children: [
      Row(children: [
        Expanded(child: _Stat(value: '$completed', label: 'days completed')),
        const SizedBox(width: 10),
        Expanded(child: _Stat(value: '$total', label: habit.unit)),
      ]),
      const SizedBox(height: 20),
      Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('Last 20 weeks', style: TextStyle(fontWeight: FontWeight.w700)),
        const SizedBox(height: 14),
        SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: List.generate(20, (week) => Padding(
          padding: const EdgeInsets.only(right: 4), child: Column(children: List.generate(7, (weekday) {
            final d = days[week * 7 + weekday];
            final count = habit.count(d);
            final strength = count == 0 ? 0.0 : min(1.0, count / habit.goal);
            return Tooltip(message: '${d.year}-${d.month}-${d.day}: $count ${habit.unit}', child: Container(
              width: 18, height: 18, margin: const EdgeInsets.only(bottom: 4),
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(3),
                color: count == 0 ? const Color(0xffe7e9e5) : Color.lerp(habit.color.withValues(alpha: .25), habit.color, strength)),
            ));
          })),
        )))),
        const SizedBox(height: 12),
        const Text('Darker squares mean more completions. Hover or press a square for the exact count.', style: TextStyle(color: Colors.black54)),
      ]))),
      const SizedBox(height: 16),
      ListTile(tileColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        leading: const Icon(Icons.notifications_outlined), title: const Text('Reminder'), subtitle: Text(habit.reminder), trailing: const Icon(Icons.chevron_right)),
    ])));
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.value, required this.label});
  final String value, label;
  @override Widget build(BuildContext context) => Card(color: Colors.white, child: Padding(padding: const EdgeInsets.all(18), child: Column(children: [
    Text(value, style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w800)),
    Text(label, style: const TextStyle(color: Colors.black54)),
  ])));
}

class CreateHabitSheet extends StatefulWidget {
  const CreateHabitSheet({super.key, required this.onCreate});
  final ValueChanged<Habit> onCreate;
  @override State<CreateHabitSheet> createState() => _CreateHabitSheetState();
}

class _CreateHabitSheetState extends State<CreateHabitSheet> {
  final name = TextEditingController();
  int goal = 1;
  String reminder = 'No reminder';
  @override void dispose() { name.dispose(); super.dispose(); }
  @override Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(20, 0, 20, MediaQuery.viewInsetsOf(context).bottom + 24),
    child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('Create a habit', style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 16),
      TextField(controller: name, autofocus: true, onChanged: (_) => setState(() {}), decoration: const InputDecoration(labelText: 'Habit name', hintText: 'Drink water', border: OutlineInputBorder())),
      const SizedBox(height: 12),
      Row(children: [
        const Expanded(child: Text('Times per day')),
        IconButton(onPressed: goal > 1 ? () => setState(() => goal--) : null, icon: const Icon(Icons.remove)),
        Text('$goal', style: const TextStyle(fontWeight: FontWeight.w700)),
        IconButton(onPressed: () => setState(() => goal++), icon: const Icon(Icons.add)),
      ]),
      DropdownButtonFormField<String>(initialValue: reminder, decoration: const InputDecoration(labelText: 'Reminder', border: OutlineInputBorder()),
        items: const ['No reminder', 'At a certain time', 'At regular intervals'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => reminder = v!)),
      const SizedBox(height: 18),
      FilledButton(onPressed: name.text.trim().isEmpty ? null : () => widget.onCreate(Habit(
        name: name.text.trim(), emoji: '🌱', goal: goal, unit: goal == 1 ? 'time' : 'times', reminder: reminder, color: const Color(0xff507d61))), child: const Text('Create habit')),
    ]),
  );
}

List<Habit> _demoHabits() {
  final now = day(DateTime.now());
  final random = Random(7);
  Habit make(String name, String emoji, int goal, String unit, String reminder, Color color, double chance) {
    final history = <DateTime, int>{};
    for (var i = 0; i < 140; i++) {
      if (random.nextDouble() < chance) history[now.subtract(Duration(days: i))] = 1 + random.nextInt(goal);
    }
    history[now] = 0;
    return Habit(name: name, emoji: emoji, goal: goal, unit: unit, reminder: reminder, color: color, history: history);
  }
  return [
    make('Drink water', '💧', 8, 'glasses', 'Every 45 min • 9:00–21:00', const Color(0xff3f8fc4), .78),
    make('Stretch', '🧘', 1, 'session', '18:00', const Color(0xff8a6bb8), .62),
    make('Read', '📖', 1, 'session', 'No reminder', const Color(0xffd08045), .70),
  ];
}
