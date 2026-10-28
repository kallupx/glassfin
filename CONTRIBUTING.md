# Contributing

All repository content (code, identifiers, comments, logs, tests, commit messages, pull requests, ADRs, README, specs and test plans) must be in English. User-facing strings must use String Catalogs (`.xcstrings`) with English (`en`) as the development language and Finnish (`fi`) translations, never hardcoded text. Tests compare keys or error types, never displayed text. Every key in every `.xcstrings` must have `translated` `en` and `fi` entries, enforced by `StringCatalogTests`.

In CoreNetworking, define each English source sentence once in a catalog key constant and pass that constant to `localizedString(_:)` in its localized accessor. The helper uses Foundation and the module bundle on Apple platforms and returns the key on Linux.

## Dependency pull requests

Dependabot opens one grouped pull request for Swift packages and one for GitHub Actions (`open-pull-requests-limit: 1` in `.github/dependabot.yml`). Without the `full-ci` label, those runs execute the Linux `lint` job and skip the macOS build jobs. After lint succeeds, `dependabot-macos` still runs and fails with instructions to add `full-ci`.

Keep Dependabot auto-merge off. Before merging:

1. Add the `full-ci` label to start the macOS jobs selected by the path filters. Dependabot is identified by the pull request author, so a maintainer adding a label does not change this policy.
2. Wait until `dependabot-macos` is green. On a Dependabot pull request with `full-ci`, it requires each path-selected `test-tvos` and `test-ios` job to succeed, rejects failures and cancellations, and accepts a skip only for paths that do not select that job. After lint succeeds, it runs and passes on other pull requests and non-PR events.

With `full-ci`, a Dependabot GitHub Actions update that selects neither macOS path passes `dependabot-macos` without a macOS build. This is intentional: the gate does not require at least one macOS job to succeed. Changes under `.github/workflows/` currently select both macOS jobs.

`full-ci` also runs `full-ui` when the macOS path filter selects it. To run both macOS build jobs manually, start the `ci` workflow with `workflow_dispatch` on that branch and review the results directly. A manual run does not satisfy the pull request gate: the Dependabot pull request still needs `full-ci`.

Require `dependabot-macos` in branch protection so an unlabeled Dependabot pull request cannot merge on lint alone. The gate has no token permissions; the other CI jobs retain read-only permissions. These runs do not require repository secrets or `pull_request_target`.
