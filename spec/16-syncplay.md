# M16 – SyncPlay (P2)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M08 and WebSocket (M01).
- Endpoints (verified from the spec): `GET /SyncPlay/List`, `POST /SyncPlay/New`, `/Join`, `/Leave`, `/Pause`, `/Seek`, `/Ready`, `/Buffering`, `/Ping`, `/Queue`, `/NextItem`, `/PreviousItem`, and `/SyncPlay/{id}`. WebSocket messages: `SyncPlayCommand` and `SyncPlayGroupUpdate`.
- Note (Researcher): the official Android TV client does not yet support SyncPlay. Parity with the web.
- Acceptance criterion: two clients stay in sync within ± 500 ms, and pause/seek is propagated within ≤ 1 s.
