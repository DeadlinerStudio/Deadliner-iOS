# REFACTOR V2

## Status

This document defines the agreed V2 refactor direction for Deadliner's DDL model, inner todo model, and sync model. It is the implementation guideline for the current refactor.

## Working Rules

The following rules are mandatory during this refactor:

1. Do not use excessive fallback logic.
2. Prefer explicit errors over silent degradation.
3. Prefer strict state transitions over scattered boolean inference.
4. Prefer canonical modeling over patching old design mistakes.
5. If a state or data shape is invalid, throw an error instead of guessing.
6. Compatibility logic must be isolated at the boundary layer, not leaked into the canonical model.

## Core Decisions

### 1. DDL uses a state machine

`isCompleted` and `isArchived` will be replaced by a single canonical `state`.

Recommended state definition:

```swift
enum DDLState: String, Codable {
    case active
    case completed
    case archived
    case abandoned
}
```

Meaning:

- `active`: normal working state
- `completed`: user finished the DDL
- `archived`: completed item moved out of the active list
- `abandoned`: user explicitly gave up the DDL

### 2. Tombstone remains independent

`tombstone` is not part of the business state machine.

It remains an independent sync-layer deletion marker:

- business state: represented by `DDLState`
- sync deletion state: represented by `isTombstoned`

Reason:

- reduces compatibility cost for Android and HarmonyOS
- keeps sync semantics separate from user-facing lifecycle semantics

### 3. Inner Todo is embedded into DDL

Inner todo should no longer be modeled as an independently synchronized entity.

Canonical direction:

- inner todo becomes part of the DDL document
- storage format is structured JSON
- Markdown may be used as a rendering or export format, but not as the canonical persistence format

Recommended model:

```swift
struct InnerTodo: Codable, Identifiable, Hashable {
    var id: String
    var content: String
    var isCompleted: Bool
    var sortOrder: Int
    var createdAt: String?
    var updatedAt: String?
}
```

Recommended entity storage:

- add `subTasksBlob: Data?` or equivalent JSON field to `DDLItemEntity`
- do not use Markdown as the only persisted source of truth

## State Machine Rules

State transitions must be centralized and validated.

Recommended allowed transitions:

- `active -> completed`
- `active -> abandoned`
- `completed -> archived`
- `completed -> active`
- `archived -> completed`
- `archived -> active`
- `abandoned -> active`

No other transition should be silently accepted.

If a transition is invalid, throw an explicit error.

Recommended abstraction:

```swift
enum DDLStateTransitionError: Error {
    case invalidTransition(from: DDLState, to: DDLState)
}
```

## Sync V2

### Direction

Sync V2 becomes the canonical sync model for iOS.

V1 remains only as a compatibility projection for old Android and HarmonyOS clients.

Principle:

- V2 is canonical
- V1 is compatibility output
- compatibility logic must not distort the internal model

### Paths

Recommended remote files:

- `Deadliner/snapshot-v1.json`
- `Deadliner/snapshot-v2.json`

### V2 shape

Recommended V2 document shape:

```json
{
  "version": { "ts": "...", "dev": "..." },
  "items": [
    {
      "uid": "device:id",
      "ver": { "ts": "...", "ctr": 1, "dev": "..." },
      "deleted": false,
      "doc": {
        "name": "...",
        "start_time": "...",
        "end_time": "...",
        "state": "completed",
        "complete_time": "...",
        "note": "...",
        "is_stared": false,
        "type": "task",
        "habit_count": 0,
        "habit_total_count": 0,
        "calendar_event": -1,
        "timestamp": "...",
        "sub_tasks": [
          {
            "id": "uuid",
            "content": "example",
            "is_completed": false,
            "sort_order": 0
          }
        ]
      }
    }
  ]
}
```

### V1 compatibility mapping

V1 compatibility is a projection from V2 state:

- `active` -> `is_completed = 0`, `is_archived = 0`
- `completed` -> `is_completed = 1`, `is_archived = 0`
- `archived` -> `is_completed = 1`, `is_archived = 1`
- `abandoned` -> degrade to a V1-compatible representation

Agreed compatibility rule:

- `abandoned` is downgraded when projected to V1
- semantic loss on V1 clients is acceptable
- V2 remains the only source of full truth

## Local Data Migration

Migration should be staged.

### Phase 1

- add `stateRaw`
- add embedded inner todo JSON field
- keep old `isCompleted` and `isArchived` temporarily
- backfill `stateRaw` from old fields

Backfill rules:

- if `isArchived == true`, state is `archived`
- else if `isCompleted == true`, state is `completed`
- else state is `active`

### Phase 2

- switch repositories and business logic to `state`
- switch inner todo read/write path to embedded JSON
- keep compatibility adapters only where required

### Phase 3

- remove old boolean-driven logic
- remove legacy subtask sync assumptions
- delete obsolete storage only after migration is verified

## SubTask Migration Strategy

Recommended migration strategy is staged, not one-shot.

### Transitional approach

- keep old `SubTaskEntity` temporarily
- sync only the embedded inner todo document
- move UI and repository reads to the embedded model
- remove old entity after verification

This reduces migration risk while keeping the V2 model clean.

## Implementation Priorities

Recommended order:

1. Introduce `DDLState`, `InnerTodo`, and state machine validation.
2. Extend `DDLItemEntity` with `stateRaw` and embedded inner todo storage.
3. Update mappers and repository logic to use the new canonical model.
4. Keep V1 sync behavior stable while local behavior moves to V2 model.
5. Implement `SyncServiceV2`.
6. Add V2 to V1 compatibility projection.
7. Remove obsolete legacy logic after verification.

## Non-Negotiable Engineering Style

During this refactor:

- do not swallow invalid state
- do not auto-heal malformed business data unless the migration explicitly defines the rule
- do not infer meaning from unrelated fields when canonical fields already exist
- do not add convenience fallback branches just to "make it work"
- do not let compatibility constraints dictate canonical design

When data is invalid and no migration rule exists, fail explicitly.
