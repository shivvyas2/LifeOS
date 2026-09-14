# Dayvilo — launch draft

**Bring your day together.**

Dayvilo (day-vee-lo) is the recommended working name: warm, easy to say, and broad enough to hold health, planning, notes, money, coaching, and friends. The cat gives the product a familiar face without making the name depend on a pet or fitness metaphor.

This is a name exploration, not a production rename. Preliminary searches found less obvious overlap for Dayvilo than Morrow, Daykin, Kinday, Daynook, Dayro, or Daymori. Doveli was rejected after finding existing commercial use. These searches do not establish trademark, domain, App Store, or social-handle availability. The name remains editable in `source/project.json`.

## Brand system

| Element | Direction |
| --- | --- |
| Voice | Warm, direct, short. “Make time to move.” “A little room for you.” |
| Main line | Bring your day together. |
| Supporting line | A little company. For your everyday. |
| Core colors | Cream `#F7F4ED`, ink `#171918`, orange `#F45B32` |
| Feature colors | Peach `#FADEB9`, lavender `#E1DAF5`, sage `#CCE2D6`, blue `#D8E7FC` |
| Typography | Native system sans; clear sentence-case headlines; medium or semibold. Matches the app’s type direction. |
| Mark | Nine day dots, eight orange and one ink. A small reference to the existing Today grid. |
| Mascot | The app’s existing striped 3D cat, recorded directly from SceneKit. No newly generated mascot image is included. |
| Motion | Short eased entrances, gentle device movement, staggered cards, restrained count-ups, native cat and coach animation. |

## Films

- `exports/dayvilo-launch-9x16.mp4`: 60 seconds, 1080 × 1920, 30 fps, H.264/AAC. Vertical social draft.
- `exports/dayvilo-launch-16x9.mp4`: 60 seconds, 1920 × 1080, 30 fps, H.264/AAC. Widescreen presentation draft.
- `exports/dayvilo-teaser-9x16.mp4`: 15-second vertical cutdown.
- `exports/dayvilo-launch.srt`: editable caption track. Captions are also visible in the main films.
- `exports/dayvilo-cover-9x16.png`: vertical cover art.
- `index.html`: editable, local playback with format selection and timeline seeking.

The soundtrack is an original instrumental synthesized for this project from oscillators and deterministic noise. No third-party recordings, samples, stock music, or generated voice are used. The video remains understandable with sound off.

## Story and screen sources

The 60-second film goes from scattered pieces of a day to one coherent product, then shows Today, health, calendar and notes, money, coaching, friends and chats, an activity timer, widgets and Watch, and source connections. It ends with “Follow along for the launch.”

App screens are real native views rendered with synthetic fixtures. UI imagery is framed and cropped in the motion composition. The coach’s audio-reactive animation uses a simulated input level. Native cat footage is from `OnboardingCat.swift`; both original recordings are included. Screens can retain existing Almanac and LIFO names because this is a proposed brand direction, not a completed app rename.

The film does not claim the latest proposed glass activity redesign, a body-battery measurement, automatic Watch workout mirroring, or automatic WHOOP Bluetooth reconnect is shipped. It shows the existing activity timer. Source connection labels describe intended integrations; production Fitbit configuration, provider permissions, physical-device validation, app-group provisioning, and notification backend deployment still require release verification. No App Store availability or approved partner endorsement is claimed.

## Suggested launch caption

Your health. Your plans. Your ideas. Your people.

Meet Dayvilo — a little company for your everyday.

We’re bringing the pieces of your day together, with a familiar view of your progress, space to think, and a coach you can talk to.

Follow along as we build toward launch.

#Dayvilo #BuildInPublic #iOSApp

## Edit and render

From this directory, serve the project locally:

```sh
python3 -m http.server 8877 --bind 127.0.0.1
```

Edit `source/project.json` for the name, copy, captions, and timing. `source/film.js` controls palette, framing, and motion. `source/render.mjs` renders deterministic frames to FFmpeg. The current runtime paths are local to this workspace; override `PLAYWRIGHT_PATH` and `CHROMIUM_PATH` on another machine. FFmpeg must be available at `/usr/local/bin/ffmpeg` or that path must be updated in the script.

```sh
node source/render.mjs vertical --proof
node source/render.mjs wide --proof
node source/render.mjs vertical
node source/render.mjs wide
```

`source/make_score.py` recreates the soundtrack using Python and NumPy. Frame sequences are extracted from the native clips at 30 fps and 720 pixels wide; keep 180 frames in each sequence. Do not publish the current source-connection or device-support claims as final release claims until the relevant integrations are verified.
