#!/bin/bash
# Shift (Join Shift Life) for QA on a Mac: one line in Terminal, from a bare macOS to Shift open in the browser.
#
#   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShiftHealth-AI/jsl-install/main/install.sh)"
#
# Run it again any time to update to the newest Shift (your data stays). Options (after the line, as
# `... install.sh)" -- --reset`):
#   --reset    wipe this computer's Shift data and start over with fresh sample data
#   --reseed   add the sample data again (it never duplicates)
#
# What it does, asking before anything that needs you:
#   1. Docker: installs and opens OrbStack if there's no Docker (one password prompt from macOS)
#   2. GitHub: signs you in through the browser (the GitHub CLI, kept in ~/jsl-qa/bin); your account needs access
#      to ShiftHealth-AI/jsl-web, which is private. Nothing past this step is public.
#   3. ~/jsl-qa: Shift's setup file from jsl-web, your email (you sign in with it) and, optionally, AI keys
#   4. starts Shift from the published image, adds sample families the first time, opens the browser
#
# For testing the installer itself: JSL_QA_DIR, JSL_QA_PORT (another port than 80), JSL_QA_COMPOSE (a local
# compose file instead of jsl-web's), JSL_QA_NO_PULL=1 (use the image already on this Mac), JSL_QA_NO_OPEN=1.
#
# This script holds no secrets and no Shift code. The AI keys stay in ~/jsl-qa/.env (only you can read it).
set -euo pipefail

REPO="ShiftHealth-AI/jsl-web"
DIR="${JSL_QA_DIR:-$HOME/jsl-qa}"
PORT="${JSL_QA_PORT:-80}"
HOST="app.joinshiftlife.localhost"
URL="http://$HOST$([ "$PORT" = 80 ] || echo ":$PORT")"
INBOX="http://mail.joinshiftlife.localhost$([ "$PORT" = 80 ] || echo ":$PORT")"
RESET=false; RESEED=false
for a in "$@"; do
  case "$a" in
    --reset) RESET=true ;;
    --reseed) RESEED=true ;;
    --) ;;
    *) echo "Unknown option: $a (use --reset or --reseed)"; exit 2 ;;
  esac
done

ok()   { printf '  \033[32m✓\033[0m %s\n' "$1"; }
say()  { printf '  %s\n' "$@"; }
step() { printf '\n\033[1m%s\033[0m\n' "$1"; }
stop() { printf '\n  \033[31m✗ %s\033[0m\n' "$1"; shift; for l in "$@"; do printf '    %s\n' "$l"; done; printf '\n'; exit 1; }
ask()  { local v; read -r -p "  $1" v </dev/tty; printf '%s' "$v"; }          # prompt -> answer
secret() { local v; read -r -s -p "  $1" v </dev/tty; echo >/dev/tty; printf '%s' "$v"; }
# KEY=value in ~/jsl-qa/.env: set (replacing that key only) or read
env_get() { [ -f "$DIR/.env" ] && sed -n "s/^$1=//p" "$DIR/.env" | tail -1 || true; }
env_set() {
  local tmp; tmp="$(mktemp "$DIR/.env.XXXXXX")"
  { [ -f "$DIR/.env" ] && grep -v "^$1=" "$DIR/.env" || true; printf '%s=%s\n' "$1" "$2"; } >"$tmp"
  chmod 600 "$tmp"; mv "$tmp" "$DIR/.env"
}

[ "$(uname -s)" = Darwin ] || stop "This installer is for macOS." "On Linux with Docker, ask Ward for the Linux steps."
ARCH="$(uname -m)"; [ "$ARCH" = arm64 ] || ARCH=amd64
mkdir -p "$DIR/bin"; chmod 700 "$DIR"
export PATH="$DIR/bin:$HOME/.orbstack/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

# ---------------------------------------------------------------------------------------------------------------
step "1 of 4 · Docker"
docker_up() { docker info >/dev/null 2>&1; }
if ! command -v docker >/dev/null 2>&1 && [ ! -d /Applications/OrbStack.app ] && [ ! -d /Applications/Docker.app ]; then
  say "Shift runs inside Docker. Installing OrbStack (free for personal use; about 100 MB)…"
  tmp="$(mktemp -d)"
  curl -fL --progress-bar -o "$tmp/OrbStack.dmg" "https://orbstack.dev/download/stable/latest/$ARCH" \
    || stop "Couldn't download OrbStack." "Check the internet connection, then run the same line again."
  hdiutil attach -nobrowse -quiet -mountpoint "$tmp/mnt" "$tmp/OrbStack.dmg"
  if ! ditto "$tmp/mnt/OrbStack.app" /Applications/OrbStack.app 2>/dev/null; then
    say "macOS needs your password to put OrbStack in Applications:"
    sudo ditto "$tmp/mnt/OrbStack.app" /Applications/OrbStack.app
  fi
  hdiutil detach -quiet "$tmp/mnt" || true
  rm -rf "$tmp"
  ok "OrbStack installed"
fi
if ! docker_up; then
  say "Starting Docker. If a window opens (OrbStack's first run), click through it; it may ask for your password."
  open -a OrbStack >/dev/null 2>&1 || open -a Docker >/dev/null 2>&1 || true
  for _ in $(seq 1 150); do docker_up && break; sleep 2; done
  docker_up || stop "Docker didn't start." "Open OrbStack from Applications, finish its setup, then run the same line again."
fi
docker compose version >/dev/null 2>&1 || stop "This Docker has no 'docker compose'." "Update OrbStack or Docker Desktop, then run the same line again."
ok "Docker is running"

# ---------------------------------------------------------------------------------------------------------------
step "2 of 4 · GitHub"
if ! command -v gh >/dev/null 2>&1; then
  tag="$(curl -fsSLI -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest)"; tag="${tag##*/v}"
  tmp="$(mktemp -d)"
  curl -fsSL -o "$tmp/gh.zip" "https://github.com/cli/cli/releases/download/v$tag/gh_${tag}_macOS_$ARCH.zip" \
    || stop "Couldn't download the GitHub CLI." "Check the internet connection, then run the same line again."
  unzip -q "$tmp/gh.zip" -d "$tmp" && cp "$tmp"/gh_*/bin/gh "$DIR/bin/gh" && rm -rf "$tmp"
  ok "GitHub CLI ready"
fi
if ! gh auth status -h github.com >/dev/null 2>&1; then
  say "Sign in to GitHub in the browser window that opens (copy the one-time code shown here)."
  gh auth login -h github.com -p https -w -s read:packages </dev/tty
elif ! gh auth status -h github.com 2>&1 | grep -q "read:packages"; then
  say "Shift's images need one more GitHub permission (read packages). Approve it in the browser:"
  gh auth refresh -h github.com -s read:packages </dev/tty
fi
LOGIN="$(gh api user -q .login)"
gh api "repos/$REPO" -q .full_name >/dev/null 2>&1 \
  || stop "Your GitHub account ($LOGIN) can't see $REPO yet." "Ask Ward to add $LOGIN, accept the invitation (email), then run the same line again."
gh auth token | docker login ghcr.io -u "$LOGIN" --password-stdin >/dev/null 2>&1 \
  || stop "Docker couldn't sign in to GitHub's image registry." "Run the same line again; if it repeats, send this to Ward."
ok "Signed in as $LOGIN"

# ---------------------------------------------------------------------------------------------------------------
step "3 of 4 · Setup"
if [ -n "${JSL_QA_COMPOSE:-}" ]; then cp "$JSL_QA_COMPOSE" "$DIR/compose.yml"
else
  gh api -H "Accept: application/vnd.github.raw" "repos/$REPO/contents/qa/compose.yml?ref=main" >"$DIR/compose.yml.new" \
    && mv "$DIR/compose.yml.new" "$DIR/compose.yml" || stop "Couldn't get Shift's setup file." "Run the same line again."
fi
touch "$DIR/.env"; chmod 600 "$DIR/.env"
EMAIL="$(env_get JSL_QA_EMAIL)"
while [ -z "$EMAIL" ] || [[ "$EMAIL" != *@*.* ]]; do
  EMAIL="$(ask "Your email (you sign in to Shift with it; nothing is sent to it): ")"
done
env_set JSL_QA_EMAIL "$EMAIL"
if [ -z "$(env_get ANTHROPIC_API_KEY)$(env_get OPENAI_API_KEY)$(env_get JSL_QA_AI_ASKED)" ]; then
  say "" "Optional: Shift can use AI to draft the concierge's replies. Paste a Claude or OpenAI API key to turn" \
      "it on, or press Return to skip (everything else works without it). The key stays on this Mac."
  k="$(secret "Claude API key (Return to skip): ")"; [ -n "$k" ] && env_set ANTHROPIC_API_KEY "$k"
  k="$(secret "OpenAI API key (Return to skip): ")"; [ -n "$k" ] && env_set OPENAI_API_KEY "$k"
  env_set JSL_QA_AI_ASKED 1
fi
ok "Settings in $DIR"

# ---------------------------------------------------------------------------------------------------------------
step "4 of 4 · Starting Shift (the first time downloads about 1 GB)"
dc() { docker compose -p jsl-qa --project-directory "$DIR" -f "$DIR/compose.yml" "$@"; }
if $RESET; then
  [ "$(ask "Wipe all of Shift's data on this Mac? Type yes: ")" = yes ] || stop "Nothing wiped."
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  rm -f "$DIR/.seeded"
  ok "Wiped"
fi
if ! dc ps --services --status running 2>/dev/null | grep -qx proxy \
   && lsof -nP -iTCP:"$PORT" -sTCP:LISTEN >/dev/null 2>&1; then
  stop "Another app is using port $PORT, which Shift needs." "Quit it (or restart the Mac), then run the same line again."
fi
[ -n "${JSL_QA_NO_PULL:-}" ] || JSL_QA_PORT="$PORT" dc pull --quiet || stop "Couldn't download Shift." "Run the same line again; if it repeats, send this to Ward."
JSL_QA_PORT="$PORT" dc up -d --remove-orphans --wait >"$DIR/start.log" 2>&1 \
  || { tail -5 "$DIR/start.log"; stop "Shift didn't start." "Send Ward the output of:  docker compose -p jsl-qa logs --tail 50"; }
for _ in $(seq 1 60); do curl -fsS "$URL/api/ready" >/dev/null 2>&1 && break; sleep 2; done
curl -fsS "$URL/api/ready" >/dev/null 2>&1 || stop "Shift started but isn't answering at $URL yet." "Wait a minute and open it in the browser."
ok "Shift is running"

if $RESEED || [ ! -f "$DIR/.seeded" ]; then
  say "Adding sample families, places, events and calendars (a minute)…"
  cli() { dc run --rm --no-deps -e DATABASE_URL=postgres://jsl_migrator:jsl_migrator@db:5432/jsl web python -m jsl.cli "$@" >/dev/null; }
  cli seed --admin "$EMAIL" && cli seed-demo && cli seed-qa --lead "$EMAIL" && cli seed-calendar \
    || stop "The sample data didn't load." "Run the same line again with --reseed."
  touch "$DIR/.seeded"
  ok "Sample data added"
fi

cat >"$DIR/README.txt" <<TXT
Shift for QA on this Mac

  Open Shift      $URL
  Sign-in codes   $INBOX   (every email Shift sends lands here; nothing leaves this Mac)

  You             $EMAIL: admin, and the concierge lead of the eight sample households
  Parents         jessie@example.com, brian@example.com (the Meewes family)
                  h01-01@chelan.com and the like (see Admin > Households)
  Concierge       maya@example.com
  Tip             use a private window to be a parent and the concierge at once

  Update          run the install line again (your data stays)
  Start over      run it again with:  -- --reset
  Stop            docker compose -p jsl-qa stop        (or quit OrbStack)
TXT
printf '\n'; sed 's/^/  /' "$DIR/README.txt"; printf '\n  (This list is saved in %s/README.txt)\n\n' "$DIR"
[ -n "${JSL_QA_NO_OPEN:-}" ] || open "$URL"
