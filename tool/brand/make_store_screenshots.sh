#!/usr/bin/env bash
# Renders the 8 captioned Play Store phone screenshots (1080x1920) from the raw
# captures in docs/store/screenshots/ into docs/store/play/screenshots/.
set -euo pipefail
cd "$(dirname "$0")/../.."
chrome="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
raw="$PWD/docs/store/screenshots"
out="docs/store/play/screenshots"
mkdir -p "$out"

enc() { python3 -c 'import sys, urllib.parse; print(urllib.parse.quote(sys.argv[1]))' "$1"; }

render() { # <output name> <raw capture> <headline> <subline> [status bar px to crop]
  local url="file://$PWD/tool/brand/screenshot.html?shot=$(enc "file://$raw/$2")&t=$(enc "$3")&s=$(enc "$4")&crop=${5:-0}"
  "$chrome" --headless --disable-gpu --hide-scrollbars --force-device-scale-factor=1 \
    --window-size=1080,1920 --virtual-time-budget=2000 --allow-file-access-from-files \
    --screenshot="$PWD/$out/$1" "$url" 2>/dev/null
}

rm -f "$out"/0*.png
render 01-pass-the-slips.png      03-your-turn.png                 "Pass the slips"              "One slip at a time, around the circle" 120
render 02-four-of-a-kind.png      04-winner-and-character.png      "Four of a kind wins!"        "Then everyone picks a secret character" 120
render 03-your-movies.png         13-movie-list.png                "English or Telugu movies"    "Pick the films your group knows" 120
render 04-find-the-queen.png      09-king-queen-find-the-queen.png "King, find the Queen!"       "Plus a whole King & Queen game mode"
render 05-play-with-friends.png   01-lobby.png                     "Play with 3–10 friends"      "Share a room code or a WhatsApp invite" 120
render 06-secret-role.png         08-king-queen-secret-role.png    "For your eyes only"          "Nobody can peek, not even the host"
render 07-round-results.png       05-round-results.png             "Every slip revealed"         "Scores add up after every round" 120
render 08-crown-king-queen.png    06-king-and-queen.png            "Crown the King and Queen"    "The top two scorers win the crowns" 120
ls -1 "$out"
