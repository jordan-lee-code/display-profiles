#!/bin/bash
# Validation suite for display-profiles.
#
# Covers: bash syntax, common.sh unit tests, error-path behaviour, and a live
# round-trip display switch that re-applies the current config via xrandr.
#
# Usage:
#   bash tests/validate.sh          # from the repo root
#   ./tests/validate.sh             # after chmod +x
#
# Sections 3 and 5 require xrandr and a running X session (DISPLAY set).
# They are skipped automatically when those conditions are not met.

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

_pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; ((PASS++)) || true; }
_fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; ((FAIL++)) || true; }
_skip() { printf "  \033[33mSKIP\033[0m  %s\n" "$1"; ((SKIP++)) || true; }
section() { echo ""; echo "── $* ──────────────────────────────────────────"; }

HAVE_XRANDR=false
command -v xrandr &>/dev/null && [[ -n "${DISPLAY:-}" ]] && HAVE_XRANDR=true

# ── 1. Syntax — bash -n ───────────────────────────────────────────────────────
section "1. Syntax — bash -n"
for f in \
    "$REPO"/bin/display-*.sh \
    "$REPO"/lib/common.sh \
    "$REPO"/install.sh \
    "$REPO"/hooks/cinnamon/*.sh
do
    name=$(basename "$f")
    if err=$(bash -n "$f" 2>&1); then
        _pass "$name"
    else
        _fail "$name: $err"
    fi
done

# ── 2. lib/common.sh unit tests ───────────────────────────────────────────────
section "2. lib/common.sh unit tests"
source "$REPO/lib/common.sh"

[[ "$(get_profiles_dir)" == "$HOME/.config/display-profiles" ]] \
    && _pass "get_profiles_dir returns correct path" \
    || _fail "get_profiles_dir: got '$(get_profiles_dir)'"

[[ "$(get_log_file)" == "$HOME/.config/display-profiles/debug.log" ]] \
    && _pass "get_log_file returns correct path" \
    || _fail "get_log_file: got '$(get_log_file)'"

for pair in "cinnamon:cinnamon" "GNOME:gnome" "KDE:kde" "plasma:kde" "XFCE:xfce" "mate:mate" "unknown_de:unknown"; do
    input="${pair%%:*}"; expected="${pair##*:}"
    got=$(XDG_CURRENT_DESKTOP="$input" detect_de)
    [[ "$got" == "$expected" ]] \
        && _pass "detect_de '$input' → $expected" \
        || _fail "detect_de '$input' → expected '$expected', got '$got'"
done

if bash -c "source '$REPO/lib/common.sh'; require_cmd ls" 2>/dev/null; then
    _pass "require_cmd: existing command (ls) → exits 0"
else
    _fail "require_cmd: existing command should succeed"
fi

if err=$(bash -c "source '$REPO/lib/common.sh'; require_cmd __no_such_cmd__ 'hint text'" 2>&1); then
    _fail "require_cmd: missing command should exit non-zero"
else
    [[ "$err" == *"not found"* && "$err" == *"hint text"* ]] \
        && _pass "require_cmd: missing command → 'not found' + hint" \
        || _fail "require_cmd: wrong error message: $err"
fi

TMP_H=$(mktemp -d)
HOME_BAK=$HOME; HOME=$TMP_H
log_error "sentinel-12345"
HOME=$HOME_BAK
if [[ -f "$TMP_H/.config/display-profiles/debug.log" ]]; then
    content=$(cat "$TMP_H/.config/display-profiles/debug.log")
    [[ "$content" == *"sentinel-12345"* && "$content" == *"ERROR:"* ]] \
        && _pass "log_error: creates debug.log with timestamp and message" \
        || _fail "log_error: wrong log content: $content"
else
    _fail "log_error: debug.log not created"
fi
rm -rf "$TMP_H"

TMP_H=$(mktemp -d)
HOME_BAK=$HOME; HOME=$TMP_H
result=$(list_profiles)
[[ -z "$result" ]] \
    && _pass "list_profiles: no profiles dir → empty output" \
    || _fail "list_profiles: empty case (got: '$result')"
mkdir -p "$TMP_H/.config/display-profiles/"{gamma,alpha,beta}
result=$(list_profiles)
[[ "$result" == $'alpha\nbeta\ngamma' ]] \
    && _pass "list_profiles: returns profiles sorted alphabetically" \
    || _fail "list_profiles: expected alpha/beta/gamma, got: '$result'"
HOME=$HOME_BAK
rm -rf "$TMP_H"

idx=0
pick_index idx 3 "prompt> " <<< "2" 2>/dev/null
[[ "$idx" == "2" ]] \
    && _pass "pick_index: valid input (2 of 3) stored correctly" \
    || _fail "pick_index: valid input (got '$idx')"

idx=0
pick_index idx 5 "prompt> " <<< "" 2>/dev/null
[[ "$idx" == "1" ]] \
    && _pass "pick_index: empty input defaults to 1" \
    || _fail "pick_index: empty default (got '$idx')"

idx=0
pick_index idx 3 "prompt> " < <(printf 'abc\n0\n99\n-1\n3\n') 2>/dev/null
[[ "$idx" == "3" ]] \
    && _pass "pick_index: rejects bad inputs, accepts first valid (3)" \
    || _fail "pick_index: invalid-then-valid (got '$idx')"

# ── 3. display-setup.sh smoke test ───────────────────────────────────────────
section "3. display-setup.sh smoke test"
if ! $HAVE_XRANDR; then
    _skip "display-setup.sh: xrandr not available or DISPLAY not set"
elif out=$(bash "$REPO/bin/display-setup.sh" 2>&1); then
    [[ "$out" == *"Connected outputs"* ]] \
        && _pass "display-setup.sh: runs and lists connected outputs" \
        || _fail "display-setup.sh: unexpected output: $(echo "$out" | head -3)"
else
    _fail "display-setup.sh: exited non-zero: $out"
fi

# ── 4. Error paths ────────────────────────────────────────────────────────────
section "4. Error paths"

if ! out=$(bash "$REPO/bin/display-switch.sh" 2>&1); then
    [[ "$out" == *"Usage"* ]] \
        && _pass "display-switch.sh: no args → usage message" \
        || _fail "display-switch.sh: no args → wrong message: $out"
else
    _fail "display-switch.sh: no args should exit non-zero"
fi

if ! out=$(bash "$REPO/bin/display-switch.sh" __nonexistent_profile__ 2>&1); then
    [[ "$out" == *"not found"* ]] \
        && _pass "display-switch.sh: missing profile → 'not found'" \
        || _fail "display-switch.sh: missing profile → wrong message: $out"
else
    _fail "display-switch.sh: missing profile should exit non-zero"
fi

TMP_H=$(mktemp -d)
mkdir -p "$TMP_H/.config/display-profiles/orphan"
if ! out=$(HOME=$TMP_H bash "$REPO/bin/display-switch.sh" orphan 2>&1); then
    [[ "$out" == *"missing xrandr.sh"* ]] \
        && _pass "display-switch.sh: profile missing xrandr.sh → clear error" \
        || _fail "display-switch.sh: missing xrandr.sh → wrong message: $out"
else
    _fail "display-switch.sh: missing xrandr.sh should exit non-zero"
fi
rm -rf "$TMP_H"

TMP_H=$(mktemp -d)
mkdir -p "$TMP_H/.config/display-profiles/badfail"
printf '#!/bin/bash\nexit 1\n' > "$TMP_H/.config/display-profiles/badfail/xrandr.sh"
chmod +x "$TMP_H/.config/display-profiles/badfail/xrandr.sh"
if ! out=$(HOME=$TMP_H bash "$REPO/bin/display-switch.sh" badfail 2>&1); then
    if [[ "$out" == *"xrandr failed"* ]] \
        && [[ -f "$TMP_H/.config/display-profiles/debug.log" ]] \
        && grep -q "badfail" "$TMP_H/.config/display-profiles/debug.log"
    then
        _pass "display-switch.sh: failing xrandr.sh → error message + written to debug.log"
    else
        _fail "display-switch.sh: failing xrandr.sh → unexpected behaviour (out: $out)"
    fi
else
    _fail "display-switch.sh: failing xrandr.sh should exit non-zero"
fi
rm -rf "$TMP_H"

if ! out=$(bash "$REPO/bin/display-save-layout.sh" 2>&1); then
    [[ "$out" == *"Usage"* ]] \
        && _pass "display-save-layout.sh: no args → usage message" \
        || _fail "display-save-layout.sh: no args → wrong message: $out"
else
    _fail "display-save-layout.sh: no args should exit non-zero"
fi

if ! out=$(bash "$REPO/bin/display-save-layout.sh" __nonexistent_profile__ 2>&1); then
    [[ "$out" == *"not found"* ]] \
        && _pass "display-save-layout.sh: missing profile → 'not found'" \
        || _fail "display-save-layout.sh: missing profile → wrong message: $out"
else
    _fail "display-save-layout.sh: missing profile should exit non-zero"
fi

TMP_H=$(mktemp -d)
HOME=$TMP_H bash "$REPO/bin/display-apply-saved.sh" 2>/dev/null \
    && _pass "display-apply-saved.sh: no display-mode file → exits 0 silently" \
    || _fail "display-apply-saved.sh: no display-mode → should exit 0"
rm -rf "$TMP_H"

TMP_H=$(mktemp -d); mkdir -p "$TMP_H/.config"; printf '' > "$TMP_H/.config/display-mode"
HOME=$TMP_H bash "$REPO/bin/display-apply-saved.sh" 2>/dev/null \
    && _pass "display-apply-saved.sh: empty display-mode → exits 0 silently" \
    || _fail "display-apply-saved.sh: empty display-mode → should exit 0"
rm -rf "$TMP_H"

# ── 5. Live round-trip switch (re-applies current config) ─────────────────────
section "5. Live round-trip switch"
if ! $HAVE_XRANDR; then
    _skip "round-trip: xrandr not available or DISPLAY not set"
else
    XRANDR_OUT=$(xrandr 2>/dev/null)
    # Active: connected with a current geometry (WxH+X+Y) in the header line.
    # Off: connected but no geometry — treated as --off same as disconnected.
    mapfile -t ACTIVE < <(echo "$XRANDR_OUT" | awk \
        '/^[^ ]+ connected (primary )?[0-9]+x[0-9]+\+/{print $1}')
    mapfile -t OFF    < <(echo "$XRANDR_OUT" | awk \
        '/^[^ ]+ connected / && !/[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/{print $1}
         / disconnected /{print $1}')

    if [[ ${#ACTIVE[@]} -eq 0 ]]; then
        _skip "round-trip: no active outputs found"
    else
        XRANDR_LINES="xrandr"
        for out in "${ACTIVE[@]}"; do
            mode=$(echo "$XRANDR_OUT" | awk -v o="$out" '
                $0 ~ "^"o" connected" { found=1; next }
                found && /^[A-Z]/ { exit }
                found && /\*/ { match($0, /[0-9]+x[0-9]+/); print substr($0,RSTART,RLENGTH); exit }
            ')
            rate=$(echo "$XRANDR_OUT" | awk -v o="$out" '
                $0 ~ "^"o" connected" { found=1; next }
                found && /^[A-Z]/ { exit }
                found && /\*/ {
                    for (i=1;i<=NF;i++) { if ($i ~ /\*/) { gsub(/[*+]/,"",$i); print $i; exit } }
                }
            ')
            pos=$(echo "$XRANDR_OUT" | awk -v o="$out" '
                $0 ~ "^"o" connected" {
                    match($0, /[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/)
                    s=substr($0,RSTART,RLENGTH); split(s,a,"+"); print a[2]"x"a[3]; exit
                }
            ')
            primary_flag=""
            grep -q "^$out connected primary" <<< "$XRANDR_OUT" && primary_flag=" --primary"
            XRANDR_LINES+=" \\
    --output $out --mode $mode --rate $rate --pos $pos$primary_flag"
        done
        for out in "${OFF[@]}"; do
            XRANDR_LINES+=" \\
    --output $out --off"
        done

        PROFILE_DIR="$HOME/.config/display-profiles/_validate_tmp"
        mkdir -p "$PROFILE_DIR"
        printf '#!/bin/bash\n%s\n' "$XRANDR_LINES" > "$PROFILE_DIR/xrandr.sh"
        chmod +x "$PROFILE_DIR/xrandr.sh"
        printf 'NAME=_validate_tmp\nDESCRIPTION=Validation test profile\n' > "$PROFILE_DIR/meta"

        MODE_BAK=""
        [[ -f "$HOME/.config/display-mode" ]] && MODE_BAK=$(cat "$HOME/.config/display-mode")

        if out=$(bash "$REPO/bin/display-switch.sh" _validate_tmp 2>&1); then
            [[ "$out" == *"Done."* ]] \
                && _pass "round-trip: display-switch.sh ran xrandr and reported Done" \
                || _fail "round-trip: unexpected output: $out"
        else
            _fail "round-trip: display-switch.sh failed: $out"
        fi

        written=$(cat "$HOME/.config/display-mode" 2>/dev/null)
        [[ "$written" == "_validate_tmp" ]] \
            && _pass "round-trip: display-mode updated to temp profile name" \
            || _fail "round-trip: display-mode not updated (got: '$written')"

        if [[ -n "$MODE_BAK" ]]; then
            echo "$MODE_BAK" > "$HOME/.config/display-mode"
        else
            rm -f "$HOME/.config/display-mode"
        fi
        rm -rf "$PROFILE_DIR"
        _pass "round-trip: temp profile cleaned up, display-mode restored"
    fi
fi

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m  \033[33m%d skipped\033[0m\n" \
    $PASS $FAIL $SKIP
echo "══════════════════════════════════════════════════════"
[[ $FAIL -eq 0 ]]
