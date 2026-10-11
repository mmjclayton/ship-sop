#!/usr/bin/env bash
#
# Fixtures for scripts/install-hooks.sh: registration, idempotence, uninstall,
# retired-hook cleanup, edited-copy preservation and the move from the older
# .../scripts/hooks/agent-sop/ location to .../scripts/hooks/ship-sop/.
#
# Run from the repo root: bash tests/install-hooks.sh

set -u

SOURCE="$(cd "$(dirname "$0")/.." && pwd -P)"
INSTALLER="$SOURCE/scripts/install-hooks.sh"
LEGACY_LIST="$SOURCE/scripts/legacy-agent-sop-hooks.txt"

TMP=$(mktemp -d)
TMP=$(cd "$TMP" && pwd -P)
SUITE_DONE=0
suite_trap() {
    local rc=$?
    [ "$SUITE_DONE" = 1 ] || { echo "FAIL: suite stopped before its last check" >&2; rc=1; }
    rm -rf "$TMP"
    exit "$rc"
}
trap suite_trap EXIT

export HOME="$TMP/home"
mkdir -p "$HOME"
unset CODEX_HOME SHIP_SOP_USER_HOME

pass=0
fail=0
failed=""
ok()  { echo "PASS: $1"; pass=$((pass + 1)); }
bad() { echo "FAIL: $1 - $2"; fail=$((fail + 1)); failed="$failed $1"; }

# count <settings> <event> <regex>: hook commands under the event matching the regex.
count() { jq --arg re "$3" "[.hooks.$2[]?.hooks[]?.command | select(test(\$re))] | length" "$1"; }

# ── Registration ──────────────────────────────────────────────────────────────

SETTINGS="$TMP/settings.json"
cat > "$SETTINGS" <<'JSON'
{ "model": "x",
  "hooks": {
    "Stop": [ { "matcher": "*", "hooks": [ { "type": "command", "command": "node existing-stop.js" } ] } ],
    "PreToolUse": [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "node existing-pre.js" } ] } ]
  } }
JSON
DEST="$TMP/dest"
bash "$INSTALLER" --settings "$SETTINGS" --dest "$DEST" >/dev/null 2>"$TMP/inst-err"; INST1=$?
bash "$INSTALLER" --settings "$SETTINGS" --dest "$DEST" >/dev/null 2>>"$TMP/inst-err"; INST2=$?
if [ "$INST1" = 0 ] && [ "$INST2" = 0 ] \
   && [ "$(count "$SETTINGS" PreToolUse 'sop-push-gate')" = 1 ] \
   && [ "$(jq -r '.hooks.PreToolUse[] | select(.hooks[].command | test("sop-push-gate")) | .matcher' "$SETTINGS")" = Bash ] \
   && [ "$(count "$SETTINGS" Stop 'existing-stop')" = 1 ] \
   && [ "$(count "$SETTINGS" PreToolUse 'existing-pre')" = 1 ] \
   && [ "$(jq -r .model "$SETTINGS")" = x ] \
   && [ -x "$DEST/sop-push-gate.sh" ] && [ -x "$DEST/sop-lib.sh" ] \
   && [ -x "$DEST/sop-project-type.sh" ] && [ -x "$DEST/sop-codex-hook.sh" ] \
   && ls "$SETTINGS".bak-* >/dev/null 2>&1; then
    ok "installer-idempotent-and-preserving"
else
    bad "installer-idempotent-and-preserving" "exits $INST1/$INST2; pre=$(count "$SETTINGS" PreToolUse 'sop-push-gate'); err='$(cat "$TMP/inst-err")'"
fi

# Defaults: Claude uses ~/.claude/settings.json and ~/.claude/scripts/hooks/ship-sop/.
DEFHOME="$TMP/defhome"
SHIP_SOP_USER_HOME="$DEFHOME" bash "$INSTALLER" >/dev/null 2>&1
if [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$DEFHOME/.claude/settings.json")" = "bash \"$DEFHOME/.claude/scripts/hooks/ship-sop/sop-push-gate.sh\"" ] \
   && [ -x "$DEFHOME/.claude/scripts/hooks/ship-sop/sop-push-gate.sh" ] && [ ! -e "$DEFHOME/.claude/scripts/hooks/agent-sop" ]; then
    ok "installer-default-claude-path"
else bad "installer-default-claude-path" "$(cat "$DEFHOME/.claude/settings.json" 2>/dev/null)"; fi
# Codex: $CODEX_HOME/hooks.json through the dispatcher, and nothing under ~/.claude.
CODEXHOME="$TMP/codexhome"
SHIP_SOP_USER_HOME="$CODEXHOME" bash "$INSTALLER" --runtime codex >/dev/null 2>&1
if [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$CODEXHOME/.codex/hooks.json")" = "bash \"$CODEXHOME/.codex/scripts/hooks/ship-sop/sop-codex-hook.sh\" PreToolUse" ] \
   && jq -e '.hooks | keys == ["PreToolUse"]' "$CODEXHOME/.codex/hooks.json" >/dev/null && [ ! -e "$CODEXHOME/.claude" ]; then
    ok "installer-default-codex-path"
else bad "installer-default-codex-path" "$(cat "$CODEXHOME/.codex/hooks.json" 2>/dev/null)"; fi

# --no-register installs the scripts and leaves the settings alone.
NOREG="$TMP/noreg"; printf '{ "model": "q" }\n' > "$TMP/noreg.json"; cp "$TMP/noreg.json" "$TMP/noreg.orig"
bash "$INSTALLER" --settings "$TMP/noreg.json" --dest "$NOREG" --no-register >/dev/null 2>&1; NR=$?
if [ "$NR" = 0 ] && [ -x "$NOREG/sop-lib.sh" ] && cmp -s "$TMP/noreg.json" "$TMP/noreg.orig"; then ok "installer-no-register-installs-scripts-only"; else bad "installer-no-register-installs-scripts-only" "exit $NR $(cat "$TMP/noreg.json")"; fi

# Retired hook registrations under our own dest go, with no other hook touched.
RETSET="$TMP/settings-retired.json"; RETDEST="$TMP/retdest"; mkdir -p "$RETDEST"
jq -n --arg d "bash \"$RETDEST/" '{hooks:{SessionStart:[{matcher:"*",hooks:[{type:"command",command:($d+"sop-session-context.sh\"")}]}],
  Stop:[{matcher:"*",hooks:[{type:"command",command:($d+"sop-stop-drift.sh\"")},{type:"command",command:"node mine.js"}]}],
  PostToolUse:[{matcher:"Write",hooks:[{type:"command",command:($d+"sop-memory-index.sh\"")}]}]}}' > "$RETSET"
bash "$INSTALLER" --settings "$RETSET" --dest "$RETDEST" >/dev/null 2>&1
if [ "$(jq -c '.hooks | keys' "$RETSET")" = '["PreToolUse","Stop"]' ] && [ "$(jq -r '[.hooks.Stop[].hooks[].command] | join(",")' "$RETSET")" = 'node mine.js' ] \
   && [ -x "$RETDEST/sop-push-gate.sh" ]; then ok "installer-removes-retired-registrations"; else bad "installer-removes-retired-registrations" "$(jq -c .hooks "$RETSET")"; fi

# A symlinked settings file keeps its link; the target receives the write.
REAL="$TMP/dotfiles/settings.json"; LINK="$TMP/home2/settings.json"
mkdir -p "$TMP/dotfiles" "$TMP/home2" && echo '{ "model": "y" }' > "$REAL" && ln -s ../dotfiles/settings.json "$LINK"
bash "$INSTALLER" --settings "$LINK" --dest "$TMP/dest2" >/dev/null 2>&1
if [ -L "$LINK" ] && [ "$(count "$REAL" PreToolUse 'sop-push-gate')" = 1 ] && [ "$(jq -r .model "$REAL")" = y ]; then
    ok "installer-preserves-symlinked-settings"
else
    bad "installer-preserves-symlinked-settings" "link=$([ -L "$LINK" ] && echo yes || echo no)"
fi

# --dry-run writes nothing: no settings file, no settings directory, no scripts.
DRYSET="$TMP/dry-home/settings.json"; DRYDEST="$TMP/dry-dest"
bash "$INSTALLER" --settings "$DRYSET" --dest "$DRYDEST" --dry-run > "$TMP/dry-out" 2>&1; DRY=$?
if [ "$DRY" = 0 ] && [ ! -e "$TMP/dry-home" ] && [ ! -e "$DRYDEST" ] && [ "$(count "$TMP/dry-out" PreToolUse 'sop-push-gate')" = 1 ]; then
    ok "installer-dry-run-writes-nothing"
else
    bad "installer-dry-run-writes-nothing" "exit=$DRY out='$(head -3 "$TMP/dry-out")'"
fi
DRYEX="$TMP/dry-existing.json"; printf '{ "model": "z" }\n' > "$DRYEX"; cp "$DRYEX" "$TMP/dry-existing.orig"
bash "$INSTALLER" --settings "$DRYEX" --dest "$TMP/dry-dest2" --dry-run >/dev/null 2>&1
if cmp -s "$DRYEX" "$TMP/dry-existing.orig" && ! ls "$DRYEX".bak-* >/dev/null 2>&1 && [ ! -e "$TMP/dry-dest2" ]; then ok "installer-dry-run-keeps-existing-settings"; else bad "installer-dry-run-keeps-existing-settings" "$(cat "$DRYEX")"; fi

# A settings path that is a directory is refused; an empty file is read as {}.
mkdir -p "$TMP/settings-dir.json"
if bash "$INSTALLER" --settings "$TMP/settings-dir.json" --dest "$TMP/dest-dir" >/dev/null 2>"$TMP/dir-err"; then
    bad "installer-refuses-directory-settings" "exit 0"
elif grep -q 'not a regular file' "$TMP/dir-err" && [ -z "$(ls -A "$TMP/settings-dir.json")" ]; then ok "installer-refuses-directory-settings"
else bad "installer-refuses-directory-settings" "$(cat "$TMP/dir-err")"; fi
: > "$TMP/settings-empty.json"
bash "$INSTALLER" --settings "$TMP/settings-empty.json" --dest "$TMP/dest-empty" >/dev/null 2>&1; EMPTY=$?
if [ "$EMPTY" = 0 ] && [ "$(count "$TMP/settings-empty.json" PreToolUse 'sop-push-gate')" = 1 ]; then ok "installer-empty-settings-registers"; else bad "installer-empty-settings-registers" "exit=$EMPTY"; fi
printf '{not json\n' > "$TMP/settings-bad.json"; cp "$TMP/settings-bad.json" "$TMP/settings-bad.orig"
if bash "$INSTALLER" --settings "$TMP/settings-bad.json" --dest "$TMP/dest-bad" >/dev/null 2>"$TMP/bad-err"; then bad "installer-refuses-invalid-settings" "exit 0"
elif grep -q 'could not parse' "$TMP/bad-err" && cmp -s "$TMP/settings-bad.json" "$TMP/settings-bad.orig"; then ok "installer-refuses-invalid-settings"
else bad "installer-refuses-invalid-settings" "$(cat "$TMP/bad-err")"; fi

# ── Edited copies ─────────────────────────────────────────────────────────────
# An unedited install is updated in place; a locally edited script is kept and named.
EDIT="$TMP/edit"; EDITSET="$TMP/edit.json"
bash "$INSTALLER" --settings "$EDITSET" --dest "$EDIT" >/dev/null 2>&1
printf '\n# Custom policy\n' >> "$EDIT/sop-lib.sh"; cp "$EDIT/sop-lib.sh" "$TMP/edited-lib"
bash "$INSTALLER" --settings "$EDITSET" --dest "$EDIT" > "$TMP/edit-out" 2>&1
if cmp -s "$TMP/edited-lib" "$EDIT/sop-lib.sh" && grep -q "keep $EDIT/sop-lib.sh (edited locally" "$TMP/edit-out"; then ok "installer-keeps-edited-script"; else bad "installer-keeps-edited-script" "$(cat "$TMP/edit-out")"; fi
# A copy written by an earlier install (recorded in the manifest) is updated.
printf '# older shipped version\n' > "$EDIT/sop-project-type.sh"
OLDBLOB=$(git hash-object --no-filters "$EDIT/sop-project-type.sh")
awk -v b="$OLDBLOB" '$2 == "sop-project-type.sh" { $1 = b } { print }' "$EDIT/.installed" > "$TMP/manifest" && mv "$TMP/manifest" "$EDIT/.installed"
bash "$INSTALLER" --settings "$EDITSET" --dest "$EDIT" >/dev/null 2>&1
if cmp -s "$SOURCE/scripts/hooks/sop-project-type.sh" "$EDIT/sop-project-type.sh"; then ok "installer-updates-unedited-earlier-version"; else bad "installer-updates-unedited-earlier-version" "not updated"; fi
# Uninstall keeps the edited copy and removes the rest.
bash "$INSTALLER" --settings "$EDITSET" --dest "$EDIT" --uninstall > "$TMP/edit-un" 2>&1
if cmp -s "$TMP/edited-lib" "$EDIT/sop-lib.sh" && [ ! -e "$EDIT/sop-push-gate.sh" ] && [ ! -e "$EDIT/.installed" ] && grep -q "keep $EDIT/sop-lib.sh" "$TMP/edit-un" \
   && [ "$(count "$EDITSET" PreToolUse 'sop-push-gate')" = 0 ]; then ok "installer-uninstall-keeps-edited-script"; else bad "installer-uninstall-keeps-edited-script" "$(cat "$TMP/edit-un")"; fi
# Codex: reinstall and removal preserve a customised script too.
CXE="$TMP/codex-edit"
SHIP_SOP_USER_HOME="$CXE" bash "$INSTALLER" --runtime codex >/dev/null 2>&1
printf '\n# Custom policy\n' >> "$CXE/.codex/scripts/hooks/ship-sop/sop-lib.sh"; cp "$CXE/.codex/scripts/hooks/ship-sop/sop-lib.sh" "$TMP/cx-before"
SHIP_SOP_USER_HOME="$CXE" bash "$INSTALLER" --runtime codex >/dev/null 2>&1
CX1=$(cmp -s "$TMP/cx-before" "$CXE/.codex/scripts/hooks/ship-sop/sop-lib.sh" && echo same)
SHIP_SOP_USER_HOME="$CXE" bash "$INSTALLER" --runtime codex --uninstall >/dev/null 2>&1
if [ "$CX1" = same ] && cmp -s "$TMP/cx-before" "$CXE/.codex/scripts/hooks/ship-sop/sop-lib.sh" && [ "$(count "$CXE/.codex/hooks.json" PreToolUse 'sop-codex-hook')" = 0 ]; then
    ok "installer-codex-preserves-customised-script"
else bad "installer-codex-preserves-customised-script" "cx1=$CX1"; fi

# ── Uninstall ─────────────────────────────────────────────────────────────────
# Only our own registration goes: a user hook that shares a file name survives.
jq '.hooks.PreToolUse += [ { "matcher": "Bash", "hooks": [ { "type": "command", "command": "node /other-tool/sop-push-gate.sh" } ] } ]' "$SETTINGS" > "$SETTINGS.tmp" && mv "$SETTINGS.tmp" "$SETTINGS"
bash "$INSTALLER" --settings "$SETTINGS" --dest "$DEST" --uninstall >/dev/null 2>&1; UN=$?
if [ "$UN" = 0 ] && [ "$(count "$SETTINGS" PreToolUse "$DEST/sop-push-gate")" = 0 ] && [ "$(count "$SETTINGS" PreToolUse 'other-tool/sop-push-gate')" = 1 ] \
   && [ "$(count "$SETTINGS" Stop 'existing-stop')" = 1 ] && [ "$(count "$SETTINGS" PreToolUse 'existing-pre')" = 1 ] && [ ! -e "$DEST" ]; then
    ok "installer-uninstall-removes-only-ours"
else
    bad "installer-uninstall-removes-only-ours" "exit $UN $(jq -c .hooks "$SETTINGS")"
fi
# Never delete a file that is its own source (a --dest pointing at the checkout).
cp -R "$SOURCE/scripts" "$TMP/selfcopy"
bash "$TMP/selfcopy/install-hooks.sh" --settings "$TMP/self.json" --dest "$TMP/selfcopy/hooks" >/dev/null 2>&1
bash "$TMP/selfcopy/install-hooks.sh" --settings "$TMP/self.json" --dest "$TMP/selfcopy/hooks" --uninstall >/dev/null 2>&1
if [ -f "$TMP/selfcopy/hooks/sop-push-gate.sh" ] && [ -f "$TMP/selfcopy/hooks/sop-lib.sh" ]; then ok "installer-never-removes-its-own-source"; else bad "installer-never-removes-its-own-source" "$(ls "$TMP/selfcopy/hooks")"; fi

# ── Migration from the older agent-sop location ───────────────────────────────
# legacy_install <home> <runtime-dir> <settings-file>: a pristine older install,
# using the oldest listed version of each file, registered the way it registered.
legacy_install() {
    local dir="$1/$2/scripts/hooks/agent-sop" name b
    mkdir -p "$dir"
    for name in sop-lib.sh sop-push-gate.sh sop-project-type.sh sop-codex-hook.sh sop-stop-drift.sh sop-session-context.sh resolve-resume-path.sh; do
        b=$(awk -v n="$name" '$2 == n { print $1; exit }' "$LEGACY_LIST")
        [ -n "$b" ] || return 1
        printf 'legacy %s\n' "$name" > "$dir/$name"
        # Rewrite the copy until its blob matches: content is irrelevant, only the
        # recorded blob is, so swap the list entry for this fixture's own blob.
        sed -i.bak "s/^$b $name\$/$(git hash-object --no-filters "$dir/$name") $name/" "$TMP/legacy-list" && rm -f "$TMP/legacy-list.bak"
    done
}
# The real list must name real blobs; a fixture copy of the installer reads a
# fixture list in which each legacy fixture file is a "shipped" version.
if grep -v '^#' "$LEGACY_LIST" | grep -qvE '^[0-9a-f]{40} [a-z-]+\.sh$'; then bad "legacy-list-well-formed" "malformed line"; else ok "legacy-list-well-formed"; fi
for name in sop-lib.sh sop-push-gate.sh sop-project-type.sh sop-codex-hook.sh sop-stop-drift.sh sop-session-context.sh sop-memory-index.sh sop-worktree-claim.sh sop-doctor.sh resolve-resume-path.sh; do
    grep -q " $name\$" "$LEGACY_LIST" || bad "legacy-list-covers-$name" "no entry"
done
FIXSRC="$TMP/fixture-src"; cp -R "$SOURCE/scripts" "$FIXSRC"
cp "$LEGACY_LIST" "$TMP/legacy-list"

MIG="$TMP/mig"
legacy_install "$MIG" .claude || bad "migration-fixture" "legacy list lacks a file"
cp "$TMP/legacy-list" "$FIXSRC/legacy-agent-sop-hooks.txt"
printf 'edited by hand\n' > "$MIG/.claude/scripts/hooks/agent-sop/sop-doctor.sh"   # not a listed version
printf 'unrelated\n' > "$MIG/.claude/scripts/hooks/agent-sop/notes.txt"              # not ours at all
OLD="$MIG/.claude/scripts/hooks/agent-sop"
jq -n --arg d "bash \"$OLD/" '{model:"m",hooks:{
  PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:($d+"sop-push-gate.sh\""),timeout:10}]},
              {matcher:"Bash",hooks:[{type:"command",command:"node keep-me.js"}]}],
  Stop:[{matcher:"*",hooks:[{type:"command",command:($d+"sop-stop-drift.sh\"")}]}],
  SessionStart:[{matcher:"*",hooks:[{type:"command",command:($d+"sop-session-context.sh\"")}]}]}}' > "$TMP/mig-settings.json"
mkdir -p "$MIG/.claude" && cp "$TMP/mig-settings.json" "$MIG/.claude/settings.json"
SHIP_SOP_USER_HOME="$MIG" bash "$FIXSRC/install-hooks.sh" > "$TMP/mig-out" 2>&1; MIGRC=$?
NEWCMD="bash \"$MIG/.claude/scripts/hooks/ship-sop/sop-push-gate.sh\""
if [ "$MIGRC" = 0 ] \
   && [ "$(jq '[.hooks[][].hooks[].command | select(test("sop-push-gate"))] | length' "$MIG/.claude/settings.json")" = 1 ] \
   && [ "$(jq -r '[.hooks.PreToolUse[].hooks[].command | select(test("sop-push-gate"))][0]' "$MIG/.claude/settings.json")" = "$NEWCMD" ] \
   && ! grep -q 'hooks/agent-sop' "$MIG/.claude/settings.json" \
   && [ "$(jq -c '.hooks | keys' "$MIG/.claude/settings.json")" = '["PreToolUse"]' ] \
   && [ "$(count "$MIG/.claude/settings.json" PreToolUse 'keep-me')" = 1 ] \
   && [ "$(jq -r .model "$MIG/.claude/settings.json")" = m ]; then
    ok "migration-leaves-one-registration-at-the-new-path"
else bad "migration-leaves-one-registration-at-the-new-path" "exit $MIGRC $(jq -c .hooks "$MIG/.claude/settings.json") $(cat "$TMP/mig-out")"; fi
if [ ! -e "$OLD/sop-lib.sh" ] && [ ! -e "$OLD/sop-push-gate.sh" ] && [ ! -e "$OLD/sop-stop-drift.sh" ] && [ ! -e "$OLD/resolve-resume-path.sh" ] \
   && [ -f "$OLD/sop-doctor.sh" ] && grep -q "keep $OLD/sop-doctor.sh (edited locally" "$TMP/mig-out" && [ -f "$OLD/notes.txt" ]; then
    ok "migration-removes-pristine-copies-and-keeps-edited-ones"
else bad "migration-removes-pristine-copies-and-keeps-edited-ones" "$(ls "$OLD" 2>&1) $(cat "$TMP/mig-out")"; fi
# A second run is a no-op and the gate it installed is executable.
SHIP_SOP_USER_HOME="$MIG" bash "$FIXSRC/install-hooks.sh" > "$TMP/mig-out2" 2>&1
if grep -q 'already up to date' "$TMP/mig-out2" && [ -x "$MIG/.claude/scripts/hooks/ship-sop/sop-push-gate.sh" ]; then ok "migration-rerun-is-a-no-op"; else bad "migration-rerun-is-a-no-op" "$(cat "$TMP/mig-out2")"; fi

# With the real list: a real shipped version (the one sop-project-type.sh that was
# ever released at the old path, reproduced byte for byte) is removed.
REALOLD="$TMP/realold"; mkdir -p "$REALOLD/.claude/scripts/hooks/agent-sop"
cat > "$REALOLD/.claude/scripts/hooks/agent-sop/sop-project-type.sh" <<'LEGACY'
#!/usr/bin/env bash
#
# sop-project-type.sh [root] — prints "code" or "non-code" for the repository
# at root (default: the git toplevel of the current directory). Exit 0 always.
#
# The executable form of one rule, `sop_project_type` in sop-lib.sh, so that
# /update-sop, /restart-sop, /finish, /ship and the compliance checker ask the
# same question the hooks answer and cannot drift from them. An explicit
# `**Project type:** code|non-code` line in CLAUDE.md wins; otherwise the four
# heuristics in docs/sop/compliance-checklist.md § Code vs Non-Code Detection.
#
# Installed user-scope by scripts/install-hooks.sh next to the hooks:
#   bash ~/.claude/scripts/hooks/agent-sop/sop-project-type.sh

set -u
. "$(dirname "${BASH_SOURCE[0]}")/sop-lib.sh"

ROOT="${1:-}"
if [ -z "$ROOT" ]; then
    ROOT=$(sop_repo_root "$PWD")
    [ -n "$ROOT" ] || ROOT="$PWD"
fi
sop_project_type "$ROOT"
printf '\n'
exit 0
LEGACY
REALBLOB=$(git hash-object --no-filters "$REALOLD/.claude/scripts/hooks/agent-sop/sop-project-type.sh")
SHIP_SOP_USER_HOME="$REALOLD" bash "$INSTALLER" > "$TMP/realold-out" 2>&1
if grep -qx "$REALBLOB sop-project-type.sh" "$LEGACY_LIST" && [ ! -e "$REALOLD/.claude/scripts/hooks/agent-sop" ]; then ok "migration-real-shipped-version-removed"; else bad "migration-real-shipped-version-removed" "blob $REALBLOB; $(cat "$TMP/realold-out")"; fi

# With the real list, a copy whose content matches no shipped version is kept.
REALMIG="$TMP/realmig"; mkdir -p "$REALMIG/.claude/scripts/hooks/agent-sop"
printf 'not a shipped version\n' > "$REALMIG/.claude/scripts/hooks/agent-sop/sop-push-gate.sh"
jq -n --arg c "bash \"$REALMIG/.claude/scripts/hooks/agent-sop/sop-push-gate.sh\"" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' > "$REALMIG/.claude/settings.json"
SHIP_SOP_USER_HOME="$REALMIG" bash "$INSTALLER" > "$TMP/realmig-out" 2>&1
if [ -f "$REALMIG/.claude/scripts/hooks/agent-sop/sop-push-gate.sh" ] && ! grep -q 'hooks/agent-sop' "$REALMIG/.claude/settings.json" \
   && [ "$(count "$REALMIG/.claude/settings.json" PreToolUse 'ship-sop/sop-push-gate')" = 1 ]; then ok "migration-edited-copy-kept-registration-moved"; else bad "migration-edited-copy-kept-registration-moved" "$(cat "$TMP/realmig-out")"; fi

# Codex: hooks.json entries pointing at either older copy go; pristine Codex copies go.
CXM="$TMP/cxmig"
cp "$LEGACY_LIST" "$TMP/legacy-list"
legacy_install "$CXM" .codex || bad "codex-migration-fixture" "legacy list lacks a file"
cp "$TMP/legacy-list" "$FIXSRC/legacy-agent-sop-hooks.txt"
jq -n --arg d "bash \"$CXM/.codex/scripts/hooks/agent-sop/" --arg c "bash \"$CXM/.claude/scripts/hooks/agent-sop/" '{hooks:{
  PreToolUse:[{matcher:".*",hooks:[{type:"command",command:($d+"sop-codex-hook.sh\" PreToolUse")}]}],
  Stop:[{matcher:".*",hooks:[{type:"command",command:($c+"sop-stop-drift.sh\"")},{type:"command",command:($d+"sop-codex-hook.sh\" Stop")}]}]}}' > "$CXM/.codex/hooks.json"
SHIP_SOP_USER_HOME="$CXM" bash "$FIXSRC/install-hooks.sh" --runtime codex > "$TMP/cxm-out" 2>&1
if jq -e '.hooks | keys == ["PreToolUse"]' "$CXM/.codex/hooks.json" >/dev/null \
   && [ "$(jq -r '.hooks.PreToolUse[0].hooks[0].command' "$CXM/.codex/hooks.json")" = "bash \"$CXM/.codex/scripts/hooks/ship-sop/sop-codex-hook.sh\" PreToolUse" ] \
   && [ "$(jq '[.hooks[][].hooks[]] | length' "$CXM/.codex/hooks.json")" = 1 ] \
   && [ ! -e "$CXM/.codex/scripts/hooks/agent-sop" ]; then ok "migration-codex"; else bad "migration-codex" "$(jq -c . "$CXM/.codex/hooks.json") $(cat "$TMP/cxm-out")"; fi

# --no-register leaves an older install, and its registration, alone.
NRM="$TMP/nrmig"
cp "$LEGACY_LIST" "$TMP/legacy-list"
legacy_install "$NRM" .claude || bad "no-register-fixture" "legacy list lacks a file"
cp "$TMP/legacy-list" "$FIXSRC/legacy-agent-sop-hooks.txt"
jq -n --arg c "bash \"$NRM/.claude/scripts/hooks/agent-sop/sop-push-gate.sh\"" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' > "$NRM/.claude/settings.json"
cp "$NRM/.claude/settings.json" "$TMP/nrm-before"
SHIP_SOP_USER_HOME="$NRM" bash "$FIXSRC/install-hooks.sh" --no-register >/dev/null 2>&1
if cmp -s "$TMP/nrm-before" "$NRM/.claude/settings.json" && [ -f "$NRM/.claude/scripts/hooks/agent-sop/sop-push-gate.sh" ] && [ -x "$NRM/.claude/scripts/hooks/ship-sop/sop-lib.sh" ]; then
    ok "migration-skipped-with-no-register"
else bad "migration-skipped-with-no-register" "$(cat "$NRM/.claude/settings.json")"; fi

# ── Entries that are not ours ─────────────────────────────────────────────────
# A flat entry and an entry with "hooks": [] in another event, and a flat legacy
# entry, are left exactly as they were; only entries holding a matching command
# change.
SHAPE="$TMP/shape.json"
jq -n --arg old "bash \"$TMP/shapehome/.claude/scripts/hooks/agent-sop/sop-push-gate.sh\"" '{hooks:{
  Stop:[{command:"node flat-stop.js"},{matcher:"*",hooks:[]}],
  PostToolUse:[{matcher:"Write",hooks:[]}],
  PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$old},{type:"command",command:"node keep.js"}]},
              {command:"node flat-pre.js"}]}}' > "$SHAPE"
mkdir -p "$TMP/shapehome/.claude"; cp "$SHAPE" "$TMP/shapehome/.claude/settings.json"
SHIP_SOP_USER_HOME="$TMP/shapehome" bash "$INSTALLER" > "$TMP/shape-out" 2>&1; SH=$?
SS="$TMP/shapehome/.claude/settings.json"
if [ "$SH" = 0 ] && [ "$(jq -cS '.hooks.Stop' "$SS")" = "$(jq -cS '.hooks.Stop' "$SHAPE")" ] \
   && [ "$(jq -cS '.hooks.PostToolUse' "$SS")" = "$(jq -cS '.hooks.PostToolUse' "$SHAPE")" ] \
   && [ "$(jq -c '.hooks.PreToolUse[0]' "$SS")" = '{"matcher":"Bash","hooks":[{"type":"command","command":"node keep.js"}]}' ] \
   && [ "$(jq -c '.hooks.PreToolUse[1]' "$SS")" = '{"command":"node flat-pre.js"}' ] \
   && [ "$(count "$SS" PreToolUse 'ship-sop/sop-push-gate')" = 1 ]; then
    ok "installer-leaves-flat-and-empty-entries-alone"
else bad "installer-leaves-flat-and-empty-entries-alone" "exit $SH $(jq -c .hooks "$SS") $(cat "$TMP/shape-out")"; fi
# The uninstall filter leaves them alone too.
SHIP_SOP_USER_HOME="$TMP/shapehome" bash "$INSTALLER" --uninstall >/dev/null 2>&1
if [ "$(jq -cS '.hooks.Stop' "$SS")" = "$(jq -cS '.hooks.Stop' "$SHAPE")" ] && [ "$(jq -cS '.hooks.PostToolUse' "$SS")" = "$(jq -cS '.hooks.PostToolUse' "$SHAPE")" ] \
   && [ "$(count "$SS" PreToolUse 'ship-sop')" = 0 ]; then ok "uninstall-leaves-flat-and-empty-entries-alone"; else bad "uninstall-leaves-flat-and-empty-entries-alone" "$(jq -c .hooks "$SS")"; fi
# An event that is not an array is named and nothing is written.
printf '{"hooks":{"Stop":{"command":"x"}}}\n' > "$TMP/notarray.json"; cp "$TMP/notarray.json" "$TMP/notarray.orig"
if bash "$INSTALLER" --settings "$TMP/notarray.json" --dest "$TMP/dest-na" > "$TMP/na-out" 2>&1; then bad "installer-names-non-array-event" "exit 0"
elif grep -q '.hooks.Stop is not an array' "$TMP/na-out" && cmp -s "$TMP/notarray.json" "$TMP/notarray.orig"; then ok "installer-names-non-array-event"
else bad "installer-names-non-array-event" "$(cat "$TMP/na-out")"; fi

# ── Stray registrations ───────────────────────────────────────────────────────
# A gate registered anywhere but our install dir would run beside ours: setup
# names it, exits non-zero and leaves the old copies in place.
for form in 'bash "/elsewhere/agent-sop/sop-push-gate.sh"' 'bash ~/.claude/scripts/hooks/agent-sop/sop-push-gate.sh' 'bash /opt/hooks/sop-push-gate.sh'; do
    STH="$TMP/stray-$RANDOM"
    cp "$LEGACY_LIST" "$TMP/legacy-list"
    legacy_install "$STH" .claude || bad "stray-fixture" "legacy list lacks a file"
    cp "$TMP/legacy-list" "$FIXSRC/legacy-agent-sop-hooks.txt"
    jq -n --arg c "$form" '{hooks:{PreToolUse:[{matcher:"Bash",hooks:[{type:"command",command:$c}]}]}}' > "$STH/.claude/settings.json"
    SHIP_SOP_USER_HOME="$STH" bash "$FIXSRC/install-hooks.sh" > "$TMP/stray-out" 2>&1; ST=$?
    if [ "$ST" != 0 ] && grep -q 'other push-gate registrations remain' "$TMP/stray-out" && grep -qF "$form" "$TMP/stray-out" \
       && [ -f "$STH/.claude/scripts/hooks/agent-sop/sop-push-gate.sh" ]; then ok "installer-refuses-stray-registration: $form"
    else bad "installer-refuses-stray-registration: $form" "exit $ST $(cat "$TMP/stray-out")"; fi
done

# ── Unreadable installed copies ───────────────────────────────────────────────
# A copy that cannot be hashed is never treated as unedited (an empty hash used
# to equal an empty manifest entry).
if [ "$(id -u)" != 0 ]; then
    UR="$TMP/unreadable"; URSET="$TMP/unreadable.json"
    bash "$INSTALLER" --settings "$URSET" --dest "$UR" >/dev/null 2>&1
    printf 'local edit\n' > "$UR/sop-project-type.sh"; rm -f "$UR/.installed"
    chmod 000 "$UR/sop-project-type.sh"
    bash "$INSTALLER" --settings "$URSET" --dest "$UR" > "$TMP/ur-out" 2>&1
    bash "$INSTALLER" --settings "$URSET" --dest "$UR" --uninstall > "$TMP/ur-un" 2>&1
    chmod 644 "$UR/sop-project-type.sh"
    if [ "$(cat "$UR/sop-project-type.sh")" = "local edit" ] && grep -q "keep $UR/sop-project-type.sh" "$TMP/ur-out" && grep -q "keep $UR/sop-project-type.sh" "$TMP/ur-un"; then
        ok "installer-keeps-unhashable-copy"
    else bad "installer-keeps-unhashable-copy" "$(cat "$TMP/ur-out" "$TMP/ur-un")"; fi
else
    ok "installer-keeps-unhashable-copy (skipped as root: every file is readable)"
fi

# ── Settings write ────────────────────────────────────────────────────────────
# The file keeps its mode, and the temporary file is made beside it (an
# unwritable TMPDIR does not matter).
MODESET="$TMP/mode/settings.json"; mkdir -p "$TMP/mode" "$TMP/ro-tmp"; printf '{}\n' > "$MODESET"; chmod 640 "$MODESET"; chmod 500 "$TMP/ro-tmp"
TMPDIR="$TMP/ro-tmp" bash "$INSTALLER" --settings "$MODESET" --dest "$TMP/mode-dest" > "$TMP/mode-out" 2>&1; MD=$?
chmod 700 "$TMP/ro-tmp"
MODE_NOW=$(stat -c %a "$MODESET" 2>/dev/null || stat -f %Lp "$MODESET")
if [ "$MD" = 0 ] && [ "$MODE_NOW" = 640 ] && [ "$(count "$MODESET" PreToolUse 'sop-push-gate')" = 1 ]; then ok "installer-keeps-settings-mode-and-writes-beside-it"; else bad "installer-keeps-settings-mode-and-writes-beside-it" "exit $MD mode $MODE_NOW $(cat "$TMP/mode-out")"; fi
# GNU stat (Linux): `-f` is file-system status and exits 0 with output that is not
# a mode, so the installer must ask for `-c %a` first. A stub on PATH plays GNU.
REAL_STAT=$(command -v stat); mkdir -p "$TMP/gnu-bin"
cat > "$TMP/gnu-bin/stat" <<STUB
#!/bin/bash
if [ "\$1" = -c ] && [ "\$2" = %a ]; then "$REAL_STAT" -c %a "\$3" 2>/dev/null || "$REAL_STAT" -f %Lp "\$3"; exit; fi
if [ "\$1" = -f ]; then echo '  File: "\$3"  ID: 0 Namelen: 255 Type: ext2/ext3'; exit 0; fi
exec "$REAL_STAT" "\$@"
STUB
chmod +x "$TMP/gnu-bin/stat"
GNUSET="$TMP/gnu/settings.json"; mkdir -p "$TMP/gnu"; printf '{}\n' > "$GNUSET"; chmod 644 "$GNUSET"
PATH="$TMP/gnu-bin:$PATH" bash "$INSTALLER" --settings "$GNUSET" --dest "$TMP/gnu-dest" > "$TMP/gnu-out" 2>&1; GD=$?
GNU_MODE=$(stat -c %a "$GNUSET" 2>/dev/null || stat -f %Lp "$GNUSET")
if [ "$GD" = 0 ] && [ "$GNU_MODE" = 644 ]; then ok "installer-reads-the-mode-with-gnu-stat"; else bad "installer-reads-the-mode-with-gnu-stat" "exit $GD mode $GNU_MODE $(cat "$TMP/gnu-out")"; fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "install-hooks: $pass passed, $fail failed"
SUITE_DONE=1
[ "$fail" -eq 0 ] || { echo "Failed:$failed"; exit 1; }
exit 0
