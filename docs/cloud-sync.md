# Nareru cloud-sync design

## Goals

- Recording progress always works offline.
- Multiple devices converge without silently losing completions.
- Cloud sync is optional; local-only use remains supported.
- Each account can access only its own data.

## Components

1. **Local SQLite database** — queried by the UI and used while offline.
2. **Outbox** — records each local mutation until the server acknowledges it.
3. **Supabase Auth** — email magic link initially; additional providers later.
4. **Supabase Postgres** — canonical cross-device copy with row-level security.
5. **Sync worker** — pushes the outbox, then pulls rows changed after its cursor.

## Merge rules

Habit completions are stored as one row per habit and local calendar date. A
device changes the absolute completion count, not a fragile increment request.
For concurrent edits, the newest `updated_at` wins. Deletions use tombstones so
an offline device cannot accidentally recreate a deleted habit.

Habit UUIDs are generated on-device. Every synced row contains `user_id`,
`updated_at`, and `deleted_at`. The server assigns authoritative timestamps.

## Secrets and CI

Public Supabase URL and anonymous key may be supplied using `--dart-define`.
They are not administrative credentials; row-level security is mandatory.
Never place the Supabase service-role key in the app or GitHub build workflow.

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://example.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=your-anon-key
```

Test builds compile without backend values and run in local-only mode.
