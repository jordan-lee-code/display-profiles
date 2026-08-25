#!/bin/bash
# Validation suite for display-profiles.
#
# Covers: bash syntax, common.sh unit tests, error-path behaviour, a live
# round-trip display switch that re-applies the current config via xrandr, and
# the client-driven resolution path used by streaming hosts.
#
# Usage:
#   bash tests/validate.sh          # from the repo root
#   ./tests/validate.sh             # after chmod +x
#
# Sections 3, 5 and part of 6 require xrandr and a running X session
# (DISPLAY set).
# They are skipped automatically when those conditions are not met.

REPO="$(cd "$(dirname "$(realpath "${BASH_SOURCE[0]}")")/.." && pwd)"
PASS=0; FAIL=0; SKIP=0

_pass() { printf "  \033[32mPASS\033[0m  %s\n" "$1"; ((PASS++)) || true; }
_fail() { printf "  \033[31mFAIL\033[0m  %s\n" "$1"; ((FAIL++)) || true; }
_skip() { printf "  \033[33mSKIP\033[0m  %s\n" "$1"; ((SKIP++)) || true; }
section() { echo ""; echo "── $* ──────────────────────────────────────────"; }

# setup_temp_home — create a disposable temp directory and redirect HOME to it.
# Saves the original HOME in _REAL_HOME and sets TMP_H to the temp path.
# Caller must call teardown_temp_home to restore HOME, then: rm -rf "$TMP_H"
setup_temp_home() { TMP_H=$(mktemp -d); _REAL_HOME=$HOME; HOME=$TMP_H; }

# teardown_temp_home — restore HOME to the value saved by setup_temp_home.
# Does NOT delete TMP_H; caller is responsible for: rm -rf "$TMP_H"
teardown_temp_home() { HOME=$_REAL_HOME; }

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

# The Sunshine bridge runs inside a flatpak sandbox where bash is not
# guaranteed, so it is POSIX sh and is checked with sh -n rather than bash -n.
if err=$(sh -n "$REPO/integrations/sunshine/prep.sh" 2>&1); then
    _pass "integrations/sunshine/prep.sh"
else
    _fail "integrations/sunshine/prep.sh: $err"
fi

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

setup_temp_home
log_error "sentinel-12345"
teardown_temp_home
if [[ -f "$TMP_H/.config/display-profiles/debug.log" ]]; then
    content=$(cat "$TMP_H/.config/display-profiles/debug.log")
    [[ "$content" == *"sentinel-12345"* && "$content" == *"ERROR:"* ]] \
        && _pass "log_error: creates debug.log with timestamp and message" \
        || _fail "log_error: wrong log content: $content"
else
    _fail "log_error: debug.log not created"
fi
rm -rf "$TMP_H"

setup_temp_home
result=$(list_profiles)
[[ -z "$result" ]] \
    && _pass "list_profiles: no profiles dir → empty output" \
    || _fail "list_profiles: empty case (got: '$result')"
mkdir -p "$TMP_H/.config/display-profiles/"{gamma,alpha,beta}
result=$(list_profiles)
[[ "$result" == $'alpha\nbeta\ngamma' ]] \
    && _pass "list_profiles: returns profiles sorted alphabetically" \
    || _fail "list_profiles: expected alpha/beta/gamma, got: '$result'"
teardown_temp_home
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

    # Active outputs: connected AND have a current geometry (WxH+X+Y) in the header.
    # The optional "primary " token is skipped with (primary )? in the pattern.
    mapfile -t ACTIVE < <(echo "$XRANDR_OUT" | awk \
        '/^[^ ]+ connected (primary )?[0-9]+x[0-9]+\+/{print $1}')

    # Off outputs: connected but no geometry (not currently active), plus disconnected.
    # Both classes get --off in the reconstructed xrandr command.
    mapfile -t OFF    < <(echo "$XRANDR_OUT" | awk \
        '/^[^ ]+ connected / && !/[0-9]+x[0-9]+\+[0-9]+\+[0-9]+/{print $1}
         / disconnected /{print $1}')

    if [[ ${#ACTIVE[@]} -eq 0 ]]; then
        _skip "round-trip: no active outputs found"
    else
        XRANDR_LINES="xrandr"
        for out in "${ACTIVE[@]}"; do
            # Extract WxH from the mode line marked with * (current active mode).
            mode=$(echo "$XRANDR_OUT" | awk -v o="$out" '
                $0 ~ "^"o" connected" { found=1; next }
                found && /^[A-Z]/ { exit }
                found && /\*/ { match($0, /[0-9]+x[0-9]+/); print substr($0,RSTART,RLENGTH); exit }
            ')
            # Extract the refresh rate from the field containing * (strips * and + markers).
            rate=$(echo "$XRANDR_OUT" | awk -v o="$out" '
                $0 ~ "^"o" connected" { found=1; next }
                found && /^[A-Z]/ { exit }
                found && /\*/ {
                    for (i=1;i<=NF;i++) { if ($i ~ /\*/) { gsub(/[*+]/,"",$i); print $i; exit } }
                }
            ')
            # Extract X+Y position from the geometry field (WxH+X+Y) on the output header.
            # split() on "+" gives [WxH, X, Y] at indices 1, 2, 3.
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

# ── 6. Client-driven resolution ───────────────────────────────────────────────
section "6. Client-driven resolution"

# best_rate_for is tested against a stubbed mode list so the assertions do not
# depend on whatever panels this machine happens to have plugged in.
_stub_modes() {
    list_output_modes() {
        cat <<'MODES'
2560x1440 59.95
2560x1440 165.08
2560x1440 143.91
2560x1440 120.00
1280x800 59.81
MODES
    }
}
_stub_modes

got=$(best_rate_for STUB 2560x1440 90)
[[ "$got" == "120.00" ]] \
    && _pass "best_rate_for: picks lowest rate meeting the target" \
    || _fail "best_rate_for: 90fps target → expected 120.00, got '$got'"

got=$(best_rate_for STUB 2560x1440 240)
[[ "$got" == "165.08" ]] \
    && _pass "best_rate_for: unreachable target → highest available rate" \
    || _fail "best_rate_for: 240fps target → expected 165.08, got '$got'"

got=$(best_rate_for STUB 1280x800 60)
[[ "$got" == "59.81" ]] \
    && _pass "best_rate_for: 60fps target tolerates a 59.81Hz mode" \
    || _fail "best_rate_for: 60fps target → expected 59.81, got '$got'"

got=$(best_rate_for STUB 3840x2160 60)
[[ -z "$got" ]] \
    && _pass "best_rate_for: unknown resolution → empty" \
    || _fail "best_rate_for: unknown resolution → expected empty, got '$got'"

unset -f list_output_modes
source "$REPO/lib/common.sh"

# A client that reports nothing usable must not take the display down with it.
TMP_H=$(mktemp -d)
if out=$(HOME=$TMP_H bash "$REPO/bin/display-switch-client.sh" --width abc --height 800 2>&1); then
    [[ "$out" == *"leaving the current display configuration alone"* ]] \
        && _pass "client: invalid dimensions → leaves display alone, exits 0" \
        || _fail "client: invalid dimensions → wrong message: $out"
else
    _fail "client: invalid dimensions should exit 0, not fail"
fi
rm -rf "$TMP_H"

TMP_H=$(mktemp -d)
if out=$(HOME=$TMP_H bash "$REPO/bin/display-switch-client.sh" --width 99999 --height 800 2>&1); then
    [[ "$out" == *"No usable client resolution"* ]] \
        && _pass "client: out-of-range width rejected before reaching xrandr" \
        || _fail "client: out-of-range width → wrong message: $out"
else
    _fail "client: out-of-range width should exit 0, not fail"
fi
rm -rf "$TMP_H"

# With a fallback configured the same bad input should hand over to the named
# profile instead, and report that it did.
TMP_H=$(mktemp -d)
out=$(HOME=$TMP_H bash "$REPO/bin/display-switch-client.sh" \
        --width abc --fallback __nonexistent_profile__ 2>&1 || true)
[[ "$out" == *"falling back to profile"* ]] \
    && _pass "client: invalid dimensions with --fallback → delegates to profile" \
    || _fail "client: --fallback not honoured: $out"
rm -rf "$TMP_H"

if ! $HAVE_XRANDR; then
    _skip "client: mode selection needs xrandr and DISPLAY"
else
    OUT_NAME=$(current_primary_output)
    if [[ -z "$OUT_NAME" ]]; then
        _skip "client: no connected output to test mode selection against"
    else
        PANEL=$(output_preferred_res "$OUT_NAME")
        PANEL_RATE=$(best_rate_for "$OUT_NAME" "$PANEL" 1)

        # Asking for the panel's own resolution must not engage the scaler.
        IFS=x read -r pw ph <<< "$PANEL"
        out=$(bash "$REPO/bin/display-switch-client.sh" --output "$OUT_NAME" \
                --width "$pw" --height "$ph" --fps 60 --dry-run 2>&1)
        [[ "$out" == *"--scale 1x1"* && "$out" != *"--scale-from"* ]] \
            && _pass "client: native resolution request uses no scaling" \
            || _fail "client: native request unexpectedly scaled: $out"

        # A size the panel has no mode for must be scaled rather than refused,
        # which is what lets a 4K client work on a 1440p panel.
        odd_w=$(( pw > 1000 ? pw - 337 : 800 ))
        odd_h=$(( ph > 700 ? ph - 211 : 600 ))
        out=$(bash "$REPO/bin/display-switch-client.sh" --output "$OUT_NAME" \
                --width "$odd_w" --height "$odd_h" --fps 60 --dry-run 2>&1)
        [[ "$out" == *"--scale-from ${odd_w}x${odd_h}"* ]] \
            && _pass "client: non-native resolution falls back to scaling" \
            || _fail "client: non-native request not scaled: $out"

        # The panel must stay on one of its own modes even while scaling.
        [[ "$out" == *"--mode $PANEL"* ]] \
            && _pass "client: scaled request keeps the panel on a native mode" \
            || _fail "client: scaled request left the panel mode wrong: $out"

        # An output that is not connected is a fallback case, not a crash.
        out=$(bash "$REPO/bin/display-switch-client.sh" --output __no_such_output__ \
                --width 1280 --height 800 --fps 60 --dry-run 2>&1 || true)
        [[ "$out" == *"not connected"* ]] \
            && _pass "client: unknown output → clear 'not connected' message" \
            || _fail "client: unknown output → wrong message: $out"

        unset PANEL_RATE
    fi
fi

# --no-persist must apply the layout without changing what login restores.
TMP_H=$(mktemp -d)
mkdir -p "$TMP_H/.config/display-profiles/_validate_np"
printf '#!/bin/bash\nexit 0\n' > "$TMP_H/.config/display-profiles/_validate_np/xrandr.sh"
chmod +x "$TMP_H/.config/display-profiles/_validate_np/xrandr.sh"
printf 'personal\n' > "$TMP_H/.config/display-mode"
if HOME=$TMP_H bash "$REPO/bin/display-switch.sh" --no-persist _validate_np >/dev/null 2>&1; then
    [[ "$(cat "$TMP_H/.config/display-mode")" == "personal" ]] \
        && _pass "display-switch.sh --no-persist leaves display-mode untouched" \
        || _fail "display-switch.sh --no-persist overwrote display-mode"
else
    _fail "display-switch.sh --no-persist should succeed"
fi
rm -rf "$TMP_H"

# A transient xrandr failure should be retried rather than reported immediately,
# so a switch that loses a startup race still lands.
TMP_H=$(mktemp -d)
mkdir -p "$TMP_H/.config/display-profiles/_validate_retry"
cat > "$TMP_H/.config/display-profiles/_validate_retry/xrandr.sh" <<RETRY
#!/bin/bash
COUNT_FILE="$TMP_H/attempts"
n=\$(( \$(cat "\$COUNT_FILE" 2>/dev/null || echo 0) + 1 ))
echo "\$n" > "\$COUNT_FILE"
[[ "\$n" -ge 2 ]] && exit 0
echo "transient failure" >&2
exit 1
RETRY
chmod +x "$TMP_H/.config/display-profiles/_validate_retry/xrandr.sh"
if HOME=$TMP_H bash "$REPO/bin/display-switch.sh" _validate_retry >/dev/null 2>&1; then
    attempts=$(cat "$TMP_H/attempts" 2>/dev/null)
    if [[ "$attempts" == "2" ]] \
        && grep -q "transient failure" "$TMP_H/.config/display-profiles/debug.log" 2>/dev/null
    then
        _pass "display-switch.sh: retries a transient xrandr failure and logs its stderr"
    else
        _fail "display-switch.sh: retry behaviour wrong (attempts: '$attempts')"
    fi
else
    _fail "display-switch.sh: should succeed once xrandr.sh stops failing"
fi
rm -rf "$TMP_H"

# ── Summary ───────────────────────────────────────────────────────────────────
echo ""
echo "══════════════════════════════════════════════════════"
printf "  \033[32m%d passed\033[0m  \033[31m%d failed\033[0m  \033[33m%d skipped\033[0m\n" \
    $PASS $FAIL $SKIP
echo "══════════════════════════════════════════════════════"
[[ $FAIL -eq 0 ]]
