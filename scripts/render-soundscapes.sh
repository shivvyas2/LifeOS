#!/bin/sh
# Renders the listening set: each mood at 09:00 and 23:00, at rest and with a
# high heart rate, and with rain. Usage: scripts/render-soundscapes.sh <out-dir>
set -e
out="${1:?usage: scripts/render-soundscapes.sh <out-dir>}"
mkdir -p "$out"
out="$(cd "$out" && pwd)"
cd "$(dirname "$0")/../LifeOSKit"
swift build -c release --product soundscape-render
bin="$(swift build -c release --show-bin-path)/soundscape-render"
for mood in focus brainstorm relax sleep; do
  "$bin" --mood "$mood" --minutes 2 --hour 9 --out "$out/$mood-morning.wav"
  "$bin" --mood "$mood" --minutes 2 --hour 23 --out "$out/$mood-night.wav"
  "$bin" --mood "$mood" --minutes 2 --hour 14 --hr 105 --out "$out/$mood-high-hr.wav"
  "$bin" --mood "$mood" --minutes 2 --hour 14 --weather rain --out "$out/$mood-rain.wav"
done
