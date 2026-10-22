#!/usr/bin/env bash
set -euo pipefail
SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
TIDY="$SOURCE/scripts/worktree-tidy.sh"
WORK=$(cd "$(mktemp -d)" && pwd -P)
trap 'rm -rf "$WORK"' EXIT
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t

git init -q --bare -b main "$WORK/origin.git"
git clone -q "$WORK/origin.git" "$WORK/repo" 2>/dev/null
R="$WORK/repo"
git -C "$R" commit -q --allow-empty -m base
git -C "$R" push -q origin main
git -C "$R" remote set-head origin main

# One worktree per category.
git -C "$R" worktree add -q -b merged "$WORK/merged" main
git -C "$R" worktree add -q --detach "$WORK/detached-held" main
git -C "$R" worktree add -q -b ahead "$WORK/ahead" main
git -C "$WORK/ahead" commit -q --allow-empty -m 'not on main'
git -C "$R" worktree add -q --detach "$WORK/detached-lost" main
git -C "$WORK/detached-lost" commit -q --allow-empty -m 'on no branch'
git -C "$R" worktree add -q --detach "$WORK/dirty" main
printf 'x\n' > "$WORK/dirty/untracked.txt"
git -C "$R" worktree add -q --detach "$WORK/locked" main
git -C "$R" worktree lock "$WORK/locked"
git -C "$R" worktree add -q --detach "$WORK/deleted" main
rm -rf "$WORK/deleted"
git -C "$R" worktree add -q --detach "$WORK/recent" main
# Ignored files: a regenerable folder does not keep a worktree, a .env does.
printf 'node_modules/\n.env\n' >> "$R/.git/info/exclude"
git -C "$R" worktree add -q --detach "$WORK/regenerable" main
mkdir -p "$WORK/regenerable/web/node_modules/x"; printf 'x\n' > "$WORK/regenerable/web/node_modules/x/i.js"
git -C "$R" worktree add -q --detach "$WORK/secrets" main
printf 'KEY=1\n' > "$WORK/secrets/.env"
# An agent worktree's node_modules link to the main checkout is regenerable; a
# plain untracked file with that name is not.
mkdir -p "$WORK/shared-modules/pkg"; printf 'x\n' > "$WORK/shared-modules/pkg/i.js"
git -C "$R" worktree add -q --detach "$WORK/linked" main
ln -s "$WORK/shared-modules" "$WORK/linked/node_modules"
git -C "$R" worktree add -q --detach "$WORK/fake-link" main
printf 'not a link\n' > "$WORK/fake-link/node_modules"
# A status larger than a pipe buffer is still read as changed.
git -C "$R" worktree add -q --detach "$WORK/big" main
(cd "$WORK/big" && seq -f 'untracked-file-with-a-long-name-%05g.txt' 1 4000 | xargs touch)
# A paused operation keeps an otherwise clean worktree.
git -C "$R" worktree add -q --detach "$WORK/bisecting" main
touch "$(git -C "$WORK/bisecting" rev-parse --absolute-git-dir)/BISECT_LOG"

# Age every worktree except "recent" past the 24-hour guard.
for name in merged detached-held ahead detached-lost dirty locked regenerable secrets bisecting linked fake-link big; do
    admin=$(git -C "$WORK/$name" rev-parse --absolute-git-dir)
    for f in "$admin/HEAD" "$admin/logs/HEAD" "$admin/index"; do [ ! -e "$f" ] || touch -t 202001010000 "$f"; done
done
# A fresh index (as `git status` leaves) must not count as activity.
touch "$(git -C "$WORK/merged" rev-parse --absolute-git-dir)/index"

category() { awk -v p="$2" '$2 == p {print $1}' "$1"; }
expect() { # output path category
    [ "$(category "$1" "$2")" = "$3" ] || { echo "FAIL: $2 is '$(category "$1" "$2")', expected $3"; cat "$1"; exit 1; }
}

(cd "$R" && bash "$TIDY") > "$WORK/report"
expect "$WORK/report" "$WORK/merged" safe
expect "$WORK/report" "$WORK/detached-held" safe
expect "$WORK/report" "$WORK/ahead" review
expect "$WORK/report" "$WORK/detached-lost" review
expect "$WORK/report" "$WORK/dirty" review
expect "$WORK/report" "$WORK/locked" keep
expect "$WORK/report" "$WORK/deleted" gone
expect "$WORK/report" "$WORK/recent" keep
expect "$WORK/report" "$WORK/regenerable" safe
expect "$WORK/report" "$WORK/secrets" review
expect "$WORK/report" "$WORK/bisecting" review
expect "$WORK/report" "$WORK/linked" safe
expect "$WORK/report" "$WORK/fake-link" review
expect "$WORK/report" "$WORK/big" review
grep -q "big  .*uncommitted changes (4000 files)" "$WORK/report" || { echo 'FAIL: large status count'; cat "$WORK/report"; exit 1; }
grep -q "secrets  .*ignored files 1 (first: .env)" "$WORK/report" || { echo 'FAIL: ignored-file reason'; cat "$WORK/report"; exit 1; }
grep -q '^Worktrees: 4 safe, 7 need review, 1 gone, 2 kept (report only' "$WORK/report" \
    || { echo 'FAIL: report summary'; cat "$WORK/report"; exit 1; }
[ "$(git -C "$R" worktree list | wc -l | tr -d ' ')" = 15 ] || { echo 'FAIL: report-only run changed worktrees'; exit 1; }
printf 'PASS: each worktree lands in its category and a report changes nothing\n'

# The caller's own worktree is never a candidate, even when clean and idle.
(cd "$WORK/detached-held" && bash "$TIDY") > "$WORK/report-here"
expect "$WORK/report-here" "$WORK/detached-held" keep
(cd "$WORK/detached-held/sub" 2>/dev/null || { mkdir "$WORK/detached-held/sub"; cd "$WORK/detached-held/sub"; } && bash "$TIDY" "$R") > "$WORK/report-sub"
expect "$WORK/report-sub" "$WORK/detached-held" keep
rmdir "$WORK/detached-held/sub"
printf 'PASS: the current worktree is kept, from a subfolder and with the repo named\n'

# An age that cannot be read is review, never treated as old.
mkdir -p "$WORK/bin"; printf '#!/bin/sh\nexit 1\n' > "$WORK/bin/stat"; chmod +x "$WORK/bin/stat"
(cd "$R" && PATH="$WORK/bin:$PATH" bash "$TIDY") > "$WORK/report-noage"
expect "$WORK/report-noage" "$WORK/merged" review
grep -q 'merged  age unreadable' "$WORK/report-noage" || { echo 'FAIL: age unreadable reason'; cat "$WORK/report-noage"; exit 1; }
grep -q '^Worktrees: 0 safe' "$WORK/report-noage" || { echo 'FAIL: unreadable age counted safe'; cat "$WORK/report-noage"; exit 1; }
printf 'PASS: an unreadable age is review\n'

(cd "$R" && bash "$TIDY" --apply) > "$WORK/apply"
[ ! -d "$WORK/merged" ] && [ ! -d "$WORK/detached-held" ] || { echo 'FAIL: safe worktrees not removed'; exit 1; }
! git -C "$R" show-ref -q --verify refs/heads/merged || { echo 'FAIL: merged branch not deleted'; exit 1; }
[ ! -d "$WORK/regenerable" ] && [ ! -e "$WORK/linked" ] || { echo 'FAIL: regenerable-only worktree not removed'; exit 1; }
[ -f "$WORK/shared-modules/pkg/i.js" ] || { echo 'FAIL: link target touched'; exit 1; }
for name in ahead detached-lost dirty locked recent secrets bisecting fake-link big; do
    [ -d "$WORK/$name" ] || { echo "FAIL: $name was removed"; exit 1; }
done
git -C "$R" show-ref -q --verify refs/heads/ahead || { echo 'FAIL: unmerged branch deleted'; exit 1; }
[ -f "$WORK/dirty/untracked.txt" ] && [ -f "$WORK/secrets/.env" ] || { echo 'FAIL: untracked or ignored file lost'; exit 1; }
! git -C "$R" worktree list --porcelain | grep -q "^worktree $WORK/deleted$" || { echo 'FAIL: deleted worktree not pruned'; exit 1; }
grep -q '^Worktrees: 4 safe (4 removed), 7 need review, 1 gone (1 pruned), 2 kept$' "$WORK/apply" \
    || { echo 'FAIL: apply summary'; cat "$WORK/apply"; exit 1; }
printf 'PASS: --apply removes only safe worktrees, their node_modules links (not the target) and merged branches, and prunes deleted folders\n'

# A second apply has nothing left to remove.
(cd "$R" && bash "$TIDY" --apply) > "$WORK/again"
grep -q '^Worktrees: 0 safe (0 removed), 7 need review, 0 gone (0 pruned), 2 kept$' "$WORK/again" \
    || { echo 'FAIL: second apply'; cat "$WORK/again"; exit 1; }
printf 'PASS: a repeat run is a no-op\n'

# Without a remote default branch, a branch worktree cannot be shown merged.
git init -q -b main "$WORK/local"
git -C "$WORK/local" commit -q --allow-empty -m base
git -C "$WORK/local" worktree add -q -b topic "$WORK/local-topic" main
admin=$(git -C "$WORK/local-topic" rev-parse --absolute-git-dir)
touch -t 202001010000 "$admin/HEAD" "$admin/logs/HEAD"
(cd "$WORK/local" && bash "$TIDY" --apply) > "$WORK/local-report"
expect "$WORK/local-report" "$WORK/local-topic" review
[ -d "$WORK/local-topic" ] || { echo 'FAIL: worktree removed without a remote default'; exit 1; }
printf 'PASS: no remote default branch means review\n'

set +e
bash "$TIDY" --min-age-hours x "$R" >/dev/null 2>&1; bad_age=$?
bash "$TIDY" "$WORK" >/dev/null 2>&1; not_repo=$?
set -e
[ "$bad_age" = 2 ] && [ "$not_repo" = 2 ] || { echo "FAIL: usage exits $bad_age and $not_repo, expected 2"; exit 1; }
printf 'PASS: bad arguments and non-repositories exit 2\n'
