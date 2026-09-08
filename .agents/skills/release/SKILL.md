---
name: release
description: Prepare release notes and, when explicitly authorized, tag and publish a GitHub release.
---

Always manual. Support --version X.Y.Z, --draft, --prerelease and --no-publish.
Read release configuration, Backlog shipped items, build-plan batch logs and
conventional commits since the last release. Propose the version or use the
explicit version. Prepare CHANGELOG.md and .ship/release-notes-<version>.md
with concrete changes and validation. Do all preparation before any approval
question. --no-publish stops after writing those files, without tagging/pushing.

Before publication, verify the remote default branch, intended commit, clean
release state, existing tags and gh authentication. Respect branch protection:
prepare a release PR when required instead of attempting a direct main push.
Present the version, commit, tag and notes. Use existing explicit authorization
or ask before publishing. Commit release files as needed, tag the exact intended
commit, push the authorized branch/tag and use gh release create with --notes-file
and the requested draft/prerelease flags. Verify the resulting release URL.
If publication partially fails, report the actual tag/release state; do not
silently roll it back or create a second release. Auto-mode never invokes release.
