# Nareru

**慣れる (nareru)** — to get used to something.

A calm, local-first habit tracker built with Flutter. The product deliberately
avoids a planner-style calendar: the home screen only concerns itself with this
week and today's next useful action.

## Product principles

- One tap records progress.
- The home screen shows only this week.
- A missed day is information, not a failure.
- Reminders may be fixed-time, interval-based, or disabled.
- Detailed history lives behind each habit, not on the main screen.
- Data is local-first. Sync can be added later without being required.

## Current prototype

The prototype includes a responsive Android/desktop interface, today view,
weekly progress, quick completion/undo, habit list, creation sheet, and a
GitHub-style history view populated with demo data. State is currently in
memory so the interaction model can be validated before adding persistence and
native notification scheduling.

## Run

```bash
flutter create . --platforms=android,linux,windows,ios,macos
flutter pub get
flutter run
```

## Cloud sync

Nareru is designed to work offline first. SQLite is the source used by the UI;
when the user signs in, a background sync engine exchanges changed rows with
Supabase. See [`docs/cloud-sync.md`](docs/cloud-sync.md) and
[`supabase/schema.sql`](supabase/schema.sql).

The app must never require an internet connection to record a completion.

## Test builds

The GitHub Actions workflow in `.github/workflows/build-test-packages.yml`
builds Android, Linux, Windows, unsigned iOS, and macOS packages. It runs for
pull requests, pushes to `main`, and manual dispatches. Download packages from
the workflow run's **Artifacts** section.

## Planned implementation order

1. SQLite persistence and editable habits
2. Sync engine and sign-in UI
3. Android notification scheduling and reboot recovery
4. Linux and Windows native notifications
5. Export/import backup
6. iOS and macOS notification setup

The notification data model should support `none`, `fixedTimes`, and
`intervalWindow` modes. Interval reminders need a start/end window so “every
45 minutes” does not wake someone overnight.
