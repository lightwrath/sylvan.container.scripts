#!/usr/bin/env bash
# Source this file into the current shell; do not execute it:
#   source ~/sylvan.container.scripts/start-dbus-session.sh
#
# The selected D-Bus session is recorded in a user-only file so terminals in the
# same container can join it. Firefox and applications that need to open URLs in
# that Firefox must use the same session.

start_dbus_session() {
    local state_dir="$HOME/.cache"
    local state_file="$state_dir/dbus-session-${UID}.env"
    local wayland_socket=""

    # Preserve the Wayland socket before replacing an invalid XDG runtime dir.
    if [[ -n "${WAYLAND_DISPLAY:-}" && "${WAYLAND_DISPLAY#*/}" == "$WAYLAND_DISPLAY" ]]; then
        wayland_socket="${XDG_RUNTIME_DIR:-}/$WAYLAND_DISPLAY"
    else
        wayland_socket="${WAYLAND_DISPLAY:-}"
    fi

    # D-Bus requires a private runtime directory owned by the current user.
    if [[ -z "${XDG_RUNTIME_DIR:-}" || ! -d "$XDG_RUNTIME_DIR" || ! -O "$XDG_RUNTIME_DIR" ]]; then
        export XDG_RUNTIME_DIR="$state_dir/xdg-runtime-${UID}"
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 700 "$XDG_RUNTIME_DIR"
    fi

    # An absolute socket path remains valid after XDG_RUNTIME_DIR changes.
    if [[ -n "$wayland_socket" && -S "$wayland_socket" ]]; then
        export WAYLAND_DISPLAY="$wayland_socket"
    fi

    if ! command -v dbus-launch >/dev/null 2>&1 || ! command -v dbus-send >/dev/null 2>&1; then
        echo "dbus-launch and dbus-send are required; install the container's D-Bus client package." >&2
        return 1
    fi

    dbus_session_is_alive() {
        dbus-send --session --dest=org.freedesktop.DBus --type=method_call \
            --print-reply / org.freedesktop.DBus.ListNames >/dev/null 2>&1
    }

    save_dbus_session() {
        mkdir -p "$state_dir"
        chmod 700 "$state_dir"
        umask 077
        {
            printf 'DBUS_SESSION_BUS_ADDRESS=%q\n' "$DBUS_SESSION_BUS_ADDRESS"
            printf 'DBUS_SESSION_BUS_PID=%q\n' "${DBUS_SESSION_BUS_PID:-}"
        # >| intentionally replaces our own state file when the shell enables noclobber.
        } >|"$state_file"
        chmod 600 "$state_file"
    }

    # Prefer a live bus already assigned to this shell.
    if [[ -n "${DBUS_SESSION_BUS_ADDRESS:-}" ]] && dbus_session_is_alive; then
        save_dbus_session
        echo "Using current D-Bus session: $DBUS_SESSION_BUS_ADDRESS"
        unset -f dbus_session_is_alive save_dbus_session
        return 0
    fi

    # Otherwise, securely join the live session saved by another terminal.
    if [[ -f "$state_file" && ! -L "$state_file" && -O "$state_file" ]]; then
        # The file is written by save_dbus_session with shell-escaped values and
        # mode 0600. Do not use a state file from another user.
        source "$state_file"
        export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
        if dbus_session_is_alive; then
            echo "Joined saved D-Bus session: $DBUS_SESSION_BUS_ADDRESS"
            unset -f dbus_session_is_alive save_dbus_session
            return 0
        fi
        rm -f "$state_file"
        unset DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
    fi

    eval "$(dbus-launch --sh-syntax)"
    export DBUS_SESSION_BUS_ADDRESS DBUS_SESSION_BUS_PID
    save_dbus_session
    echo "Started D-Bus session: $DBUS_SESSION_BUS_ADDRESS"
    unset -f dbus_session_is_alive save_dbus_session
}

# Firefox uses D-Bus, rather than an unavailable X11 remote channel, to forward
# URL-opening requests to the existing Wayland browser instance.
export MOZ_DBUS_REMOTE=1

# xdg-open will invoke the bridge stored alongside this script instead of the
# Firefox CLI, whose --new-tab remote mechanism is not usable in this
# Wayland-only container.
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
export BROWSER="$script_dir/firefox-dbus-open"
unset script_dir

start_dbus_session
unset -f start_dbus_session
