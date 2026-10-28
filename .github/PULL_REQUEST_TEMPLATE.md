## Summary

## How to test

## Dependency updates

If this is a grouped Dependabot pull request, add `full-ci` before merging and keep auto-merge off. Every macOS job selected by the path filters must succeed. With `full-ci` and no selected macOS paths, the gate passes without a macOS build, including for GitHub Actions updates.

- [ ] `full-ci` label added (`workflow_dispatch` does not satisfy the pull request gate)
- [ ] `test-tvos` green if selected by the path filter
- [ ] `test-ios` green if selected by the path filter
- [ ] `dependabot-macos` green
