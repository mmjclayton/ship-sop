---
description: Cut a tagged GitHub Release. Runs release-notes-writer, prompts for version confirmation, tags the commit, and publishes via gh CLI. Always manual — never auto-fires.
ship_sop_version: "2026-04-25"
---

Generate release notes from the project's tracking files and git history, tag the current commit, and publish a GitHub Release. Always manual — by design, releases are deliberate.

## Arguments

- `--version <X.Y.Z>` — override the auto-bumped version. Skips the bump rule and uses the value as-is.
- `--draft` — create the release as a draft (gh release create --draft). Useful when you want to review the published page before announcing.
- `--prerelease` — mark as prerelease.
- `--no-publish` — write CHANGELOG and notes file but do not tag or publish. Useful for rehearsing the release.

## Pre-flight checks

```bash
# Must be on the default branch
DEFAULT_BRANCH=$(git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@')
CURRENT=$(git rev-parse --abbrev-ref HEAD)

if [ "$CURRENT" != "$DEFAULT_BRANCH" ]; then
    echo "Releases must be cut from the default branch ($DEFAULT_BRANCH). Currently on $CURRENT."
    echo "Switch branches or pass --force-branch (not recommended)."
    exit 1
fi

# Working tree must be clean
if [ -n "$(git status --porcelain)" ]; then
    echo "Working tree is dirty. Commit or stash before releasing."
    exit 1
fi

# Must be up to date with remote
git fetch origin
LOCAL=$(git rev-parse HEAD)
REMOTE=$(git rev-parse origin/$DEFAULT_BRANCH)
if [ "$LOCAL" != "$REMOTE" ]; then
    echo "Local $DEFAULT_BRANCH does not match origin. Pull or push before releasing."
    exit 1
fi

# gh CLI must be authenticated
if ! gh auth status >/dev/null 2>&1; then
    echo "gh CLI is not authenticated. Run: gh auth login"
    exit 1
fi
```

If any check fails, halt and report. Do not attempt to fix automatically — release pre-flight should be conservative.

## Run release-notes-writer

Invoke `@release-notes-writer` to generate:
- `CHANGELOG.md` (updated in place — a new version block prepended)
- `.ship/release-notes-<version>.md` (the body for `gh release create`)

The agent reports the chosen version, source mix, and any uncategorised commits.

## Confirm with operator

Before tagging, surface a confirmation:

```
Release plan:
  Version: <version>
  Tag: v<version>
  Commit: <short-sha> "<commit-subject>"
  Notes: .ship/release-notes-<version>.md (<N> entries)
  Bump source: <feat: commit / BREAKING / --version override>

Proceed? [y/N]
```

If the operator does not confirm, halt — leave CHANGELOG.md and the notes file in place so they can edit and re-run.

## Tag and publish

```bash
# Stage and commit CHANGELOG.md
git add CHANGELOG.md
git commit -m "chore(release): v<version>"

# Tag
git tag -a "v<version>" -m "Release v<version>"

# Push commit + tag
git push origin "$DEFAULT_BRANCH"
git push origin "v<version>"

# Create GitHub Release
GH_FLAGS=""
[ "$DRAFT" = true ] && GH_FLAGS="$GH_FLAGS --draft"
[ "$PRERELEASE" = true ] && GH_FLAGS="$GH_FLAGS --prerelease"

gh release create "v<version>" \
    --title "v<version>" \
    --notes-file ".ship/release-notes-<version>.md" \
    $GH_FLAGS
```

If `--no-publish` was passed, skip tagging, pushing, and `gh release create`. The CHANGELOG and notes file stay on disk for the operator to inspect.

## Output

```markdown
# Release published

Version: v<version>
Tag: v<version>
URL: https://github.com/<owner>/<repo>/releases/tag/v<version>
Status: <published | draft | prerelease>

Files committed:
- CHANGELOG.md (new section: [<version>])

Notes file (kept for reference):
- .ship/release-notes-<version>.md
```

If `--draft`, append a reminder to publish the draft via the GitHub UI or `gh release edit v<version> --draft=false` when ready.

## When this fires

- **Always manual.** No SessionStop hook triggers `/release`. No git pre-push hook calls it.
- The reasoning: ship-sop auto-mode protects code quality on every session. Releases are public artifacts — they get a human pulling the trigger every time.
- If you want pre-push automation, use a project-level git hook or GitHub Actions on tag push, not ship-sop.

## Failure modes

- **gh CLI not authenticated** — pre-flight blocks with clear instruction.
- **Working tree dirty** — pre-flight blocks. The release should reflect main as committed, not local edits.
- **Not on default branch** — pre-flight blocks. Use `--force-branch` only if you really know what you're doing.
- **CHANGELOG already has v<version>** — release-notes-writer surfaces the conflict. Operator either bumps the version or removes the prior entry.
- **`gh release create` fails after tag pushed** — the tag remains; operator can re-run `gh release create v<version> --notes-file ...` directly. Don't auto-rollback the tag — silent rollback is worse than a clear failure.
