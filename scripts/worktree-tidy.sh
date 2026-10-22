#!/usr/bin/env bash
# Sort a repository's linked worktrees and, with --apply, remove the safe ones.
#
#   safe    no uncommitted, untracked or ignored files (regenerable folders such
#           as node_modules excepted, and an untracked symlink with a regenerable
#           name, such as an agent worktree's node_modules link), no rebase, merge or bisect in progress,
#           HEAD contained in a branch, remote branch or tag (a branch worktree:
#           its tip is on the default remote branch), not locked, not the
#           caller's worktree, and idle for at least --min-age-hours. --apply
#           removes it, and deletes its branch.
#   review  anything else that holds work or could not be checked. Never
#           removed; a person decides.
#   gone    the folder no longer exists. --apply prunes git's record of it.
#   keep    locked, the caller's worktree, or active within --min-age-hours.
#
# "Idle" reads the worktree's HEAD and reflog times, so a session that has had a
# clean worktree open for longer without committing is not seen.
#
# Usage: worktree-tidy.sh [--apply] [--min-age-hours N] [repo]
# Exit: 0 done, 1 a step failed (reported on stderr), 2 usage or not a repository.
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

# Ignored folders that a build or install recreates; anything else ignored may be
# the only copy (.env, a local database, data files) and keeps the worktree.
REGENERABLE='node_modules dist build out .next .nuxt .turbo .cache coverage test-results playwright-report __pycache__ .pytest_cache .mypy_cache .ruff_cache .venv venv target .DS_Store'

real_dir() { (cd "$1" 2>/dev/null && pwd -P); }
mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null; }

LIST=$(mktemp)
trap 'rm -f "$LIST"' EXIT
git -C "$REPO" worktree list --porcelain -z > "$LIST" || { echo 'git worktree list failed' >&2; exit 1; }
MAIN=$(tr '\0' '\n' < "$LIST" | sed -n '1s/^worktree //p')
[ -n "$MAIN" ] || { echo 'Could not read the main worktree' >&2; exit 1; }
CWD=$(pwd -P)

# Only a remote-tracking default branch proves a commit is safe elsewhere.
DEFAULT=$(git -C "$MAIN" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)
if [ -z "$DEFAULT" ]; then
    for candidate in origin/main origin/master; do
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
fail() { echo "  $1" >&2; FAILED=$((FAILED + 1)); }

# Newest of the worktree's HEAD and reflog times; prints nothing when neither can
# be read. The index is left out: a plain `git status` rewrites it.
last_active() { # admin-dir
    local newest='' t f
    for f in "$1/HEAD" "$1/logs/HEAD"; do
        [ -e "$f" ] || continue
        t=$(mtime "$f") || continue
        case $t in ''|*[!0-9]*) continue ;; esac
        if [ -z "$newest" ] || [ "$t" -gt "$newest" ]; then newest=$t; fi
    done
    printf '%s' "$newest"
}

in_progress() { # admin-dir: prints the operation git has paused, if any
    local f
    for f in rebase-merge rebase-apply MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD BISECT_LOG; do
        [ ! -e "$1/$f" ] || { printf '%s' "$f"; return; }
    done
}

# Ignored paths outside the regenerable set; prints a count and the first one.
kept_ignored() { # status-with-ignored
    local line entry name count=0 first=''
    while IFS= read -r line; do
        case $line in '!! '*) ;; *) continue ;; esac
        entry=${line#!! }; entry=${entry%/}; name=${entry##*/}
        is_regenerable "$name" && continue
        count=$((count + 1)); [ -n "$first" ] || first=$entry
    done <<< "$1"
    [ "$count" -eq 0 ] || printf '%s (first: %s)' "$count" "$first"
}

is_regenerable() { case " $REGENERABLE " in *" $1 "*) return 0 ;; esac; return 1; }

# Untracked symlinks with a regenerable name (node_modules -> the main checkout's).
# Prints them one per line; the link is removed, never what it points at.
regenerable_links() { # path status
    local line entry
    while IFS= read -r line; do
        case $line in '?? '*) ;; *) continue ;; esac
        entry=${line#?? }
        is_regenerable "${entry##*/}" && [ -L "$1/$entry" ] && printf '%s\n' "$entry"
    done <<< "$2"
    return 0
}

# Status lines that are not ignored files or a regenerable link. A loop rather
# than a pipe: under pipefail an early-exiting grep on a large status reads as
# "no changes".
count_changes() { # status links
    local line count=0 nl=$'\n'
    while IFS= read -r line; do
        case $line in ''|'!! '*) continue ;; esac
        if [ "${line:0:3}" = '?? ' ]; then
            case "$nl$2$nl" in *"$nl${line#?? }$nl"*) continue ;; esac
        fi
        count=$((count + 1))
    done <<< "$1"
    printf '%s' "$count"
}

held_elsewhere() { # sha: does a branch, remote branch or tag contain it?
    local refs
    refs=$(git -C "$MAIN" for-each-ref --count=1 --contains "$1" refs/heads refs/remotes refs/tags) || return 2
    [ -n "$refs" ]
}

remove_safe() { # path branch links
    local rc=0 link
    while IFS= read -r link; do
        [ -n "$link" ] || continue
        [ -L "$1/$link" ] || { fail "kept $1: $link is no longer a symlink"; return; }
        rm -f -- "$1/$link" || { fail "kept $1: could not remove the $link link"; return; }
    done <<< "$3"
    git -C "$MAIN" worktree remove "$1" || { fail "failed to remove $1"; return; }
    REMOVED=$((REMOVED + 1))
    [ -n "$2" ] || return 0
    # Re-check: the tip must still be on the default branch before the branch goes.
    git -C "$MAIN" merge-base --is-ancestor "refs/heads/$2" "$DEFAULT" || rc=$?
    case $rc in
        0) git -C "$MAIN" branch -D "$2" >/dev/null || fail "removed $1 but could not delete branch $2" ;;
        1) echo "  removed $1, kept branch $2: no longer on $DEFAULT" >&2 ;;
        *) fail "removed $1, kept branch $2: merge check failed" ;;
    esac
}

is_current() { # path: is the caller inside this worktree?
    local real
    real=$(real_dir "$1") || return 1
    case $CWD/ in "$real"/*) return 0 ;; esac
    return 1
}

classify() { # path branch(empty when detached) sha locked prunable
    local path=$1 branch=$2 sha=$3 locked=$4 prunable=$5 label admin active idle op status changes links ignored rc=0 track
    label=${branch:-detached ${sha:0:8}}
    if [ "$locked" = true ]; then report keep "$path" "$label" 'locked'; return; fi
    if [ "$prunable" = true ] || [ ! -d "$path" ]; then report gone "$path" "$label" 'folder deleted'; return; fi
    if is_current "$path"; then report keep "$path" "$label" 'current worktree'; return; fi

    if ! admin=$(git -C "$path" rev-parse --absolute-git-dir 2>/dev/null); then
        report review "$path" "$label" 'git records unreadable'; return
    fi
    active=$(last_active "$admin")
    if [ -z "$active" ]; then report review "$path" "$label" 'age unreadable'; return; fi
    idle="$(( (NOW - active) / 86400 ))d idle"

    op=$(in_progress "$admin")
    if [ -n "$op" ]; then report review "$path" "$label" "$op in progress, $idle"; return; fi
    if ! status=$(git --no-optional-locks -C "$path" status --porcelain --ignored=matching 2>/dev/null); then
        report review "$path" "$label" "status unreadable, $idle"; return
    fi
    links=$(regenerable_links "$path" "$status")
    changes=$(count_changes "$status" "$links")
    if [ "$changes" -gt 0 ]; then
        report review "$path" "$label" "uncommitted changes ($changes files), $idle"; return
    fi
    ignored=$(kept_ignored "$status")
    if [ -n "$ignored" ]; then report review "$path" "$label" "ignored files $ignored, $idle"; return; fi

    if [ -n "$branch" ]; then
        if [ -z "$DEFAULT" ]; then report review "$path" "$label" 'no default remote branch to compare with'; return; fi
        git -C "$MAIN" merge-base --is-ancestor "refs/heads/$branch" "$DEFAULT" 2>/dev/null || rc=$?
        if [ "$rc" -gt 1 ]; then report review "$path" "$label" "merge check failed, $idle"; return; fi
        if [ "$rc" -eq 1 ]; then
            track=$(git -C "$MAIN" for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null) || track=''
            if [ "$track" = '[gone]' ]; then track='; remote branch deleted (merged by squash?)'; else track=''; fi
            report review "$path" "$label" "commits not on $DEFAULT$track, $idle"; return
        fi
    else
        held_elsewhere "$sha" || rc=$?
        if [ "$rc" -eq 2 ]; then report review "$path" "$label" "ref check failed, $idle"; return; fi
        if [ "$rc" -eq 1 ]; then report review "$path" "$label" "commits on no branch, $idle"; return; fi
    fi

    if [ $((NOW - active)) -lt "$MIN_AGE_SECONDS" ]; then
        report keep "$path" "$label" "active in the last ${MIN_AGE_HOURS}h"; return
    fi
    report safe "$path" "$label" "clean, nothing unique, $idle"
    [ "$APPLY" = false ] || remove_safe "$path" "$branch" "$links"
}

# NUL-separated fields, an empty field between records (so a path holding a
# newline cannot forge a record); the first record is the main worktree.
path='' branch='' sha='' locked=false prunable=false first=true
flush() {
    if [ -n "$path" ]; then
        if [ "$first" = true ]; then first=false; else classify "$path" "$branch" "$sha" "$locked" "$prunable"; fi
    fi
    path='' branch='' sha='' locked=false prunable=false
}
while IFS= read -r -d '' line; do
    case $line in
        '') flush ;;
        'worktree '*) flush; path=${line#worktree } ;;
        'HEAD '*) sha=${line#HEAD } ;;
        'branch '*) branch=${line#branch refs/heads/} ;;
        locked|'locked '*) locked=true ;;
        prunable|'prunable '*) prunable=true ;;
    esac
done < "$LIST"
flush

PRUNED=0
if [ "$APPLY" = true ] && [ "$GONE" -gt 0 ]; then
    if git -C "$MAIN" worktree prune; then PRUNED=$GONE; else fail 'worktree prune failed'; fi
fi

if [ "$APPLY" = true ]; then
    printf 'Worktrees: %d safe (%d removed), %d need review, %d gone (%d pruned), %d kept\n' "$SAFE" "$REMOVED" "$REVIEW" "$GONE" "$PRUNED" "$KEEP"
else
    printf 'Worktrees: %d safe, %d need review, %d gone, %d kept (report only; --apply removes safe and prunes gone)\n' "$SAFE" "$REVIEW" "$GONE" "$KEEP"
fi
[ "$FAILED" -eq 0 ] || exit 1
