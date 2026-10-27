# M17 – Admin tools (P2)

**Spec version:** v1.3.3 (22.10.2026). Changes are shown in SPEC.md's change history.

**Dependencies:** M01–M04 and M10. **Ruling (the team on 21.10.2026):** a P2 module, not in the MVP.

## Visibility and security
- Shown only if `User.Policy.IsAdministrator == true` (`GET /Users/Me`). **The server does the real authorization**, and 403 is handled cleanly (02, S7.1).
- Destructive actions (restart, deleting a user or a device, cancelling a task) require a **separate confirmation**, whose default focus is "Cancel" (fi: "Peruuta") (S7.2).

## tvOS (light version)
| Action | Endpoint |
|---|---|
| Active sessions (who is watching what, PlayMethod, the transcoding reason) | `GET /Sessions` (+ WebSocket `SessionsStart`/`Sessions`) |
| A library scan | `POST /Library/Refresh` |
| Scheduled tasks: list, start, and stop | `GET /ScheduledTasks`, `POST`/`DELETE /ScheduledTasks/Running/{taskId}` |

## iOS (full version)
- In addition to the above: user management (`GET`/`POST /Users`, `GET`/`DELETE /Users/{userId}`, `POST /Users/{userId}/Policy`; permissions and parental ratings `GET /Localization/ParentalRatings`), devices (`GET`/`DELETE /Devices`), and a server restart (`POST /System/Restart`).
- Reference: Swiftfin iOS's admin dashboard, PR https://github.com/jellyfin/Swiftfin/pull/1230 (its contents were not checked in this spec).

## Acceptance criteria
- [ ] A non-admin user does not see the admin menu. If the admin permission is removed mid-session (403), a message is shown, and the app does not crash.
- [ ] Every destructive action requires confirmation (UI test).
- [ ] The session list updates within ≤ 5 s (WebSocket).
