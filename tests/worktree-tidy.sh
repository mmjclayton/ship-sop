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

# Age every worktree except "recent" past the 24-hour guard.
for name in merged detached-held ahead detached-lost dirty locked; do
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
grep -q '^Worktrees: 2 safe, 3 need review, 1 gone, 2 kept (report only' "$WORK/report" \
    || { echo 'FAIL: report summary'; cat "$WORK/report"; exit 1; }
[ "$(git -C "$R" worktree list | wc -l | tr -d ' ')" = 9 ] || { echo 'FAIL: report-only run changed worktrees'; exit 1; }
printf 'PASS: each worktree lands in its category and a report changes nothing\n'

# The caller's own worktree is never a candidate, even when clean and idle.
(cd "$WORK/detached-held" && bash "$TIDY") > "$WORK/report-here"
expect "$WORK/report-here" "$WORK/detached-held" keep
printf 'PASS: the current worktree is kept\n'

(cd "$R" && bash "$TIDY" --apply) > "$WORK/apply"
[ ! -d "$WORK/merged" ] && [ ! -d "$WORK/detached-held" ] || { echo 'FAIL: safe worktrees not removed'; exit 1; }
! git -C "$R" show-ref -q --verify refs/heads/merged || { echo 'FAIL: merged branch not deleted'; exit 1; }
for name in ahead detached-lost dirty locked recent; do
    [ -d "$WORK/$name" ] || { echo "FAIL: $name was removed"; exit 1; }
done
git -C "$R" show-ref -q --verify refs/heads/ahead || { echo 'FAIL: unmerged branch deleted'; exit 1; }
[ -f "$WORK/dirty/untracked.txt" ] || { echo 'FAIL: untracked file lost'; exit 1; }
! git -C "$R" worktree list --porcelain | grep -q "^worktree $WORK/deleted$" || { echo 'FAIL: deleted worktree not pruned'; exit 1; }
grep -q '^Worktrees: 2 safe (2 removed), 3 need review, 1 gone (pruned), 2 kept$' "$WORK/apply" \
    || { echo 'FAIL: apply summary'; cat "$WORK/apply"; exit 1; }
printf 'PASS: --apply removes only safe worktrees and merged branches, and prunes deleted folders\n'

# A second apply has nothing left to remove.
(cd "$R" && bash "$TIDY" --apply) > "$WORK/again"
grep -q '^Worktrees: 0 safe (0 removed), 3 need review, 0 gone (pruned), 2 kept$' "$WORK/again" \
    || { echo 'FAIL: second apply'; cat "$WORK/again"; exit 1; }
printf 'PASS: a repeat run is a no-op\n'

set +e
bash "$TIDY" --min-age-hours x "$R" >/dev/null 2>&1; bad_age=$?
bash "$TIDY" "$WORK" >/dev/null 2>&1; not_repo=$?
set -e
[ "$bad_age" = 2 ] && [ "$not_repo" = 2 ] || { echo "FAIL: usage exits $bad_age and $not_repo, expected 2"; exit 1; }
printf 'PASS: bad arguments and non-repositories exit 2\n'
