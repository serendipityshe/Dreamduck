#!/bin/sh
# Exercise detection and unit generation without changing the host's services.
set -eu
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)
TEST_BASE=$(CDPATH='' cd -- "${TMPDIR:-/tmp}" && pwd -P)
TEST_DIR=$(mktemp -d "$TEST_BASE/a733-dev-test.XXXXXX")
case "$TEST_DIR" in
    "$TEST_BASE"/a733-dev-test.*) ;;
    *) printf 'unexpected test directory: %s\n' "$TEST_DIR" >&2; exit 1 ;;
esac
trap 'rm -rf -- "$TEST_DIR"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$TEST_DIR/bin"

cat > "$TEST_DIR/bin/uname" <<'EOF'
#!/bin/sh
case "$1" in
    -s) printf '%s\n' "${TEST_OS:-Linux}" ;;
    -m) printf '%s\n' "${TEST_ARCH:-aarch64}" ;;
esac
EOF
cat > "$TEST_DIR/bin/id" <<'EOF'
#!/bin/sh
case "$1:$2" in
    -u:) echo "${TEST_UID:-1000}" ;;
    -u:duck) echo 1000 ;;
    -u:root) echo 0 ;;
    -gn:duck) echo duck ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$TEST_DIR/bin/uname" "$TEST_DIR/bin/id"
PATH="$TEST_DIR/bin:$PATH"
export PATH

run() { sh "$REPO/scripts/a733-dev.sh" "$@"; }
reject() {
    if run "$@" > "$TEST_DIR/out" 2>&1; then
        printf 'FAIL: unexpectedly accepted: %s\n' "$*" >&2
        exit 1
    fi
}

printf 'xunlong,orangepi-zero3w\000arm,sun60iw2p1\000' > "$TEST_DIR/a733"
printf 'radxa,zero3\000rockchip,rk3566\000' > "$TEST_DIR/radxa"
printf 'xunlong,orangepi-zero3w\000allwinner,sun50i-h618\000' > "$TEST_DIR/h618"
printf 'xunlong,orangepi-zero3w-extra\000arm,sun60iw2p1\000' > "$TEST_DIR/partial"
run check "$TEST_DIR/a733" > "$TEST_DIR/out"
reject check "$TEST_DIR/radxa"
reject check "$TEST_DIR/h618"
reject check "$TEST_DIR/partial"
reject check "$TEST_DIR/missing"
TEST_ARCH=x86_64 reject check "$TEST_DIR/a733"
TEST_OS=Darwin reject check "$TEST_DIR/a733"

# An unprivileged account and the fake flags are essential even when root installs it.
run unit duck > "$TEST_DIR/unit"
grep -qx 'User=duck' "$TEST_DIR/unit"
grep -qx 'Group=duck' "$TEST_DIR/unit"
grep -qx 'RuntimeDirectory=dreamduck-a733-dev' "$TEST_DIR/unit"
grep -qx 'RuntimeDirectoryMode=0750' "$TEST_DIR/unit"
# The default /run/robotd directory cannot be created by the bench account.
# Pin the existing identity writer to the directory systemd grants this service.
grep -qx 'Environment=DUCK_RUNTIME_DIR=/run/dreamduck-a733-dev' "$TEST_DIR/unit"
grep -Fqx "WorkingDirectory=$REPO" "$TEST_DIR/unit"
grep -Fqx "ExecStart=$REPO/target/debug/robotd --fake --no-policy --params $REPO/deploy/robotd-a733-dev.toml --socket /run/dreamduck-a733-dev/robotd.sock" "$TEST_DIR/unit"
reject unit root
reject unit unknown
reject unit 'duck%u'
reject install duck
TEST_UID=0 TEST_ARCH=x86_64 reject install duck
reject install duck extra
reject nonexistent-command

# Client routing must stay on the bench socket rather than /run/robotd.sock.
mkdir -p "$TEST_DIR/repo/scripts" "$TEST_DIR/repo/target/debug"
cp "$REPO/scripts/a733-dev.sh" "$TEST_DIR/repo/scripts/"
cat > "$TEST_DIR/repo/target/debug/robotctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$@"
EOF
cat > "$TEST_DIR/bin/systemctl" <<'EOF'
#!/bin/sh
printf '%s\n' "$@"
EOF
chmod +x "$TEST_DIR/repo/target/debug/robotctl" "$TEST_DIR/bin/systemctl"
sh "$TEST_DIR/repo/scripts/a733-dev.sh" health --json > "$TEST_DIR/out"
printf '%s\n' --robot-socket /run/dreamduck-a733-dev/robotd.sock health --json > "$TEST_DIR/want"
cmp "$TEST_DIR/want" "$TEST_DIR/out"
run status > "$TEST_DIR/out"
printf '%s\n' --no-pager status dreamduck-a733-dev.service > "$TEST_DIR/want"
cmp "$TEST_DIR/want" "$TEST_DIR/out"
reject stop
TEST_UID=0 run disable > "$TEST_DIR/out"
printf '%s\n' disable --now dreamduck-a733-dev.service > "$TEST_DIR/want"
cmp "$TEST_DIR/want" "$TEST_DIR/out"
printf 'PASS: A733 detection, fake-only unit, privilege checks and service/client routing\n'
