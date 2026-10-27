# Contributing

All repository content (code, identifiers, comments, logs, tests, commit messages, pull requests, ADRs, README, specs and test plans) must be in English. User-facing strings must use String Catalogs (`.xcstrings`) with English (`en`) as the development language and Finnish (`fi`) translations, never hardcoded text. Tests compare keys or error types, never displayed text. Every key in every `.xcstrings` must have `translated` `en` and `fi` entries, enforced by `StringCatalogTests`.

In CoreNetworking, define each English source sentence once in a catalog key constant and pass that constant to `localizedString(_:)` in its localized accessor. The helper uses Foundation and the module bundle on Apple platforms and returns the key on Linux.

## Dependency pull requests

Dependabot opens one grouped pull request for Swift packages and one for GitHub Actions (`open-pull-requests-limit: 1` in `.github/dependabot.yml`). Those runs execute the Linux `lint` job only.

A grouped dependency pull request is not mergeable on lint alone, and Dependabot auto-merge stays off. Before merging:

1. Add the `full-ci` label, or start the `ci` workflow with `workflow_dispatch` on that branch. `workflow_dispatch` runs the macOS jobs. The pull request check turns green only after a `pull_request` run with `full-ci` records those jobs.
2. Wait until `test-tvos` and `test-ios` are green. The `dependabot-macos` check is green for every other pull request, and it fails a Dependabot pull request until `full-ci` is set and at least one of those jobs succeeded. A path-filter skip is not a macOS build. Require that check in branch protection so lint alone cannot merge the pull request.

`full-ci` also runs the `full-ui` job.
