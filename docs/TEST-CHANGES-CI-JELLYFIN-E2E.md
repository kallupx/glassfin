# Test changes: local Jellyfin E2E CI

No existing test file or assertion is modified, weakened or removed by this
change relative to main. The merge of updated origin/main includes #44's own
test changes, documented upstream in `docs/TEST-CHANGES-M08a-TRACKS.md`.

- Added `Apps/Shared/Tests/Logic/UITestStateResetTests.swift`: verifies reset-only
  launch arguments keep mock mode disabled, clears isolated defaults/cache and
  keychain state, preserves unrelated keychain services/cache files, and permits
  repeated reset. Runs in the existing iOS/tvOS hosted unit-test targets in CI.
- Added `scripts/ci/test_jellyfin_e2e.py`: isolated Python regression checks for
  pinned archive verification, loopback-only API redirects, secret-safe artifact
  cleanup, and the explicit unavailable-test result before PR #47 lands. Added
  a startup-race regression: public info can succeed while the wizard API still
  returns 503; no setup mutation is sent until that API becomes ready.

The new CI job selects #47's existing tvOS acceptance class only when its source
is present. It does not copy, rewrite, skip individual assertions, or merge the
stacked app branches. Full acceptance remains dependent on #47 and its app
prerequisites.
