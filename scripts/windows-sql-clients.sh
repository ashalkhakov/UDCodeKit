#!/usr/bin/env bash
# The installer's PREPARE (.github/release/windows.conf): the SQL extension's
# client libraries beside UDCode.exe (scripts/sql-clients.sh windows).
exec bash "$(dirname "$0")/sql-clients.sh" windows "$@"
