# Test media

Media files are not stored in this repository. Playback integration that needs real files is a follow-up and will download them outside the repo.

`scripts/docker-integration.sh` generates two-second synthetic media outside the repo:
one movie and `Fixture Series` with S1E1, S1E2 and S2E1. The bootstrap registers
separate movie and TV libraries and waits for both seasons and their episodes.
The DEBUG `LibraryFixtureClient` scenarios `series-single-season` and
`series-two-seasons` mirror the series shape for unit/UI tests (T07-43/T07-44).
