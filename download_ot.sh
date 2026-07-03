#!/usr/bin/env bash
#------------------------------------------------------------------------------
# Old Testament bulk downloader -- wraps bg2md_book.rb for all 39 OT books.
#
# Made for headless machines (e.g. a Proxmox LXC container): invoking it
# detaches from the terminal and keeps running after you log out.
#
# Usage:
#   ./download_ot.sh [VERSION]           start (default NIV); returns at once
#   ./download_ot.sh --status [VERSION]  running? progress + last log lines
#   ./download_ot.sh --stop [VERSION]    stop the running download
#
# Progress log: ot-download-<VERSION>.log    PID file: ot-download-<VERSION>.pid
# Rerun after a stop/crash/reboot to resume; existing verse files are skipped.
#
# Container prerequisites: ruby, git, and `gem install colorize`.
# The 'clipboard' gem bg2md.rb requires is satisfied by a no-op shim written
# to .clipboard-shim/, so no X11/xclip is needed (and your clipboard is not
# overwritten once a second when running this on a desktop).
#
# Heads-up: the OT is ~23,000 verses; at the polite 1 req/sec this takes
# roughly 13-20 hours.
#------------------------------------------------------------------------------
set -euo pipefail
cd "$(dirname "$0")"

OT_BOOKS=(Gen Exod Lev Num Deut Josh Judg Ruth 1Sam 2Sam 1Kgs 2Kgs 1Chr 2Chr
          Ezra Neh Esth Job Ps Prov Eccl Song Isa Jer Lam Ezek Dan Hos Joel
          Amos Obad Jonah Mic Nah Hab Zeph Hag Zech Mal)
# Hidden override for smoke tests, e.g.: DOWNLOAD_BOOKS="Obad" ./download_ot.sh
if [[ -n "${DOWNLOAD_BOOKS:-}" ]]; then
  read -r -a OT_BOOKS <<< "$DOWNLOAD_BOOKS"
fi

cmd="start"
case "${1:-}" in
  --status) cmd="status"; shift ;;
  --stop)   cmd="stop"; shift ;;
esac
version="${1:-NIV}"
log="ot-download-$version.log"
pidfile="ot-download-$version.pid"

running_pid() {
  [[ -f "$pidfile" ]] || return 1
  local pid
  pid=$(cat "$pidfile")
  kill -0 "$pid" 2>/dev/null || return 1
  echo "$pid"
}

case "$cmd" in
  status)
    if pid=$(running_pid); then
      echo "Running (pid $pid)."
    else
      echo "Not running."
    fi
    echo "Verse files downloaded so far: $(find "$version" -name '*.md' 2>/dev/null | wc -l | tr -d ' ')"
    if [[ -f "$log" ]]; then
      echo "--- last log lines ($log):"
      tail -5 "$log"
    fi
    exit 0
    ;;
  stop)
    if pid=$(running_pid); then
      if command -v setsid >/dev/null 2>&1; then
        kill -TERM -- -"$pid" 2>/dev/null || kill "$pid" 2>/dev/null
      else
        pkill -TERM -P "$pid" 2>/dev/null || true
        kill "$pid" 2>/dev/null || true
      fi
      rm -f "$pidfile"
      echo "Stopped (pid $pid). Rerun ./download_ot.sh $version to resume."
    else
      echo "Not running."
    fi
    exit 0
    ;;
esac

if pid=$(running_pid); then
  echo "Already running (pid $pid). Use --status or --stop."
  exit 1
fi

# No-op stand-in for the 'clipboard' gem so bg2md.rb works headless.
mkdir -p .clipboard-shim
cat > .clipboard-shim/clipboard.rb <<'EOF'
# No-op stand-in for the 'clipboard' gem, for headless use (see download_ot.sh).
module Clipboard
  def self.copy(text)
    text
  end

  def self.paste
    ''
  end

  def self.clear; end
end
EOF

if [[ "${OT_DETACHED:-}" != "1" ]]; then
  if command -v setsid >/dev/null 2>&1; then
    OT_DETACHED=1 setsid nohup "$0" "$version" >>"$log" 2>&1 &
  else
    # macOS has no setsid; nohup alone still survives terminal close
    OT_DETACHED=1 nohup "$0" "$version" >>"$log" 2>&1 &
  fi
  sleep 1
  if pid=$(running_pid); then
    echo "Old Testament download ($version) started in background (pid $pid)."
  else
    echo "Old Testament download ($version) started in background."
  fi
  echo "It keeps running after you log out."
  echo "Progress: ./download_ot.sh --status $version    Log: $log"
  exit 0
fi

# ---- detached worker (below runs in the background session) ----
echo $$ > "$pidfile"
export RUBYLIB=".clipboard-shim${RUBYLIB:+:$RUBYLIB}"
echo "=== OT download ($version) started $(date) ==="
for b in "${OT_BOOKS[@]}"; do
  echo "=== $b ==="
  ruby bg2md_book.rb "$version" "$b" \
    || echo "!!! $b finished with failures (rerun ./download_ot.sh $version later to retry)"
done
echo "=== OT download ($version) finished $(date) ==="
rm -f "$pidfile"
