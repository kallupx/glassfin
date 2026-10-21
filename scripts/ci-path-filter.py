#!/usr/bin/env python3
"""Write GitHub Actions outputs for the macOS path filters.

Pull request diffs come from the pulls files API. A container checkout of the
merge ref does not always contain the base commit, so `git diff` against that
SHA fails even with `fetch-depth: 0`.
"""

from __future__ import annotations

import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

MACOS_PREFIXES = (
    "Packages/",
    "Apps/",
    "Tests/",
    "project.yml",
    ".github/workflows/",
)


def github_json(url: str):
    token = os.environ.get("GITHUB_TOKEN", "")
    request = urllib.request.Request(
        url,
        headers={
            "Authorization": f"Bearer {token}",
            "Accept": "application/vnd.github+json",
            "User-Agent": "glassfin-ci",
            "X-GitHub-Api-Version": "2022-11-28",
        },
    )
    with urllib.request.urlopen(request) as response:
        return json.load(response)


def pull_request_files() -> list[str]:
    repo = os.environ["GITHUB_REPOSITORY"]
    number = os.environ["PR_NUMBER"]
    files: list[str] = []
    page = 1
    while True:
        url = f"https://api.github.com/repos/{repo}/pulls/{number}/files?per_page=100&page={page}"
        batch = github_json(url)
        files.extend(item["filename"] for item in batch)
        if len(batch) < 100:
            break
        page += 1
    return files


def git_diff(base: str, head: str) -> list[str]:
    output = subprocess.check_output(["git", "diff", "--name-only", base, head], text=True)
    return [line for line in output.splitlines() if line]


def commit_exists(rev: str) -> bool:
    completed = subprocess.run(
        ["git", "rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}"],
        capture_output=True,
        text=True,
    )
    return completed.returncode == 0


def ensure_pr_base() -> str:
    """Return a revision that `git diff` can read.

    A container checkout of the pull request merge ref has failed to resolve
    `pull_request.base.sha` even after `fetch-depth: 0`. Fetch the base branch,
    then the commit itself, before falling back to that SHA.
    """
    sha = os.environ.get("PR_BASE_SHA", "")
    ref = os.environ.get("PR_BASE_REF") or "main"
    remote_ref = f"origin/{ref}"
    if sha and commit_exists(sha):
        return sha
    if not commit_exists(remote_ref):
        subprocess.run(["git", "fetch", "--no-tags", "origin", ref], check=False)
    if commit_exists(remote_ref):
        return remote_ref
    if not sha:
        return remote_ref
    subprocess.run(
        ["git", "fetch", "--no-tags", "origin", f"{sha}:refs/remotes/origin/pr-base"],
        check=True,
    )
    return "refs/remotes/origin/pr-base"


def changed_files() -> list[str]:
    event = os.environ.get("GITHUB_EVENT_NAME", "")
    if event == "workflow_dispatch":
        return ["Packages/GlassfinCore/Package.swift"]
    if event == "pull_request":
        if not os.environ.get("GITHUB_TOKEN"):
            print("GITHUB_TOKEN is empty; using git diff", file=sys.stderr)
        else:
            try:
                return pull_request_files()
            except Exception as error:
                print(f"pulls files API failed ({error}); falling back to git diff", file=sys.stderr)
        return git_diff(ensure_pr_base(), "HEAD")
    base = os.environ.get("PUSH_BEFORE", "")
    head = os.environ.get("GITHUB_SHA", "HEAD")
    if not base or set(base) == {"0"}:
        base = "HEAD^"
    try:
        return git_diff(base, head)
    except subprocess.CalledProcessError:
        repo = os.environ["GITHUB_REPOSITORY"]
        compared = github_json(f"https://api.github.com/repos/{repo}/compare/{base}...{head}")
        return [item["filename"] for item in compared.get("files", [])]


def matches(path: str, prefix: str) -> bool:
    return path == prefix or path.startswith(prefix)


def main() -> None:
    files = changed_files()
    macos = any(matches(path, prefix) for path in files for prefix in MACOS_PREFIXES)
    macos = macos or any(path.endswith("Package.resolved") for path in files)
    ios = any(matches(path, "Apps/iOS/") or matches(path, "Packages/") for path in files)
    if os.environ.get("GITHUB_EVENT_NAME") == "workflow_dispatch":
        macos = True
        ios = True
    output = os.environ.get("GITHUB_OUTPUT")
    lines = f"macos={'true' if macos else 'false'}\nios={'true' if ios else 'false'}\n"
    if output:
        Path(output).open("a", encoding="utf-8").write(lines)
    else:
        print(lines, end="")
    print(f"# {len(files)} changed files", file=sys.stderr)


if __name__ == "__main__":
    main()
