#!/bin/bash
# Apply patches to whatsapp-web.js node_modules at build time.
# Called from Dockerfile after npm install.
#
# Each patch function is idempotent — safe to re-run.

set -e

WWEBJS_DIR="${1:-node_modules/whatsapp-web.js}"
CLIENT_JS="$WWEBJS_DIR/src/Client.js"

echo "=== Applying whatsapp-web.js patches ==="

# Patch 001: hasSynced timing fix (GitHub #5758)
#
# Problem: The `ready` event never fires because `hasSynced` may already
# be true before the event listener is attached. This causes message
# callbacks to never be registered.
#
# Fix: Check hasSynced state immediately, then register the listener.
# Also guards the listener callback to only fire when hasSynced=true.
apply_hassynced_fix() {
  echo "[1] Client.js hasSynced timing fix (#5758)..."

  if grep -q "if (appState.hasSynced)" "$CLIENT_JS"; then
    echo "  -> Already patched, skipping"
    return 0
  fi

  # Replace the two original lines with the fixed version
  sed -i.bak '
    /window\.AuthStore\.AppState\.on.*change:state.*onAuthAppStateChangedEvent/ {
      N
      s|.*window\.AuthStore\.AppState\.on.*change:state.*{.*window\.onAuthAppStateChangedEvent(state);.*}.*\n.*window\.AuthStore\.AppState\.on.*change:hasSynced.*{.*window\.onAppStateHasSyncedEvent();.*}.*|            const appState = window.AuthStore.AppState;\
            if (appState.hasSynced) {\
                window.onAppStateHasSyncedEvent();\
            }\
            appState.on('\''change:hasSynced'\'', (_AppState, hasSynced) => {\
                if (hasSynced) {\
                    window.onAppStateHasSyncedEvent();\
                }\
            });\
            appState.on('\''change:state'\'', (_AppState, state) => { window.onAuthAppStateChangedEvent(state); });|
    }
  ' "$CLIENT_JS"

  rm -f "${CLIENT_JS}.bak"

  if grep -q "if (appState.hasSynced)" "$CLIENT_JS"; then
    echo "  -> Applied successfully"
  else
    echo "  -> WARNING: Pattern not matched — Client.js may have changed upstream"
    echo "     Check https://github.com/pedroslopez/whatsapp-web.js/issues/5758"
    exit 1
  fi
}

apply_hassynced_fix

echo "=== All patches applied ==="
