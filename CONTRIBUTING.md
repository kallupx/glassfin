# Contributing

All repository content (code, identifiers, comments, logs, tests, commit messages, pull requests, ADRs, README, specs and test plans) must be in English. User-facing strings must use String Catalogs (`.xcstrings`) with English (`en`) as the development language and Finnish (`fi`) translations, never hardcoded text. Tests compare keys or error types, never displayed text. Every key in every `.xcstrings` must have `translated` `en` and `fi` entries, enforced by `StringCatalogTests`.

In CoreNetworking, define each English source sentence once in a catalog key constant and pass that constant to `localizedString(_:)` in its localized accessor. The helper uses Foundation and the module bundle on Apple platforms and returns the key on Linux.

## Dependency pull requests

Dependabot opens one grouped pull request for Swift packages and one for GitHub Actions (`open-pull-requests-limit: 1` in `.github/dependabot.yml`). Without the `full-ci` label, those runs execute the Linux `lint` job and skip the macOS jobs, including `dependabot-macos`. This is an intentional skip, not evidence of a macOS build.

Do not merge a grouped dependency pull request on lint alone, and keep Dependabot auto-merge off. Before merging:

1. Add the `full-ci` label to start the macOS jobs selected by the path filters. Dependabot is identified by the pull request author, so a maintainer adding a label does not change this policy. Alternatively, start the `ci` workflow with `workflow_dispatch` on that branch to run both macOS jobs.
2. Wait until the required `test-tvos` and `test-ios` jobs are green. On a Dependabot pull request with `full-ci`, `dependabot-macos` requires each path-selected job to succeed, rejects failures and cancellations, and accepts a skip only for paths that do not select that job. It skips on other pull requests and events; manual runs must be reviewed directly.

`full-ci` also runs the `full-ui` job.

[GitHub treats skipped jobs as successful checks](https://docs.github.com/en/actions/how-tos/write-workflows/choose-when-workflows-run/control-jobs-with-conditions), so requiring `dependabot-macos` alone cannot enforce macOS review for an unlabeled pull request. Maintainers must request and review macOS CI before merging dependency updates. These runs keep the existing read-only permissions and do not require repository secrets or `pull_request_target`.
