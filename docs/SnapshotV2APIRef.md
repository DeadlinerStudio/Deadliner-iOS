# Snapshot V2 API Ref

## Purpose

This document defines the canonical Snapshot V2 sync contract for Deadliner.

It is the migration reference for:

- iOS
- Android
- HarmonyOS

It covers:

- DDL snapshot model
- Habit snapshot model
- local database migration requirements
- WebDAV file strategy
- V1 compatibility rules

This document is normative for cross-platform migration.

## Core Principles

1. Snapshot V2 is the canonical sync model.
2. Snapshot V1 is compatibility output only.
3. DDL and Habit use separate snapshot files.
4. Business lifecycle state is modeled by `state`.
5. Sync deletion remains modeled by `deleted` or local tombstone.
6. Inner Todo stays embedded inside DDL snapshot.
7. Habit records stay inside Habit snapshot.
8. Invalid data must fail explicitly.

## Files

Canonical files:

- `Deadliner/snapshot-v2.json`
- `Deadliner/habit-snapshot-v2.json`

Compatibility file:

- `Deadliner/snapshot-v1.json`

## DDL Snapshot V2

### WebDAV path

- `Deadliner/snapshot-v2.json`

### Root shape

```json
{
  "version": {
    "ts": "2026-03-24T12:00:00Z",
    "dev": "ABC123"
  },
  "items": [
    {
      "uid": "ABC123:1",
      "ver": {
        "ts": "2026-03-24T12:00:00Z",
        "ctr": 0,
        "dev": "ABC123"
      },
      "deleted": false,
      "doc": {
        "id": 1,
        "name": "Write report",
        "start_time": "2026-03-24T08:00:00",
        "end_time": "2026-03-24T18:00:00",
        "state": "active",
        "complete_time": "",
        "note": "example",
        "is_stared": 0,
        "type": "task",
        "habit_count": 0,
        "habit_total_count": 0,
        "calendar_event": -1,
        "timestamp": "2026-03-24T08:00:00",
        "sub_tasks": []
      }
    }
  ]
}
```

### DDL fields

- `uid`: globally unique DDL identity
- `ver.ts`: version timestamp
- `ver.ctr`: version tie-break counter
- `ver.dev`: version device id
- `deleted`: tombstone flag
- `doc.id`: local DDL legacy id, not globally authoritative
- `doc.name`
- `doc.start_time`
- `doc.end_time`
- `doc.state`
- `doc.complete_time`
- `doc.note`
- `doc.is_stared`
- `doc.type`
- `doc.habit_count`
- `doc.habit_total_count`
- `doc.calendar_event`
- `doc.timestamp`
- `doc.sub_tasks`

### State values

```json
"state": "active | completed | archived | abandoned | abandonedArchived"
```

Meaning:

- `active`: normal working state
- `completed`: task finished
- `archived`: completed and archived
- `abandoned`: user explicitly gave up the task
- `abandonedArchived`: user explicitly gave up the task and then archived it

### Task state machine

Canonical task actions:

- `markComplete`
- `markArchive`
- `markGiveUp`
- `restoreActive`
- `unarchive`

Canonical transitions:

- `active --markComplete--> completed`
- `completed --markArchive--> archived`
- `active --markGiveUp--> abandoned`
- `abandoned --markArchive--> abandonedArchived`

Supported reverse transitions:

- `completed --restoreActive--> active`
- `abandoned --restoreActive--> active`
- `archived --unarchive--> completed`
- `abandonedArchived --unarchive--> abandoned`

Rules:

- clients should implement task lifecycle transitions through an action-based state machine instead of ad hoc direct state writes
- `abandoned` is still an active-list task and must not be treated as archived
- `abandonedArchived` is an archive-list task and must preserve the fact that it was abandoned before archiving

### Tombstone

Tombstone is not part of the business state machine.

Meaning:

- `state` answers lifecycle semantics
- `deleted` answers sync deletion semantics

### Tombstone retention

Deleted tombstones are not required to live forever.

Rules:

- clients may retain tombstones for a bounded retention window, for example 30 days
- tombstones older than the retention window may be pruned from local storage
- tombstones older than the retention window may also be dropped during snapshot merge/build so remote snapshot files can shrink over time
- once a tombstone is older than the retention window, clients accept the risk that a very stale offline device may no longer receive that deletion marker

Recommended behavior:

- apply normal LWW rules within the retention window
- after the retention window, treat the tombstone as eligible for garbage collection

### Inner Todo shape

```json
{
  "id": "sub-1",
  "content": "Draft outline",
  "is_completed": 0,
  "sort_order": 0,
  "created_at": "2026-03-24T08:00:00Z",
  "updated_at": "2026-03-24T08:05:00Z"
}
```

Rules:

- `id` must be stable across edits
- `is_completed` is `0 | 1`
- `sort_order` is integer order

## Habit Snapshot V2

### WebDAV path

- `Deadliner/habit-snapshot-v2.json`

### Direction

Habit sync is separated from DDL sync.

Reason:

- Habit records need their own payload
- keeping Habit separate avoids mixing task state sync and habit history sync
- DDL remains the carrier identity, but Habit sync has its own file

### Root shape

```json
{
  "version": {
    "ts": "2026-03-24T12:00:00Z",
    "dev": "ABC123"
  },
  "items": [
    {
      "uid": "ABC123:habit-carrier",
      "ver": {
        "ts": "2026-03-24T12:00:00Z",
        "ctr": 1,
        "dev": "ABC123"
      },
      "deleted": false,
      "doc": {
        "ddl_uid": "ABC123:habit-carrier",
        "habit": {
          "name": "Read English",
          "description": "15 minutes daily",
          "color": 3,
          "icon_key": "book",
          "period": "DAILY",
          "times_per_period": 1,
          "goal_type": "PER_PERIOD",
          "total_target": null,
          "created_at": "2026-03-24T08:00:00Z",
          "updated_at": "2026-03-24T09:00:00Z",
          "status": "ACTIVE",
          "sort_order": 0,
          "alarm_time": "21:00"
        },
        "records": [
          {
            "date": "2026-03-24",
            "count": 1,
            "status": "COMPLETED",
            "created_at": "2026-03-24T08:00:00Z"
          }
        ]
      }
    }
  ]
}
```

### Identity rules

- `HabitSnapshotV2Item.uid` must equal the carrier DDL uid
- `doc.ddl_uid` must equal `item.uid`

If these do not match, clients must fail explicitly.

### Habit payload fields

- `name`
- `description`
- `color`
- `icon_key`
- `period`
- `times_per_period`
- `goal_type`
- `total_target`
- `created_at`
- `updated_at`
- `status`
- `sort_order`
- `alarm_time`

### Habit record fields

- `date`
- `count`
- `status`
- `created_at`

### Merge rule

Current baseline rule:

- Habit snapshot item version reuses the carrier DDL version
- whole habit document uses last-write-wins by `ver.ts`, then `ver.ctr`, then `ver.dev`
- when a newer habit snapshot item is applied, local habit config is overwritten and local habit records for that habit are replaced
- clients must store a Habit-specific applied sync version locally, independent from the carrier DDL sync version
- every Habit content mutation must bump sync version
- every Habit content mutation must also produce a newer mutation timestamp such as `habit.updated_at`
- clients must not emit a local Habit doc with a carrier version that is newer than `habit_applied_ver_*` when the local Habit payload still reflects older content
- a practical equivalent rule is:
  - if `carrier version > habit_applied_ver_*`
  - and local `habit.updated_at != carrier ver.ts`
  - then the local Habit payload is stale and must be skipped during local Habit snapshot build

Clients must not invent per-record merge semantics unless the protocol is extended later.

### Habit deletion semantics

- `deleted: true` means the carrier DDL still exists, but the synced Habit document has been removed
- if a local habit carrier DDL exists and its `HabitEntity` is missing, clients must emit a Habit snapshot tombstone only when that carrier version was last written by the local device
- if a local habit carrier DDL exists and its `HabitEntity` is missing, but that carrier version came from remote sync, clients must skip the item and wait for remote Habit snapshot apply
- applying a newer Habit tombstone must delete the local `HabitEntity` and all local `HabitRecord` rows for that habit
- after applying the tombstone, the client must move the carrier DDL version to the tombstone version
- if a Habit tombstone arrives but the local carrier DDL does not exist, clients must treat it as an idempotent no-op

## Local Database Migration

### DDL side

All platforms should move toward this DDL model:

- add canonical `state`
- keep tombstone independent
- embed inner todo into DDL payload

Recommended local DDL fields:

- `state`
- `complete_time`
- `sub_tasks_json`
- `is_tombstoned`

Legacy fields that must be retired from canonical DDL logic:

- `isCompleted`
- `isArchived`

Legacy backfill rules:

- if `isArchived == true`, migrate to `state = archived`
- else if `isCompleted == true`, migrate to `state = completed`
- else migrate to `state = active`

### Habit side

Habit local storage may still use separate tables locally.

Recommended local model:

- keep Habit configuration as local entity/table
- keep HabitRecord as local entity/table
- sync identity must be anchored by the carrier DDL uid
- store `habit_applied_ver_ts`, `habit_applied_ver_ctr`, `habit_applied_ver_dev` as local metadata on the carrier or equivalent local sync state
- if the carrier DDL exists but HabitEntity is absent, treat it as a Habit tombstone state for sync output

Required rule:

- local Habit/HabitRecord ids are not canonical cross-device identities
- sync identity for a habit item is always the carrier DDL uid
- Habit apply/skip decisions must use the Habit-specific applied version, not the carrier DDL version
- `habit_applied_ver_*` means the version of the local Habit payload that has actually been applied, not merely the latest carrier DDL version

## WebDAV Read Strategy

Recommended order:

1. Load `snapshot-v2.json`
2. Merge with `snapshot-v1.json` if compatibility is required
3. Apply DDL snapshot to local first
4. Load `habit-snapshot-v2.json`
5. Apply Habit snapshot after carrier DDLs are available locally

## WebDAV Write Strategy

Recommended order:

1. Build and merge DDL V2 snapshot
2. Write `snapshot-v2.json`
3. Project merged DDL V2 into V1-compatible shape
4. Write `snapshot-v1.json`
5. Build and merge Habit V2 snapshot
6. Write `habit-snapshot-v2.json`

Do not overwrite remote files blindly.

## Version Rules

All writes must continue to compare versions by:

1. `ver.ts`
2. `ver.ctr`
3. `ver.dev`

Conditional writes must use remote `ETag` when available.

On `412 Precondition Failed`:

1. reload remote
2. merge again
3. retry write

## V1 Compatibility Projection

V1 only applies to DDL snapshot.

V1 has no canonical:

- `state`
- `sub_tasks`
- Habit snapshot

V2 to V1 projection rules:

- `active` -> `is_completed = 0`, `is_archived = 0`
- `completed` -> `is_completed = 1`, `is_archived = 0`
- `archived` -> `is_completed = 1`, `is_archived = 1`
- `abandoned` -> downgrade to `archived`

`sub_tasks` are dropped when projecting V2 to V1.

There is no V1 projection for Habit snapshot.

## Invalid Data Rules

The following must fail explicitly:

- invalid `state`
- DDL item with missing `doc` while `deleted == false`
- Habit snapshot item with missing `doc` while `deleted == false`
- Habit snapshot `doc.ddl_uid != item.uid`
- Habit snapshot item whose carrier DDL does not exist locally when applying
- invalid habit `period`
- invalid habit `goal_type`
- invalid habit `status`
- non-positive habit `times_per_period`
- invalid habit record `status`
- non-positive habit record `count`

## Habit Snapshot Build Rule

When building a local Habit snapshot item:

- if carrier DDL is tombstoned, emit Habit tombstone
- if carrier DDL exists and HabitEntity exists, emit active Habit doc
- if carrier DDL exists but HabitEntity is missing and the carrier version was last written by the local device, emit Habit tombstone
- if carrier DDL exists but HabitEntity is missing and the carrier version was not last written by the local device, skip the item and wait for remote Habit snapshot apply
- if carrier DDL exists and HabitEntity exists, but the carrier version is newer than `habit_applied_ver_*` while local Habit content still reflects an older payload, skip the item and wait for remote Habit snapshot apply
- clients should only emit the local Habit doc in that situation when the local payload itself has caught up to the new carrier version, for example when `habit.updated_at == carrier ver.ts`

## Platform Migration Checklist

### Android

Required work:

- add canonical DDL `state`
- add `sub_tasks_json`
- keep tombstone independent
- implement `snapshot-v2.json`
- implement `snapshot-v1.json` compatibility projection
- implement `habit-snapshot-v2.json`
- anchor habit sync identity to carrier DDL uid

### HarmonyOS

Required work:

- same as Android
- keep compatibility logic only at sync boundary
- do not mix Habit snapshot into DDL snapshot

### iOS

Expected direction:

- DDL uses canonical `state`
- DDL sync and Habit sync are separate files
- Habit snapshot applies only after DDL carrier is available

## Minimal Client Requirements

A compliant V2 client must:

1. Read and write `snapshot-v2.json`
2. Read and write `habit-snapshot-v2.json`
3. Understand all four DDL states
4. Keep tombstone independent from state
5. Preserve `sub_tasks`
6. Keep habit item identity equal to carrier DDL uid
7. Reject invalid data explicitly
8. Project DDL V2 into V1 if old clients still exist

## Deferred Scope

The following is intentionally not part of the current protocol:

- per-record conflict-free merge for HabitRecord
- independent top-level habit identities separate from DDL carrier uid
- V1 compatibility output for Habit snapshot

## Final Rule

If a conflict exists between:

- old local boolean semantics
- old V1 DDL semantics
- new V2 canonical semantics

Then V2 canonical semantics win inside the app model.

Compatibility handling must remain at the sync boundary only.
