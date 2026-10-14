#!/bin/bash
# The AppImage on a clean Ubuntu, as gnustep-release-actions' appimage-test
# runs it (.github/release/appimage.conf, SMOKE_SCRIPT)
#   scripts/appimage-smoke.sh <UDCode AppImage>
# Proof UDCode starts and stays up with its interface and its grammars,
# against a virtual display. An app whose nib failed to load stays up too, as
# an icon with no window, and a grammar that failed to load leaves plain
# text; both are said on stderr, which is read back.
set -euo pipefail
image=$1
log=$(mktemp)
timeout 90 xvfb-run -a "$image" > "$log" 2>&1 &
pid=$!
sleep 25
if kill -0 $pid 2>/dev/null; then
  echo "UDCode: up after 25s"
  kill $pid 2>/dev/null || true
  wait $pid 2>/dev/null || true
else
  status=0; wait $pid || status=$?
  cat "$log"
  echo "::error::UDCode exited on its own with status $status"
  exit 1
fi
if grep -qE "Failed to load Xib|could not load nib|failed to load MainMenu" "$log"; then
  cat "$log"
  echo "::error::UDCode started without its interface"
  exit 1
fi
if grep -qE "UDLanguageModeRegistry: failed to load|Error \(objc-load\)" "$log"; then
  cat "$log"
  echo "::error::a grammar bundle did not load"
  exit 1
fi
loaded=$(grep -c "Plugin: loaded from" "$log" || true)
[ "$loaded" -ge 9 ] || { cat "$log"; echo "::error::$loaded of 9 grammar bundles loaded"; exit 1; }
echo "UDCode: its interface and $loaded grammars"
