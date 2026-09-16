# Sylvan Container Scripts

Utilities for Wayland-based development containers.

## Firefox interactive authentication

In every terminal that starts Firefox or an application which needs to open URLs in the existing Firefox profile:

```bash
source ~/sylvan.container.scripts/start-dbus-session.sh
```

Start Firefox after sourcing the script. The script creates or joins a per-user D-Bus session and configures `xdg-open` to send URLs to the running Firefox profile through D-Bus.
