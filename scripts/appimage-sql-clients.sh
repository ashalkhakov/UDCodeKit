#!/usr/bin/env bash
# The AppImage's PREPARE (.github/release/appimage.conf): the SQL extension's
# client libraries into the AppDir (scripts/sql-clients.sh appimage).
exec bash "$(dirname "$0")/sql-clients.sh" appimage "$@"
