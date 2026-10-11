#!/usr/bin/env bash
#
# Validate Backlog.md state-tag transitions against the allowed graph.
#
# Run before committing a Backlog.md change. Rejects illegal transitions like
# [OPEN] -> [SHIPPED] with no [IN PROGRESS] intermediate, terminal-state
# revivals, and [SHIPPED] Feature/Refactor entries with no review citation.
# Exit code: 0 if all transitions legal, 1 if any illegal.
#
# Usage:
#   bash scripts/validate-state-transitions.sh
#     Default: compares HEAD's Backlog.md against the working tree, so it
#     validates exactly the changes about to be committed. No-ops when there
#     is no working-tree diff (nothing to validate).
#
#   bash scripts/validate-state-transitions.sh --before <ref>
#     Compares working-tree Backlog.md against <ref>:Backlog.md. Use with
#     merge-base to replay a whole branch's transitions.
#
#   bash scripts/validate-state-transitions.sh --before-file <path> --after-file <path>
#     Fixture mode - no git required. Used by the test harness.
#
#   bash scripts/validate-state-transitions.sh --assert-review <path>
#     Substance-assertion helper. Checks a review artifact has
#     the three required sections (diff summary, severity, finding).
#
# Bash 3.2 (macOS default); no associative arrays.

set -euo pipefail

MODE="validate"
BEFORE_REF=""
BEFORE_FILE=""
AFTER_FILE="Backlog.md"
TRACKED_PATH="Backlog.md"   # path used with `git show <ref>:<path>`
ASSERT_REVIEW_FILE=""
SELF_MOD_CHANGED_FILE=""    # fixture: file listing changed paths for the review trigger (b) check

print_help() {
  # Print the leading comment block, stopping at the first non-comment line.
  # A hardcoded line range silently truncated (or over-ran into `set -euo
  # pipefail`) every time the usage text changed length.
  awk 'NR > 1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "$0"
}

while [ $# -gt 0 ]; do
  case "$1" in
    --before) BEFORE_REF="$2"; shift 2 ;;
    --before-file) BEFORE_FILE="$2"; shift 2 ;;
    --after-file) AFTER_FILE="$2"; shift 2 ;;
    --assert-review) MODE="assert-review"; ASSERT_REVIEW_FILE="$2"; shift 2 ;;
    --self-mod-changed-file) SELF_MOD_CHANGED_FILE="$2"; shift 2 ;;
    -h|--help) print_help; exit 0 ;;
    *) echo "Unknown arg: $1" >&2; exit 2 ;;
  esac
done

# ---------------------------------------------------------------------------
# --assert-review: P44 substance-assertion helper
# ---------------------------------------------------------------------------
if [ "$MODE" = "assert-review" ]; then
  if [ -z "$ASSERT_REVIEW_FILE" ] || [ ! -f "$ASSERT_REVIEW_FILE" ]; then
    echo "BLOCK: review artifact not found: $ASSERT_REVIEW_FILE" >&2
    exit 1
  fi

  missing=""

  # 1. Diff summary — match any of: "## Summary", "## Diff summary", "Diff summary:"
  if ! grep -qiE '^(##+ .*summary|diff summary:)' "$ASSERT_REVIEW_FILE"; then
    missing="$missing diff-summary-section"
  fi

  # 2. Severity line — must have a value from the enum
  if ! grep -qE '[Ss]everity:[[:space:]]*(CRITICAL|HIGH|MEDIUM|LOW|NONE)\b' "$ASSERT_REVIEW_FILE"; then
    missing="$missing severity-line"
  fi

  # 3. At least one concrete finding OR a reasoned no-issues statement,
  #    AND the finding/no-issues body must contain a concrete anchor — a
  #    file path with line number (`foo.ts:42`) or a backticked symbol/path
  #    (`processOrder`, `scripts/foo.sh`). Sycophancy gate (P55): reviews
  #    that pass structurally but cite nothing concrete are blocked here.
  #    Anthropic's 30 April 2026 personal-guidance research measured 9% baseline /
  #    25-38% emotional-domain validation rates even in frontier models
  #    trained against sycophancy. Reviewer-as-peer-agent carries the
  #    same load. Cite or fail.
  has_findings=0
  has_anchor=0
  ANCHOR_RE='(`[A-Za-z_][A-Za-z0-9_./:-]*`|[A-Za-z0-9_./-]+\.[a-zA-Z]+:[0-9]+)'

  if grep -qiE '^##+[[:space:]]+findings?\b' "$ASSERT_REVIEW_FILE"; then
    # awk exits 0 if Findings has body+anchor, 2 if body but no anchor,
    # 1 if no body at all. Defused with `|| awk_exit=$?` to keep set -e happy.
    awk_exit=0
    awk '
      tolower($0) ~ /^##+[[:space:]]+findings?([[:space:]]|$)/ { in_f=1; next }
      in_f && /^##+ / { in_f=0 }
      in_f && NF { found=1 }
      in_f && /(`[A-Za-z_][A-Za-z0-9_.:\/-]*`|[A-Za-z0-9_.\/-]+\.[a-zA-Z]+:[0-9]+)/ { anchor=1 }
      END { exit (found ? (anchor ? 0 : 2) : 1) }
    ' "$ASSERT_REVIEW_FILE" || awk_exit=$?
    case "$awk_exit" in
      0) has_findings=1; has_anchor=1 ;;
      2) has_findings=1 ;;
      *) ;;
    esac
  fi

  if [ "$has_findings" = "0" ]; then
    # fallback: reasoned no-issues — same anchor rule applied to the line
    if grep -qiE 'no issues[[:space:]]*[—:-][[:space:]]*\S+[[:space:]]+\S+' "$ASSERT_REVIEW_FILE"; then
      has_findings=1
      if grep -iE 'no issues' "$ASSERT_REVIEW_FILE" | grep -qE "$ANCHOR_RE"; then
        has_anchor=1
      fi
    fi
  fi

  [ "$has_findings" = "0" ] && missing="$missing concrete-finding-or-reasoned-no-issues"
  [ "$has_findings" = "1" ] && [ "$has_anchor" = "0" ] && missing="$missing anchor-in-findings"

  if [ -n "$missing" ]; then
    echo "BLOCK: review artifact $ASSERT_REVIEW_FILE missing:$missing" >&2
    echo "Required: diff summary heading, Severity: <enum>, Findings section (or reasoned 'No issues — <reason>'), and at least one concrete anchor inside findings/no-issues — a file path with line number (e.g. \`foo.ts:42\`) or a backticked symbol or path (e.g. \`processOrder\`, \`scripts/foo.sh\`)." >&2
    echo "Sycophancy gate: reviews that pass structurally but cite nothing concrete are blocked." >&2
    exit 1
  fi
  exit 0
fi

# ---------------------------------------------------------------------------
# Default: validate state transitions
# ---------------------------------------------------------------------------

# Extract (P-number, normalised-status) pairs from a Backlog file.
# Only matches items in the main "P-Numbered Items" section — the Shipped
# Archive uses bullet lines, not ### headings.
extract_statuses() {
  awk '
    /^### P[0-9]+/ {
      match($0, /P[0-9]+/)
      p = substr($0, RSTART, RLENGTH)
      next
    }
    p && /^`\[/ {
      line = $0
      gsub(/`/, "", line)
      if (match(line, /^\[[^]]+\]/)) {
        status = substr(line, RSTART, RLENGTH)
        # normalise: strip trailing " - ..." suffix inside the first bracket
        sub(/ +- +[^]]*\]$/, "]", status)
        print p "\t" status
      }
      p = ""
    }
  ' "$1"
}

# Is the transition from $1 to $2 legal? Returns 0 (legal) or 1 (illegal).
transition_is_legal() {
  local from="$1" to="$2"
  [ "$from" = "$to" ] && return 0   # no-op always legal

  if [ "$from" = "<absent>" ]; then
    case "$to" in
      "[OPEN]"|"[DEFERRED]"|"[IN PROGRESS]") return 0 ;;
      *) return 1 ;;
    esac
  fi

  case "$from" in
    "[OPEN]")
      case "$to" in "[IN PROGRESS]"|"[DEFERRED]"|"[SHIPPED]"|"[WON'T]") return 0 ;; esac
      ;;
    "[IN PROGRESS]")
      case "$to" in "[BLOCKED]"|"[DEFERRED]"|"[SHIPPED]"|"[WON'T]") return 0 ;; esac
      ;;
    "[BLOCKED]")
      case "$to" in "[IN PROGRESS]"|"[DEFERRED]"|"[SHIPPED]"|"[WON'T]") return 0 ;; esac
      ;;
    "[DEFERRED]")
      case "$to" in "[IN PROGRESS]"|"[SHIPPED]"|"[WON'T]"|"[BLOCKED]") return 0 ;; esac
      ;;
    "[SHIPPED]")
      case "$to" in "[VERIFIED]") return 0 ;; esac
      ;;
    "[VERIFIED]"|"[WON'T]")
      return 1   # terminal
      ;;
  esac
  return 1
}

legal_paths_from() {
  case "$1" in
    "<absent>") echo "[OPEN], [DEFERRED], [IN PROGRESS]" ;;
    "[OPEN]") echo "[IN PROGRESS], [DEFERRED], [SHIPPED] (Feature/Refactor cites a review), [WON'T]" ;;
    "[IN PROGRESS]") echo "[BLOCKED], [DEFERRED], [SHIPPED] (Feature/Refactor cites a review), [WON'T]" ;;
    "[BLOCKED]") echo "[IN PROGRESS], [DEFERRED], [SHIPPED] (Feature/Refactor cites a review), [WON'T]" ;;
    "[DEFERRED]") echo "[IN PROGRESS], [SHIPPED] (Feature/Refactor cites a review), [WON'T], [BLOCKED]" ;;
    "[SHIPPED]") echo "[VERIFIED]" ;;
    "[VERIFIED]"|"[WON'T]") echo "(terminal — revival requires new P-number)" ;;
  esac
}

# Resolve the before-state contents onto stdout. Empty output = skip validation.
#
# Default: compare HEAD's Backlog.md against the working tree (what is about
# to be committed). Earlier commits are assumed already validated, or can be
# revalidated with `--before <merge-base>` explicitly.
#
# Override precedence: --before-file > --before <ref> > HEAD (default).
# ── Review trigger (b): self-modification ────────────────────────────────────
#
# Edits to files an agent executes or follows as instructions (reviewer
# agents, commands, skills, the push gate, this validator) need a review
# whatever the diff size, so a self-declared `docs-only` skip cannot pass them.
#
# Tag-independent, deliberately: a [Bug] or [Refactor] tag is a poor proxy for
# risk on these paths.
sop_self_mod_paths() {
  printf '%s\n' "$1" | grep -E '^(\.claude/agents/|\.claude/commands/|\.agents/skills/|\.codex/agents/|scripts/hooks/|scripts/validate-)' || true
}

session_changed_files() {
  local default_branch="" base head_sha range="" committed worktree
  default_branch=$( { git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null || true; } | sed 's@^refs/remotes/@@')
  if [ -z "$default_branch" ]; then
    for candidate in origin/main origin/master origin/develop; do
      if git rev-parse --verify "$candidate" >/dev/null 2>&1; then default_branch="$candidate"; break; fi
    done
  fi
  if [ -n "$default_branch" ]; then
    base=$( { git merge-base "$default_branch" HEAD 2>/dev/null || true; } )
    head_sha=$( { git rev-parse HEAD 2>/dev/null || true; } )
    if [ -n "$base" ] && [ "$base" != "$head_sha" ]; then range="$base..HEAD"; fi
  fi
  committed=""
  [ -n "$range" ] && committed=$( { git diff --name-only "$range" 2>/dev/null || true; } )
  worktree=$( { git diff --name-only HEAD 2>/dev/null || true; } )
  printf '%s\n%s\n' "$committed" "$worktree" | grep -v '^$' | sort -u || true
}

resolve_before() {
  if [ -n "$BEFORE_FILE" ]; then
    # Explicit `return 0`, not a bare `return`. A bare return inherits the
    # exit status of the preceding `&&` list, so a missing --before-file made
    # this function return 1 — and because it is called as a plain statement
    # (`resolve_before > "$TMP_BEFORE"`), errexit killed the script before the
    # "no before-state ... Skipping" message below could print. The symptom was
    # exit 1 with zero bytes on both stdout and stderr: the same silent-failure
    # class as the P73 pipefail bug, in a different shape.
    if [ -f "$BEFORE_FILE" ]; then
      cat "$BEFORE_FILE"
    fi
    return 0
  fi
  local ref="${BEFORE_REF:-HEAD}"
  # Verify ref exists — else skip (fresh repo with no commits)
  git rev-parse --verify "${ref}" >/dev/null 2>&1 || return 0
  # Check whether there is any working-tree difference against the ref. If
  # not and ref=HEAD, skip (nothing to validate).
  if [ "$ref" = "HEAD" ] && git diff --quiet HEAD -- "$TRACKED_PATH" 2>/dev/null; then
    return 0
  fi
  git show "${ref}:${TRACKED_PATH}" 2>/dev/null || true
}

TMP_BEFORE=$(mktemp)
trap 'rm -f "$TMP_BEFORE" "${AFTER_CLEAN:-}"' EXIT

resolve_before > "$TMP_BEFORE"
if [ ! -s "$TMP_BEFORE" ]; then
  echo "validate-state-transitions: no before-state (on default branch or fresh repo). Skipping."
  exit 0
fi

if [ ! -f "$AFTER_FILE" ]; then
  echo "BLOCK: after-file not found: $AFTER_FILE" >&2
  exit 1
fi

BEFORE_STATES=$(extract_statuses "$TMP_BEFORE")
AFTER_STATES=$(extract_statuses "$AFTER_FILE")

violations=0
warnings=0

# Iterate every P-number in the after-state. P-numbers that disappear from
# after are ignored — removal isn't a legitimate transition (Rule 1), but
# the "never delete" rule is a separate concern covered by grep-based checks.
while IFS=$'\t' read -r p after_status; do
  [ -z "$p" ] && continue
  before_status=$(printf '%s\n' "$BEFORE_STATES" | awk -F'\t' -v p="$p" '$1 == p { print $2; exit }')
  [ -z "$before_status" ] && before_status="<absent>"

  if transition_is_legal "$before_status" "$after_status"; then
    # Soft warning: [BLOCKED] ↔ [DEFERRED] with no decision-file reference
    case "${before_status}->${after_status}" in
      "[BLOCKED]->[DEFERRED]"|"[DEFERRED]->[BLOCKED]")
        if [ -z "$BEFORE_FILE" ]; then
          # only check when we have a real git range (not fixture mode)
          range_ref="${BEFORE_REF:-}"
          if [ -z "$range_ref" ]; then
            range_ref=$(git merge-base HEAD '@{upstream}' 2>/dev/null || git merge-base HEAD origin/main 2>/dev/null || echo "")
          fi
          if [ -n "$range_ref" ]; then
            if ! git log "${range_ref}..HEAD" --name-only --format= 2>/dev/null | grep -qE "docs/agent-memory/decisions/.*${p}[^0-9]"; then
              echo "WARN: $p transitioned $before_status -> $after_status with no decision-file reference in commit range"
              warnings=$((warnings + 1))
            fi
          fi
        fi
        ;;
    esac

    # [SHIPPED] transitions of a [Feature]/[Refactor] item (or any item when the
    # branch touched an executable instruction surface, trigger (b)) must
    # cite a review artifact under docs/reviews/ or declare an enumerated skip
    # — on the Backlog entry itself. Until P105 (2026-09-05) the citation lived
    # on a Batch Log line in docs/build-plans/; a measured review found the
    # Batch Log read by nothing else, so the entry is now the single place.
    if [ "$after_status" = "[SHIPPED]" ] && [ "$before_status" != "[SHIPPED]" ]; then
      # Bounded at the next `### ` or `## ` heading (a `## Shipped Archive`
      # after the last entry must not lend it a citation), anchored the same
      # way extract_statuses anchors (`### P<n>` followed by a non-digit), and
      # CRLF-tolerant. An entry that cannot be located fails closed below.
      # No early exit in the pipeline: an awk `exit` or `grep -q` that stops
      # reading while `tr` is still writing a file larger than the pipe buffer
      # gives tr SIGPIPE, pipefail reports 141, and errexit ends the script
      # with no message — the P73 shape, reproduced on the real Backlog when
      # the shipped entry sat early in the file. CR is stripped once, to a
      # temp file, and awk reads it to the end.
      if [ -z "${AFTER_CLEAN:-}" ]; then
        AFTER_CLEAN=$(mktemp); tr -d '\r' < "$AFTER_FILE" > "$AFTER_CLEAN"
      fi
      entry_body=$(awk -v p="### ${p}" '
        $0 ~ "^"p"([^0-9]|$)" { found=1; next }
        found && /^(### |## )/ { found=0 }
        found { print }
      ' "$AFTER_CLEAN")
      if ! grep -qE "^### ${p}([^0-9]|$)" "$AFTER_CLEAN"; then
        echo "BLOCK: $p transitioned to [SHIPPED] but its entry heading could not be located in Backlog.md (expected a line starting \"### ${p}\")."
        violations=$((violations + 1))
        continue
      fi
      # Only labelled lines outside code fences count (review: HIGH): a path
      # quoted as an example, or a skip token in prose, is not a declaration.
      # The citation is a bare filename under docs/reviews/ — no slash after
      # it, so `..` cannot reach a file that is not a review (review: CRITICAL).
      review_lines=$(printf '%s\n' "$entry_body" | awk '/^[[:space:]]*```/{f=!f; next} !f' | grep -E '^[[:space:]]*review( skipped)?[: (]' || true)
      item_type=$(printf '%s\n' "$entry_body" | awk '
        !done && /^`\[/ {
          line=$0
          gsub(/`/, "", line)
          sub(/^\[[^]]+\][[:space:]]*/, "", line)
          if (match(line, /^\[[^]]+\]/)) { print substr(line, RSTART+1, RLENGTH-2) }
          done=1
        }')
      # Trigger (b), P87. Resolve once per run, not per item.
      if [ -z "${SELF_MOD_CHECKED:-}" ]; then
        SELF_MOD_CHECKED=1
        if [ -n "$SELF_MOD_CHANGED_FILE" ] && [ -f "$SELF_MOD_CHANGED_FILE" ]; then
          SELF_MOD_FILES=$(sop_self_mod_paths "$(cat "$SELF_MOD_CHANGED_FILE")")
        else
          SELF_MOD_FILES=$(sop_self_mod_paths "$(session_changed_files)")
        fi
      fi
      gate_type="$item_type"
      if [ -n "${SELF_MOD_FILES:-}" ]; then
        gate_type="Feature"
      fi

      case "$gate_type" in
        "Feature"|"Refactor")
          # The skip must name its own P-number and use the enumerated set
          # (P66); under trigger (b) only test-only and dep-bump survive.
          skip_re="review skipped \(${p}\): *(docs-only|test-only|dep-bump|below-threshold)\b"
          if [ -n "${SELF_MOD_FILES:-}" ]; then
            skip_re="review skipped \(${p}\): *(test-only|dep-bump)\b"
          fi
          if printf '%s' "$review_lines" | grep -qE '^[[:space:]]*review:[[:space:]]*docs/reviews/'; then
            # A citation is not evidence until the path resolves (P95).
            missing_reviews=""
            for cited in $(printf '%s' "$review_lines" | grep -oE '^[[:space:]]*review:[[:space:]]*docs/reviews/[A-Za-z0-9._-]+\.md' | sed -E 's/^[[:space:]]*review:[[:space:]]*//'); do
              [ -f "$cited" ] || missing_reviews="$missing_reviews $cited"
            done
            [ -n "$missing_reviews" ] || [ -n "$(printf '%s' "$review_lines" | grep -oE '^[[:space:]]*review:[[:space:]]*docs/reviews/[A-Za-z0-9._-]+\.md')" ] || missing_reviews=" (a review: line with a path that is not a bare filename under docs/reviews/)"
            if [ -n "$missing_reviews" ]; then
              echo "BLOCK: $p ([${item_type}]) cites a review artifact that does not exist:${missing_reviews}"
              echo "  A cited path that does not resolve is not a review. Either write the artifact,"
              echo "  or declare the skip on the entry as: review skipped (${p}): <docs-only|test-only|dep-bump|below-threshold>"
              violations=$((violations + 1))
            fi
          elif printf '%s' "$review_lines" | grep -qEi "$skip_re"; then
            : # enumerated skip, bound to this P-number — gate satisfied
          else
            if [ -n "${SELF_MOD_FILES:-}" ]; then
              echo "BLOCK: $p ([${item_type}]) shipped on a branch that modified an executable instruction surface - the review trigger fires regardless of tag or diff size."
              echo "  Self-modifying paths changed on this branch:"
              printf '%s\n' "$SELF_MOD_FILES" | sed 's/^/    /'
              echo "  Requires a real reviewer artifact cited on the Backlog entry as: review: docs/reviews/<file>.md"
              violations=$((violations + 1))
              continue
            fi
            echo "BLOCK: $p ([${item_type}]) shipped but its Backlog entry neither cites a docs/reviews/ artifact nor declares an enumerated review skip."
            echo "  Add a line under the status line: review: docs/reviews/<file>.md"
            echo "  or declare the skip there as: review skipped (${p}): <docs-only|test-only|dep-bump|below-threshold>"
            violations=$((violations + 1))
          fi
          ;;
      esac
    fi
  else
    echo "BLOCK: $p transitioned $before_status -> $after_status (illegal)"
    echo "  Legal outbound from $before_status: $(legal_paths_from "$before_status")"
    violations=$((violations + 1))
  fi
done <<EOF
$AFTER_STATES
EOF

if [ "$violations" -gt 0 ]; then
  echo ""
  echo "$violations illegal state transition(s). Fix Backlog.md before committing." >&2
  exit 1
fi
[ "$warnings" -gt 0 ] && echo "$warnings warning(s) — not blocking."
echo "validate-state-transitions: OK (${warnings} warnings)"
exit 0
