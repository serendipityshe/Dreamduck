#!/bin/sh
# Source-built, fake-only bench service. The signed release installer remains separate.
set -eu

UNIT=dreamduck-a733-dev.service
RUNTIME_ROOT=/run/dreamduck-a733-dev
SOCKET=$RUNTIME_ROOT/robotd.sock
REPO=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd -P)

die() { printf 'error: %s\n' "$*" >&2; exit 1; }

usage() {
    cat <<'EOF'
Usage: sh scripts/a733-dev.sh COMMAND [ARGS]
  check [compatible-file]  Check Linux ARM64 and the A733 device tree (read only)
  unit [user]             Print the fake-only systemd unit (read only)
  install [user]          Install, enable at boot and restart it (sudo required)
  start | stop | restart  Control the service (sudo required)
  status                  Show service status
  logs [journalctl-args]   Show the last 60 log lines; add -f to follow
  health [--json]         Query this service's robot socket
  disable                 Stop and disable boot startup (sudo required)
EOF
}

check_board() {
    [ "$(uname -s)" = Linux ] || die 'this service requires Linux'
    [ "$(uname -m)" = aarch64 ] || die 'this service requires aarch64'
    compatible_file=${1:-/proc/device-tree/compatible}
    [ -r "$compatible_file" ] || die "cannot read device tree: $compatible_file"
    compatibles=$(tr '\000' '\n' < "$compatible_file")
    # Both exact tokens are required: the model alone does not identify the SoC.
    printf '%s\n' "$compatibles" | grep -qx 'xunlong,orangepi-zero3w' ||
        die 'expected Orange Pi Zero 3W (xunlong,orangepi-zero3w)'
    printf '%s\n' "$compatibles" | grep -qx 'arm,sun60iw2p1' ||
        die 'expected A733 (arm,sun60iw2p1)'
    printf 'Board: Orange Pi Zero 3W / A733 / aarch64\nMode: fake hardware, no policy\n'
}

render_unit() {
    service_user=${1:-${SUDO_USER:-$(id -un)}}
    case "$service_user" in
        ''|*[!a-zA-Z0-9_-]*) die 'invalid service user' ;;
    esac
    service_uid=$(id -u "$service_user") || die "unknown user: $service_user"
    [ "$service_uid" -gt 0 ] || die 'the development service must use a non-root user'
    service_group=$(id -gn "$service_user")
    case "$service_group" in
        ''|*[!a-zA-Z0-9_-]*) die 'invalid service group' ;;
    esac
    # systemd interprets specifiers and environment references in unit values. Keep
    # source paths literal rather than silently generating a different ExecStart.
    case "$REPO" in
        *[!a-zA-Z0-9_/.-]*) die 'source path must contain only letters, digits, _, /, . and -' ;;
    esac
    cat <<EOF
[Unit]
Description=Dreamduck A733 development (fake hardware, no policy)
After=local-fs.target

[Service]
Type=exec
User=$service_user
Group=$service_group
WorkingDirectory=$REPO
ExecStart=$REPO/target/debug/robotd --fake --no-policy --params $REPO/deploy/robotd-a733-dev.toml --socket $SOCKET
Restart=on-failure
RestartSec=2s
RuntimeDirectory=dreamduck-a733-dev
RuntimeDirectoryMode=0750
NoNewPrivileges=yes
Environment=RUST_LOG=info
Environment=DUCK_RUNTIME_DIR=$RUNTIME_ROOT
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
}

require_root() {
    [ "$(id -u)" = 0 ] || die 'run this command with sudo'
}

install_service() {
    require_root
    check_board
    command -v systemctl >/dev/null 2>&1 || die 'systemctl is required'
    [ -x "$REPO/target/debug/robotd" ] && [ -x "$REPO/target/debug/robotctl" ] ||
        die 'build first: cargo build --locked -p robotd -p robotctl -j 2'
    [ -r "$REPO/deploy/robotd-a733-dev.toml" ] || die 'development params file is missing'
    # Validate the account and paths before the first write.
    unit_text=$(render_unit "$@")
    unit_dir=/etc/systemd/system
    [ -d "$unit_dir" ] || die "missing systemd unit directory: $unit_dir"
    unit_tmp=$(mktemp "$unit_dir/.dreamduck-a733-dev.XXXXXX.service")
    trap 'rm -f -- "$unit_tmp"' EXIT
    trap 'exit 1' HUP INT TERM
    printf '%s\n' "$unit_text" > "$unit_tmp"
    if command -v systemd-analyze >/dev/null 2>&1; then
        systemd-analyze verify "$unit_tmp"
    fi
    chmod 0644 "$unit_tmp"
    mv -f -- "$unit_tmp" "$unit_dir/$UNIT"
    systemctl daemon-reload
    systemctl enable "$UNIT"
    systemctl restart "$UNIT"
    systemctl --no-pager status "$UNIT"
}

command=${1:-help}
[ "$#" -eq 0 ] || shift
case "$command" in
    help|-h|--help) usage ;;
    check|unit|install)
        [ "$#" -le 1 ] || die 'too many arguments'
        case "$command" in
            check) check_board "$@" ;;
            unit) render_unit "$@" ;;
            install) install_service "$@" ;;
        esac
        ;;
    start|stop|restart|disable)
        [ "$#" -eq 0 ] || die 'unexpected arguments'
        require_root
        if [ "$command" = disable ]; then
            exec systemctl disable --now "$UNIT"
        fi
        exec systemctl "$command" "$UNIT"
        ;;
    status)
        [ "$#" -eq 0 ] || die 'unexpected arguments'
        exec systemctl --no-pager status "$UNIT"
        ;;
    logs) exec journalctl --no-pager -u "$UNIT" -n 60 "$@" ;;
    health) exec "$REPO/target/debug/robotctl" --robot-socket "$SOCKET" health "$@" ;;
    *) usage >&2; die "unknown command: $command" ;;
esac
