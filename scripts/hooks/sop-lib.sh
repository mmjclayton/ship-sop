#!/usr/bin/env bash
#
# Shared helpers for ship-sop's user-scope push gate, the project-type check
# and receipt validation (scripts/ship-receipt.sh). Sourced, not executed.
#
# Design constraints:
#   - The gate is silent unless a deterministic fact holds.
#   - `set -u` only; no `-e`, no `pipefail`: a git command that exits 128 in
#     an odd directory must not become an error here. The push gate turns any
#     unexpected exit into a refusal itself (fails closed).
#   - Resolve the repo from the hook's `cwd` input field, never from the
#     launch directory. Project-scope hooks only load from the directory
#     Claude Code was launched in; sessions launched from ~ that cd into a
#     project never see them.
#   - One rule per question: the push gate, the receipt validator and /ship
#     all read the functions here, so they cannot disagree.

set -u

# Byte semantics for every grep/sed/awk below. In a UTF-8 locale BSD grep
# aborts the whole file on one invalid byte ("Invalid multibyte sequence"),
# and with stderr discarded that read as "no declaration, no signals": a
# pasted smart quote in CLAUDE.md silently turned a code project into
# non-code and switched off every hook (review finding, CRITICAL). All the
# patterns here are ASCII, so the C locale loses nothing.
export LC_ALL=C

SOP_INPUT=""

sop_have_jq() { command -v jq >/dev/null 2>&1; }

# Read the hook input JSON from stdin once. Empty stdin is tolerated.
sop_read_input() {
    SOP_INPUT=$(cat 2>/dev/null || true)
    [ -n "$SOP_INPUT" ] || SOP_INPUT='{}'
}

# sop_field <jq-expr> — prints the field or empty. Never errors.
sop_field() {
    sop_have_jq || { printf ''; return; }
    printf '%s' "$SOP_INPUT" | jq -r "$1 // empty" 2>/dev/null || printf ''
}

sop_sha256() {
    if command -v shasum >/dev/null 2>&1; then
        shasum -a 256 | awk '{print $1}'
    elif command -v sha256sum >/dev/null 2>&1; then
        sha256sum | awk '{print $1}'
    else
        cksum | awk '{print $1}'
    fi
}

# sop_repo_root <cwd> — git toplevel for cwd, or empty.
sop_repo_root() {
    local cwd="$1"
    [ -d "$cwd" ] || { printf ''; return; }
    git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || printf ''
}

# sop_is_gated_repo <root> — where the push gate applies: a repository with a ship-sop
# configuration. The home directory is refused even when it is a git repo.
sop_is_gated_repo() {
    local root="$1"
    [ -n "$root" ] || return 1
    [ "$root" != "${HOME:-/nonexistent}" ] || return 1
    [ -f "$root/ship-sop.config.json" ]
}

# ── Project type ──────────────────────────────────────────────────────────────
# sop_project_type <root> — prints "code" or "non-code". One rule for every
# consumer: the push gate, /ship and $ship all read this. ship-sop fires for
# coding and for nothing else, so a wrong answer here is either a gate nagging
# a prose repo or unreviewed code going through.
#
# Precedence:
#   1. An explicit declaration in CLAUDE.md — a line `**Project type:** code`
#      or `**Project type:** non-code` (bold optional, a leading list bullet
#      tolerated, value case-insensitive; text inside ``` fences is ignored so
#      an example of the syntax is not read as the declaration). Wins
#      outright: a scripts-and-markdown repo with a real test suite has no
#      manifest and is still code.
#   2. Four heuristics, in order (all case-insensitive, like the declaration):
#      a. CLAUDE.md has a `## Auth`, `## Database` or `## Design System` heading
#      b. CLAUDE.md references claude-md-template-code.md
#      c. the `## Key Commands` section runs a test suite (npm/pnpm/yarn/bun
#         test, pytest, jest, vitest, cargo test, go test, make test) — the
#         word "test" in prose does not count
#      d. the root carries package.json, Cargo.toml, pyproject.toml, go.mod
#         or Gemfile
#   3. Otherwise non-code.
#
# A declaration that contradicts the heuristics is honoured.

# AGENTS.md is canonical when present; existing Claude-only projects are unchanged.
# A bridge AGENTS.md without a type declaration falls back to CLAUDE.md.
sop_instruction_file() {
    if { [ -L "$1/AGENTS.md" ] || [ -e "$1/AGENTS.md" ]; } &&
       { [ ! -f "$1/AGENTS.md" ] || [ ! -r "$1/AGENTS.md" ]; }; then
        printf '%s/AGENTS.md' "$1"; return
    fi
    if { [ -f "$1/AGENTS.md" ] || [ -L "$1/AGENTS.md" ]; } &&
       { [ ! -f "$1/CLAUDE.md" ] || [ -n "$(sop_type_from_file "$1/AGENTS.md")" ]; }; then printf '%s/AGENTS.md' "$1"
    else printf '%s/CLAUDE.md' "$1"; fi
}

# sop_claude_prose <file> — the file with fenced code blocks removed.
sop_claude_prose() { awk '/^[[:space:]]*```/{f=!f; next} !f' "$1" 2>/dev/null; }

# sop_declared_project_type <root> — "code", "non-code", or empty.
sop_type_from_file() {
    [ -f "$1" ] || return 0
    sop_claude_prose "$1" \
        | sed -E 's/^[[:space:]]*[-+*][[:space:]]+//' \
        | grep -Ei '^[*_]*project type' | head -1 | tr 'A-Z' 'a-z' \
        | sed -nE 's/^[*_]*project type[*_]*:?[*_]*[[:space:]]*(non-code|code)([^a-z].*)?$/\1/p'
}

sop_declared_project_type() {
    sop_type_from_file "$(sop_instruction_file "$1")"
}

# sop_code_signals <root> — one line per heuristic that says "code", in the
# documented order; empty when none does.
sop_code_signals() {
    local root="$1" claude m
    claude=$(sop_instruction_file "$root")
    if [ -f "$claude" ]; then
        sop_claude_prose "$claude" | grep -Ei '^## (Auth|Database|Design System)([^A-Za-z]|$)' | head -1 \
            | sed -E 's/^## ([A-Za-z]+( [A-Za-z]+)?).*/\1 heading/'
        grep -qi 'claude-md-template-code\.md' "$claude" 2>/dev/null && echo 'code-template reference'
        awk 'tolower($0) ~ /^## key commands/{f=1; next} /^## /{f=0} f' "$claude" 2>/dev/null \
            | grep -Eqi '(^|[[:space:]`])((npm|pnpm|yarn|bun)[[:space:]]+(run[[:space:]]+)?test|pytest|jest|vitest|cargo[[:space:]]+test|go[[:space:]]+test|make[[:space:]]+test)([^a-z]|$)' \
            && echo 'test command under Key Commands'
    fi
    for m in package.json Cargo.toml pyproject.toml go.mod Gemfile; do
        [ -f "$root/$m" ] && echo "$m"
    done
    return 0
}

sop_project_type() {
    local root="$1" declared
    [ -n "$root" ] && [ -d "$root" ] || { printf 'non-code'; return; }
    # A failed native instruction source must not silently disable code gates.
    if { [ -L "$root/AGENTS.md" ] || [ -e "$root/AGENTS.md" ]; } &&
       { [ ! -f "$root/AGENTS.md" ] || [ ! -r "$root/AGENTS.md" ]; }; then printf 'code'; return; fi
    declared=$(sop_declared_project_type "$root")
    if [ -n "$declared" ]; then printf '%s' "$declared"; return; fi
    if [ -n "$(sop_code_signals "$root")" ]; then printf 'code'; else printf 'non-code'; fi
}

sop_is_code_repo() { [ "$(sop_project_type "$1")" = "code" ]; }

# sop_default_branch <root> — "origin/main" style ref, or empty.
# origin/HEAD when set, else the first of origin/main, master, develop. Empty
# with status 0 only when there are no origin remote-tracking refs at all (a
# first push). Status 1 when git fails, or when origin refs exist but none is a
# recognisable default branch: the review range cannot be known, and callers
# must not read that as "nothing to review".
sop_default_branch() {
    local root="$1" ref='' cand rc=0 refs
    ref=$(git -C "$root" symbolic-ref -q refs/remotes/origin/HEAD 2>/dev/null) || rc=$?
    [ "$rc" -le 1 ] || return 1
    ref=${ref#refs/remotes/}
    if [ -z "$ref" ]; then
        for cand in origin/main origin/master origin/develop; do
            if git -C "$root" rev-parse -q --verify "$cand^{commit}" >/dev/null 2>&1; then
                ref="$cand"
                break
            fi
        done
    fi
    if [ -z "$ref" ]; then
        refs=$(git -C "$root" for-each-ref --format='%(refname)' refs/remotes/origin/ 2>/dev/null) || return 1
        [ -z "$refs" ] || return 1
    fi
    printf '%s' "$ref"
}

# sop_range_base <root> — merge-base of default branch and HEAD when the
# branch has diverged; empty when on the default branch or with no origin refs.
# Status 1 when the range cannot be computed (git failure, unrelated histories,
# an unrecognisable default branch).
sop_range_base() {
    local root="$1" ref base head
    ref=$(sop_default_branch "$root") || return 1
    [ -n "$ref" ] || { printf ''; return 0; }
    head=$(git -C "$root" rev-parse -q --verify 'HEAD^{commit}' 2>/dev/null) || return 1
    base=$(git -C "$root" merge-base "$ref" HEAD 2>/dev/null) || return 1
    [ -n "$base" ] || return 1
    if [ "$base" = "$head" ]; then
        printf ''
    else
        printf '%s' "$base"
    fi
}

# sop_cmd_matches_push <text> — the bare pattern: a `git ... push` or
# `gh pr create` simple command at the start of the text or after a
# separator (; & | ( backtick or whitespace).
sop_cmd_matches_push() {
    # git's global options may take a separate argument (-C dir, -c key=val, --git-dir dir):
    # `git -C repo push` is a push (review finding). gh may carry flags before `pr`.
    printf '%s' "$1" | grep -Eq '(^|[;&|(`/\\]|[[:space:]])(git[[:space:]]+((-[Cc]|--git-dir|--work-tree|--namespace|--exec-path|--config-env|--super-prefix)[[:space:]]+[^[:space:]]+[[:space:]]+|-[^[:space:]]+[[:space:]]+)*push|gh[[:space:]]+(-[^[:space:]]+[[:space:]]+([^-[:space:]][^[:space:]]*[[:space:]]+)?)*pr[[:space:]]+(create|new))([[:space:];&|)`"\\'"'"']|$)'
}

# sop_is_push_command <command> [depth] — true when the command would run a
# push or PR-create. Two things the bare pattern gets wrong, both found in
# review: `bash -c 'git push'` hides the verb behind a quote, and
# `echo "remember to git push"` shows the verb inside prose. So: recurse into
# the quoted body of a shell wrapper (`bash|sh|zsh|dash|ksh -c` and `eval`),
# then strip every remaining quoted string and match only the residue —
# what the shell would actually execute, not what an argument says.
#
# It fails closed where it can: code handed to a shell or interpreter in a
# command that names git and push is refused, even if it would not push. Known limits
# of static matching, not caught: a push inside a script file (sh deploy.sh, source),
# variable indirection (G=git; $G push), aliases and functions, $'\x..' escapes, and
# decoded payloads (base64 -d | sh with no visible verb). The gate stops an agent's
# honest mistake; it is not a sandbox.
sop_is_push_command() {
    local cmd="$1" depth="${2:-0}" rest body whole stripped
    # Backslash-newline continues a line: `git \<newline>push` is one command (review finding).
    cmd=$(printf '%s\n' "$cmd" | awk '{ if (sub(/\\$/, "")) printf "%s ", $0; else print }') || return 0
    # Nesting deeper than any real command is refused, not waved through (review finding).
    [ "$depth" -le 3 ] || return 0

    # Options may come before -c: `bash -e -c`, `bash --login -c`, `bash -o pipefail -c`.
    local re_sh="(bash|sh|zsh|dash|ksh)([[:space:]]+([-+]o[[:space:]]+[A-Za-z]+|[-+][A-Za-z-]+))*[[:space:]]+-[A-Za-z]*c[A-Za-z]*[[:space:]]+('([^']*)'|\"([^\"]*)\")"
    rest="$cmd"
    while [[ "$rest" =~ $re_sh ]]; do
        # Copied first: the recursive call's own matches overwrite BASH_REMATCH, and an
        # unbound read crashed the gate, letting a later push through (2026-10-11).
        whole="${BASH_REMATCH[0]}"; body="${BASH_REMATCH[5]}${BASH_REMATCH[6]}"
        # A wrapper body that mentions a push is treated as one: escaped quotes inside it
        # cannot be parsed reliably, and the gate fails closed (review finding).
        sop_cmd_matches_push "$body" && return 0
        sop_is_push_command "$body" $((depth + 1)) && return 0
        rest="${rest#*"$whole"}"
    done

    local re_eval="eval[[:space:]]+('([^']*)'|\"([^\"]*)\")"
    rest="$cmd"
    while [[ "$rest" =~ $re_eval ]]; do
        whole="${BASH_REMATCH[0]}"; body="${BASH_REMATCH[2]}${BASH_REMATCH[3]}"
        sop_cmd_matches_push "$body" && return 0
        sop_is_push_command "$body" $((depth + 1)) && return 0
        rest="${rest#*"$whole"}"
    done

    # A quoted word is still the word: `git 'push'` and `git p'u'sh` run a push. Quoted
    # strings without spaces are unquoted first; only quoted prose (with spaces) is then
    # stripped (review finding). Backslashes go too: `git pu\sh` runs a push.
    stripped=$(printf '%s\n' "$cmd" | sop_strip_heredocs \
        | sed -E "s/\\\\//g; s/'([^'[:space:]]*)'/\1/g; s/\"([^\"[:space:]]*)\"/\1/g; s/'[^']*'//g; s/\"[^\"]*\"//g")
    sop_cmd_matches_push "$stripped" && return 0

    # Fail closed on what static matching cannot parse: a shell or an
    # interpreter given code on the command line (-c/-e, any options before it, such as
    # bash -O extglob -c or python3 -c) or on stdin (bash <<EOF, bash <<< '...'), anywhere
    # in a command that names git and push. Code piped into one (echo .. | bash) counts.
    # Document heredocs (cat > f <<EOF) are dropped first, so a doc that mentions both is
    # not refused. A grep or tr error refuses rather than reading as "no match".
    local text unquoted rc=0
    text=$(printf '%s\n' "$cmd" | sop_strip_heredocs) || return 0
    unquoted=$(printf '%s\n' "$text" | sed -E 's/\\[nt]/ /g' | tr -d "'\"\\\\") || return 0
    printf '%s\n' "$text" | grep -Eq '(^|[^[:alnum:]_.-])(bash|sh|zsh|dash|ksh|python[0-9.]*|node|perl|ruby)(([[:space:]]+[^;&|[:space:]]+)*[[:space:]]+-[A-Za-z]*[ce]|[^;&|]*<<)|[|][[:space:]]*(bash|sh|zsh|dash|ksh|python[0-9.]*|node|perl|ruby)([[:space:]]|$)' || rc=$?
    [ "$rc" -le 1 ] || return 0
    [ "$rc" = 0 ] || return 1
    rc=0
    printf '%s\n' "$unquoted" | grep -Eq '(^|[^[:alnum:]_-])git([^[:alnum:]_-].*)?[^[:alnum:]_-]push([^[:alnum:]_-]|$)|(^|[^[:alnum:]_-])gh[^[:alnum:]_-].*pr[^[:alnum:]_-]+(create|new)' || rc=$?
    [ "$rc" -le 1 ] || return 0
    return "$rc"
}

# sop_strip_heredocs — drops the body of every here-document on stdin. A
# command that writes a file whose text mentions a push verb is not a push
# (the gate refused a scratchpad write of a command doc, 2026-09-05).
# A `<<` inside quotes or arithmetic (`echo '<<x'`, `$((1<<x))`) is not a here-document,
# and a body with no terminator line is not dropped: either would hide a later push line
# (review finding). Tags are unquoted first, then the line is matched with quotes removed.
# A heredoc fed to a shell or interpreter (bash <<EOF) is code: its body is kept.
# With <<- the terminator may be indented by tabs.
sop_strip_heredocs() {
    sed -E "s/<<(-?)[[:space:]]*['\"]([A-Za-z_][A-Za-z0-9_]*)['\"]/<<\1\2/g" | awk '
        skip { buf = buf $0 "\n"; e = $0; if (dash) sub(/^\t+/, "", e); if (e == tag) { skip = 0; buf = "" } ; next }
        {
            l = $0; gsub(/'"'"'[^'"'"']*'"'"'/, "", l); gsub(/"[^"]*"/, "", l); gsub(/\$\(\([^)]*\)\)/, "", l)
            if (match(l, /<<-?[[:space:]]*[A-Za-z_][A-Za-z0-9_]*/)) {
                t = substr(l, RSTART, RLENGTH); pre = substr(l, 1, RSTART - 1)
                post = substr(l, RSTART + RLENGTH)
                if (pre ~ /(^|[;&|[:space:]])(bash|sh|zsh|dash|ksh|eval|python[0-9.]*|node|perl|ruby)([[:space:]]|$)/) { print; next }
                if (post ~ /[|]([^;&]*[|])?[[:space:]]*(bash|sh|zsh|dash|ksh|python[0-9.]*|node|perl|ruby)([[:space:]]|$)/) { print; next }
                dash = (t ~ /^<<-/); sub(/^<<-?[[:space:]]*/, "", t)
                tag = t; skip = 1; buf = ""; print; next
            }
            print
        }
        END { if (skip) printf "%s", buf }'
}

# sop_code_lines <root> <from> <to> <skip-docs> — added+deleted lines in the
# range, excluding documentation extensions when skip-docs is "true".
# Binary files report "-" and count 0. Fields are tab-separated: the path
# field can carry spaces, and a rename arrives as `old => new` or
# `dir/{old => new}/rest`. A rename is excluded only when both names are
# documentation — a doc renamed into a code file with logic added is code
# (review finding, CRITICAL: whitespace splitting read the old name).
sop_instruction_pattern() {
    printf '%s' '^([.]agents/|[.]claude/|[.]codex/|docs/sop/|docs/guides/sop-)|(^|/)(AGENTS|CLAUDE|SKILL)[.]md$'
}

sop_instructions_changed() {
    git -C "$1" diff --no-renames --name-only "$2..$3" | grep -Eq "$(sop_instruction_pattern)"
}

sop_code_lines() {
    git -C "$1" diff --numstat "$2..$3" 2>/dev/null | awk -F'\t' -v skip="$4" -v instructions="$(sop_instruction_pattern)" '
        function isdoc(p) {
            if (p ~ /^docs\/reviews\/.*-ship-auto\.json$/) return 1
            if (p ~ instructions) return 0
            return p ~ /\.(md|markdown|txt|rst)$/
        }
        {
            path = $3; old = path; new = path
            if (path ~ / => /) {
                new = path; gsub(/\{[^}]* => /, "", new); gsub(/\}/, "", new); sub(/^.* => /, "", new)
                old = path; gsub(/ => [^}]*\}/, "", old); gsub(/\{/, "", old); sub(/ => .*$/, "", old)
            }
            if (skip == "true" && isdoc(old) && isdoc(new)) next
            a = ($1 == "-") ? 0 : $1
            d = ($2 == "-") ? 0 : $2
            t += a + d
        }
        END { print t + 0 }'
}

# Shared receipt contract. Markdown is a view, never evidence consumed by a gate.
sop_effective_config() {
    if [ -f "$1/ship-sop.config.json" ]; then printf '%s/ship-sop.config.json' "$1"; return; fi
    local config_home
    if [ "${SHIP_SOP_RUNTIME:-claude}" = codex ]; then
        config_home=${SHIP_SOP_CONFIG_HOME:-${CODEX_HOME:-${SHIP_SOP_USER_HOME:-$HOME}/.codex}}
    else config_home=${SHIP_SOP_CONFIG_HOME:-${SHIP_SOP_USER_HOME:-$HOME}/.claude}; fi
    printf '%s/ship-sop.config.json' "$config_home"
}

sop_policy_valid() {
    jq -se 'length == 1' "$1" >/dev/null 2>&1 || return 1
    jq -e '
      def prop($key; $default): if has($key) then .[$key] else $default end;
      type == "object" and (.trigger | type == "object") and
      (.trigger.mode | IN("auto", "manual", "off")) and
      ((.trigger | prop("throttle"; {})) | type == "object") and
      ((.trigger | prop("throttle"; {}) | prop("min_diff_lines"; 10)) | type == "number" and . >= 0 and floor == .) and
      ((.trigger | prop("throttle"; {}) | prop("skip_branch_patterns"; [])) | type == "array" and all(.[]; type == "string" and (test("[\\r\\n]") | not))) and
      (.agents | type == "object" and all(to_entries[];
        (.key | test("^[a-z0-9][a-z0-9-]*$")) and
        (.value.enabled | type == "boolean") and
        (.value | prop("block_on"; "CRITICAL") | IN("CRITICAL", "HIGH", "MEDIUM", "never")) and
        ((.value | prop("paths"; [])) | type == "array" and all(.[]; type == "string" and length > 0 and (test("[\\r\\n]") | not)))))
    ' "$1" >/dev/null 2>&1 || return 1
    local pat result
    while IFS= read -r pat; do
        printf '' | grep -E -- "$pat" >/dev/null 2>&1; result=$?
        [ "$result" -le 1 ] || return 1
    done < <(jq -r '.trigger.throttle.skip_branch_patterns[]?' "$1")
    # Reviewer path scopes are matched by jq (the demand and the receipt
    # validator share one implementation), so each must compile there.
    while IFS= read -r pat; do
        jq -en --arg p "$pat" '"" | test($p) | true' >/dev/null 2>&1 || return 1
    done < <(jq -r '.agents[] | .paths[]?' "$1")
    return 0
}

sop_policy_digest() {
    { printf 'ship-receipt-v1\n'; jq -Sc . "$1"; } | sop_sha256
}

# sop_changed_files_json <root> <base> <head> — JSON array of every path the
# range touches (both sides of a rename), for reviewer scope decisions.
sop_changed_files_json() {
    git -C "$1" diff --no-renames --name-only "$2..$3" 2>/dev/null | jq -R . | jq -sc .
}

# sop_agents_in_scope <config> <files-json> — JSON array of {key, block_on} for
# every enabled reviewer whose scope the range enters. A reviewer without
# `paths` is in scope for every range; one with `paths` only when a changed
# path matches one of its patterns; an empty `paths` never. The gate demand,
# the receipt validator and /ship all read this one rule (ship-sop P33).
sop_agents_in_scope() {
    jq -c --argjson files "$2" '
      [.agents | to_entries[] | select(.value.enabled == true) | . as $a |
        select(($a.value | has("paths") | not) or
               any($files[]; . as $f | any($a.value.paths[]; . as $p | $f | test($p)))) |
        {key: $a.key, block_on: ($a.value.block_on // "CRITICAL")}]' "$1" 2>/dev/null || printf 'unavailable'
}

# Validate completion and derive threshold decisions, independently of prose verdicts.
# schema_version 1 receipts stay valid; version 2 (ship-sop P34) adds per-reviewer
# run counts - launches (fresh agents, at least one), rechecks (re-reviews with
# context intact), block_rounds (rounds with a finding at or above the reviewer's
# block_on, never more than the runs) - and an optional usage object the runtime may supply; null when it cannot.
sop_receipt_valid() {
    local root="$1" receipt="$2" cfg sha base required tree scope
    cfg=$(sop_effective_config "$root")
    jq -se 'length == 1' "$receipt" >/dev/null 2>&1 || return 1
    sop_policy_valid "$cfg" || return 1
    sha=$(jq -r '.head // ""' "$receipt"); base=$(jq -r '.base // ""' "$receipt")
    [ "$(printf '%s\n%s\n' "$sha" "$base" | grep -Ec '^[0-9a-f]{40}$')" = 2 ] || return 1
    # Only reviewers in scope for the receipt's own range are required (P33);
    # any extra reviewer present is still held to its threshold below.
    scope=$(sop_agents_in_scope "$cfg" "$(sop_changed_files_json "$root" "$base" "$sha")")
    jq -e --slurpfile cfg "$cfg" --argjson scope "$scope" --arg policy "$(sop_policy_digest "$cfg")" '
      def rank: {CRITICAL:4,HIGH:3,MEDIUM:2,LOW:1,INFO:0,never:99}[.];
      def text: type == "string" and length > 0;
      . as $r |
      (.schema_version | IN(1, 2)) and .policy_sha256 == $policy and
      (.head | test("^[0-9a-f]{40}$")) and (.base | test("^[0-9a-f]{40}$")) and
      (.tree | test("^[0-9a-f]{40}$")) and
      (.tests.status | IN("PASS", "NOT_AVAILABLE")) and (.tests.evidence | text) and
      (.reviewers | type == "array" and length > 0) and
      ([.reviewers[].name] | length == (unique | length)) and
      all(.reviewers[]; (.name | text) and .verdict == "PASS" and
        (.version | text) and (.model | text) and
        (if $r.schema_version == 2 then
           (.launches | type == "number" and . >= 1 and floor == .) and
           (.rechecks | type == "number" and . >= 0 and floor == .) and
           (.block_rounds | type == "number" and . >= 0 and floor == .) and
           (.block_rounds <= .launches + .rechecks) and
           ((.usage // null) | type == "object" or . == null)
         else true end) and
        (.findings | type == "array" and all(.[];
          (.severity | IN("CRITICAL","HIGH","MEDIUM","LOW","INFO")) and
          (.file | text) and (.line | type == "number" and . > 0 and floor == .) and (.message | text)))) and
      all($scope[]; . as $a |
        ([$r.reviewers[] | select(.name == $a.key)] | length == 1) and
        all($r.reviewers[] | select(.name == $a.key) | .findings[];
          (.severity | rank) < ($a.block_on | rank))) and
      all(.reviewers[]; . as $review |
        ($cfg[0].agents[$review.name].block_on // "CRITICAL") as $threshold |
        all(.findings[]; (.severity | rank) < ($threshold | rank)))
    ' "$receipt" >/dev/null 2>&1 || return 1
    tree=$(git -C "$root" rev-parse "$sha^{tree}" 2>/dev/null) || return 1
    [ "$tree" = "$(jq -r .tree "$receipt")" ] || return 1
    git -C "$root" merge-base --is-ancestor "$base" "$sha" 2>/dev/null || return 1
    required=$(sop_range_base "$root") || return 1
    [ -n "$required" ] || required=$(git -C "$root" rev-parse HEAD)
    git -C "$root" merge-base --is-ancestor "$base" "$required" 2>/dev/null
}

sop_shipsop_covered() {
    local root="$1" head="$2" receipt sha
    for receipt in "$root"/docs/reviews/*-ship-auto.json; do
        [ -f "$receipt" ] || continue
        sop_receipt_valid "$root" "$receipt" || continue
        sha=$(jq -r .head "$receipt")
        git -C "$root" merge-base --is-ancestor "$sha" "$head" 2>/dev/null || continue
        sop_instructions_changed "$root" "$sha" "$head" && continue
        [ "$(sop_code_lines "$root" "$sha" "$head" true)" = "0" ] && return 0
    done
    return 1
}

# sop_shipsop_gate <root> — prints the gate demand when ship-sop auto-mode
# applies to this branch and no gate report covers HEAD; empty otherwise.
#
# The push gate prints this demand on stderr with exit 2, which Claude Code
# and Codex feed back to the model.
#
# Code projects only, and code lines only. ship-sop fires for coding and for
# nothing else: a prose repository that
# carries a config gets no automatic gate, and a documentation-only branch in
# a code repository gets none either. The config's `skip_docs_only` is read
# by nothing here any more — documentation extensions are always excluded
# from the count; the field survives for /ship's manual mode and old configs.
sop_shipsop_gate() {
    local root="$1" cfg mode branch pat base head lines min report agents scope
    cfg="$root/ship-sop.config.json"
    [ -f "$cfg" ] || { printf ''; return; }
    sop_have_jq || { printf ''; return; }

    sop_is_code_repo "$root" || { printf ''; return; }
    if ! sop_policy_valid "$cfg"; then
        printf 'ship-sop configuration invalid: repair ship-sop.config.json before publication.\n'
        return
    fi
    mode=$(jq -r '.trigger.mode // "manual"' "$cfg" 2>/dev/null)
    [ "$mode" = "auto" ] || { printf ''; return; }
    sop_is_code_repo "$root" || { printf ''; return; }

    branch=$(git -C "$root" branch --show-current 2>/dev/null)
    while IFS= read -r pat; do
        if printf '%s' "$branch" | grep -Eq -- "$pat"; then printf ''; return; fi
    done < <(jq -r '.trigger.throttle.skip_branch_patterns[]? // empty' "$cfg")

    if ! base=$(sop_range_base "$root"); then
        printf 'ship-sop gate could not be evaluated: the review range against the default branch cannot be computed (no recognisable origin default branch, unrelated history, or a git error). Run `git remote set-head origin -a` or fetch, then retry.\n'
        return
    fi
    [ -n "$base" ] || { printf ''; return; }
    head=$(git -C "$root" rev-parse HEAD 2>/dev/null)
    # An unreadable range is not an empty one: every count below reads this diff (review finding).
    local diff_rc=0
    git -C "$root" diff --quiet "$base..$head" -- >/dev/null 2>&1 || diff_rc=$?
    if [ -z "$head" ] || [ "$diff_rc" -gt 1 ]; then
        printf 'ship-sop gate could not be evaluated: git diff %s..%s failed; repair the repository before publication.\n' "${base:0:7}" "${head:0:7}"
        return
    fi

    min=$(jq -r '.trigger.throttle.min_diff_lines // 10' "$cfg" 2>/dev/null)

    # Documentation extensions are excluded from the count, always, so a
    # docs-heavy branch never summons reviewers for prose.
    lines=$(sop_code_lines "$root" "$base" "$head" true)
    if ! sop_instructions_changed "$root" "$base" "$head"; then
        [ "${lines:-0}" -ge "${min:-10}" ] 2>/dev/null || { printf ''; return; }
    fi

    # Coverage is a fact, not a stamp: a report names a commit that is an
    # ancestor of HEAD with no code change since. "No code change" uses the
    # same docs filter as the trigger, so committing the report itself — or
    # any later docs-only commit — does not un-cover the branch.
    # Reviewer scope by path (ship-sop P33): only enabled reviewers whose
    # `paths` the range enters are demanded, and when none is there is no
    # gate to run — the same rule the receipt validator applies.
    scope=$(sop_agents_in_scope "$cfg" "$(sop_changed_files_json "$root" "$base" "$head")")
    if [ "$scope" = unavailable ]; then
        printf 'ship-sop gate could not be evaluated: reviewer scope unreadable from ship-sop.config.json.\n'
        return
    fi
    [ "$scope" != "[]" ] || { printf ''; return; }

    if sop_shipsop_covered "$root" "$head"; then
        printf ''
        return
    fi

    agents=$(jq -r '.[] | "  - @\(.key) (block_on: \(.block_on))"' <<< "$scope" 2>/dev/null)
    report="docs/reviews/$(date +%Y%m%d-%H%M%S)-ship-auto.md"

    printf 'ship-sop gate (auto-mode per ship-sop.config.json): %s code lines on %s vs %s (%s..%s) have no gate report.\n' \
        "$lines" "${branch:-HEAD}" "$(sop_default_branch "$root")" "$(printf '%s' "$base" | cut -c1-7)" "$(printf '%s' "$head" | cut -c1-7)"
    printf '  Run these agents against that range, collect every result (they run in the background), then write %s and a validated companion JSON receipt for %s (a Covers: line alone is not coverage):\n' "$report" "$head"
    printf '%s\n' "$agents"
    if [ "${SHIP_SOP_RUNTIME:-claude}" = codex ]; then
        printf '  Use the ship skill: run reviewers in separate checkouts with a read-only sandbox, each with --block-on set to its block_on above; collect every result, then write the report in the parent. Never substitute a worktree path in a prompt for enforced isolation.\n'
        return
    fi
    printf '  Rules: launch each agent with isolation: "worktree", read-only; wait for every result; write the report after any fix commit so it covers HEAD; give each reviewer its block_on above and the severity rule from /ship; findings at or above a reviewer'"'"'s block_on at the top of your next reply with file:line, the rest stay in the report as notes; file nothing to Backlog.md.\n'
}
