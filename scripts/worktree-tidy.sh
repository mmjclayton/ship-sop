#!/usr/bin/env bash
# Sort a repository's linked worktrees and, with --apply, remove the safe ones.
#
#   safe    no uncommitted or untracked changes, HEAD reachable from a ref other
#           than its own worktree (a branch worktree: its tip is on the default
#           remote branch), not locked, not the caller's worktree, and idle for at
#           least --min-age-hours. --apply removes it, and deletes its branch.
#   review  uncommitted changes, or commits no other ref holds. Never removed;
#           a person decides.
#   gone    the folder no longer exists. --apply prunes git's record of it.
#   keep    locked, the caller's worktree, or active within --min-age-hours.
#
# Usage: worktree-tidy.sh [--apply] [--min-age-hours N] [repo]
# Exit: 0 done, 1 an --apply step failed, 2 usage or not a repository.
set -euo pipefail

usage() { echo 'Usage: worktree-tidy.sh [--apply] [--min-age-hours N] [repo]' >&2; exit 2; }

APPLY=false
MIN_AGE_HOURS=24
REPO=.
while [ $# -gt 0 ]; do
    case $1 in
        --apply) APPLY=true ;;
        --min-age-hours) [ $# -ge 2 ] || usage; MIN_AGE_HOURS=$2; shift ;;
        -*) usage ;;
        *) REPO=$1 ;;
    esac
    shift
done
case $MIN_AGE_HOURS in ''|*[!0-9]*) echo '--min-age-hours must be a whole number' >&2; exit 2 ;; esac

git -C "$REPO" rev-parse --git-dir >/dev/null 2>&1 || { echo "Not a git repository: $REPO" >&2; exit 2; }

real_dir() { (cd "$1" 2>/dev/null && pwd -P); }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

MAIN=$(git -C "$REPO" worktree list --porcelain | sed -n '1s/^worktree //p')
HERE=$(git rev-parse --show-toplevel 2>/dev/null || true)
[ -z "$HERE" ] || HERE=$(real_dir "$HERE")

DEFAULT=$(git -C "$MAIN" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
if [ -z "$DEFAULT" ]; then
    for candidate in origin/main origin/master main master; do
        if git -C "$MAIN" rev-parse -q --verify "$candidate^{commit}" >/dev/null; then DEFAULT=$candidate; break; fi
    done
fi

NOW=$(date +%s)
MIN_AGE_SECONDS=$((MIN_AGE_HOURS * 3600))
SAFE=0 REVIEW=0 GONE=0 KEEP=0 REMOVED=0 FAILED=0

report() { # category path label reason
    printf '%-6s  %s  %s  %s\n' "$1" "$2" "$3" "$4"
    case $1 in safe) SAFE=$((SAFE + 1)) ;; review) REVIEW=$((REVIEW + 1)) ;; gone) GONE=$((GONE + 1)) ;; keep) KEEP=$((KEEP + 1)) ;; esac
}

# Newest change to the worktree's checkout records. The index is left out: a
# plain `git status` rewrites it, so reading it would reset the age it measures.
last_active() {
    local admin newest=0 t f
    admin=$(git -C "$1" rev-parse --absolute-git-dir 2>/dev/null) || { echo 0; return; }
    for f in "$admin/HEAD" "$admin/logs/HEAD"; do
        [ -e "$f" ] || continue
        t=$(mtime "$f")
        [ "$t" -gt "$newest" ] && newest=$t
    done
    echo "$newest"
}

held_elsewhere() { # sha: does a branch, remote branch or tag contain it?
    [ -n "$(git -C "$MAIN" for-each-ref --count=1 --contains "$1" refs/heads refs/remotes refs/tags 2>/dev/null)" ]
}

remove_safe() { # path branch
    if ! git -C "$MAIN" worktree remove "$1"; then
        echo "  failed to remove $1" >&2; FAILED=$((FAILED + 1)); return
    fi
    REMOVED=$((REMOVED + 1))
    [ -n "$2" ] || return 0
    # Re-check: the tip must still be on the default branch before the branch goes.
    if git -C "$MAIN" merge-base --is-ancestor "refs/heads/$2" "$DEFAULT" 2>/dev/null; then
        git -C "$MAIN" branch -D "$2" >/dev/null || { echo "  removed $1 but kept branch $2" >&2; FAILED=$((FAILED + 1)); }
    fi
}

classify() { # path branch(empty when detached) sha locked prunable
    local path=$1 branch=$2 sha=$3 locked=$4 prunable=$5 label age_days active status track
    label=${branch:-detached ${sha:0:8}}
    if [ "$prunable" = true ] || [ ! -d "$path" ]; then report gone "$path" "$label" 'folder deleted'; return; fi
    if [ "$locked" = true ]; then report keep "$path" "$label" 'locked'; return; fi
    if [ -n "$HERE" ] && [ "$(real_dir "$path")" = "$HERE" ]; then report keep "$path" "$label" 'current worktree'; return; fi

    active=$(last_active "$path")
    age_days=$(( (NOW - active) / 86400 ))
    if ! status=$(git --no-optional-locks -C "$path" status --porcelain 2>/dev/null); then
        report review "$path" "$label" "status unreadable, ${age_days}d idle"; return
    fi
    if [ -n "$status" ]; then
        report review "$path" "$label" "uncommitted changes ($(printf '%s\n' "$status" | wc -l | tr -d ' ') files), ${age_days}d idle"; return
    fi

    if [ -n "$branch" ]; then
        if [ -z "$DEFAULT" ]; then report review "$path" "$label" 'no default branch to compare with'; return; fi
        if ! git -C "$MAIN" merge-base --is-ancestor "refs/heads/$branch" "$DEFAULT" 2>/dev/null; then
            track=$(git -C "$MAIN" for-each-ref --format='%(upstream:track)' "refs/heads/$branch")
            if [ "$track" = '[gone]' ]; then track='; remote branch deleted (merged by squash?)'; else track=''; fi
            report review "$path" "$label" "commits not on $DEFAULT$track, ${age_days}d idle"; return
        fi
    elif ! held_elsewhere "$sha"; then
        report review "$path" "$label" "commits on no branch, ${age_days}d idle"; return
    fi

    if [ $((NOW - active)) -lt "$MIN_AGE_SECONDS" ]; then
        report keep "$path" "$label" "active in the last ${MIN_AGE_HOURS}h"; return
    fi
    report safe "$path" "$label" "clean, nothing unique, ${age_days}d idle"
    [ "$APPLY" = false ] || remove_safe "$path" "$branch"
}

# Porcelain records are blank-line separated; the first is the main worktree.
path='' branch='' sha='' locked=false prunable=false first=true
flush() {
    if [ -n "$path" ]; then
        if [ "$first" = true ]; then first=false; else classify "$path" "$branch" "$sha" "$locked" "$prunable"; fi
    fi
    path='' branch='' sha='' locked=false prunable=false
}
LIST=$(git -C "$MAIN" worktree list --porcelain)
while IFS= read -r line; do
    case $line in
        'worktree '*) flush; path=${line#worktree } ;;
        'HEAD '*) sha=${line#HEAD } ;;
        'branch '*) branch=${line#branch refs/heads/} ;;
        locked|'locked '*) locked=true ;;
        prunable|'prunable '*) prunable=true ;;
    esac
done <<< "$LIST"
flush

if [ "$APPLY" = true ] && [ "$GONE" -gt 0 ]; then
    git -C "$MAIN" worktree prune || { echo '  worktree prune failed' >&2; FAILED=$((FAILED + 1)); }
fi

if [ "$APPLY" = true ]; then
    printf 'Worktrees: %d safe (%d removed), %d need review, %d gone (pruned), %d kept\n' "$SAFE" "$REMOVED" "$REVIEW" "$GONE" "$KEEP"
else
    printf 'Worktrees: %d safe, %d need review, %d gone, %d kept (report only; --apply removes safe and prunes gone)\n' "$SAFE" "$REVIEW" "$GONE" "$KEEP"
fi
[ "$FAILED" -eq 0 ] || exit 1
