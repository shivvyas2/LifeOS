# Calendar and health tracking — 2026-09-14

## Scope

The main Today screen is unchanged: its dot calendar, metric tiles, agenda rows and layout retain their existing implementation. Calendar event rows use a separate component so the calendar redesign does not restyle Today.

## Changes

- Calendar uses a warm neutral month card, orange selection, clear daily agenda, 44-point navigation actions, date jump, and a two-column arrangement when enough width is available.
- Today returns to the current date even after selecting another date in the current month. Multi-day and overnight events appear on every overlapping day, excluding midnight end dates and respecting daylight-saving transitions.
- Calendar connection state has an explicit action. The assistant offers a direct Schedule link, suggested prompts, and neutral rectangular surfaces. Event forms match the canvas and confirm deletion.
- Health has direct steps, sleep, weight and recovery history links, a date picker for older days, neutral reading cards and text tabs. Already-connected WHOOP accounts are not asked to reconnect merely because a selected day lacks readings.
- Sleep shows duration, a proportional stage bar with a separate readable legend, and available performance/efficiency/consistency/debt/nap rows. Missing naps are not presented as zero. Decorative fixed-target meters were removed.
- Tracking details label the actual latest reading's date, distinguish daily readings from monthly averages, expose all values including gaps, and provide connection guidance. Highest/lowest replace the assumption that longer sleep is always best. Weight changes retain neutral treatment.
- The year chart's monthly aggregate no longer replaces the latest actual daily reading in the headline. History refreshes when the local store saves.

## Verification

- Final normal iOS simulator build: **BUILD SUCCEEDED**.
- Swift package suite: **1,171 tests passed in 152 suites**. Three new tests cover multi-day events across DST, overnight events, and visible-window clipping.
- `git diff --check`: passed. Explicit diff checks confirm TodayScreen, AgendaCard, TrendStatTile, DotGrid, MonthCalendarView and the normal app entry point are unchanged.
- iPhone 17 Pro / iOS 26 preview verified with isolated in-memory sample data in a separate app bundle. Calendar, Health overview, steps history and weight history were inspected. Selected September 15, confirmed Today became enabled, and returned to September 14. Year view kept the actual latest reading while switching the chart and summary to monthly averages. Expanded All readings and confirmed a missing day says Not recorded.
- Captures: `calendar.png`, `health.png`, `steps.png`. All show labeled sample data.
- Sleep inspection exposed a truncated short-stage label. The final implementation hides labels inside the proportional bar and keeps the complete stage names and durations in the adaptive legend; the correction passed the final build.
- iPad runtime layout, large Dynamic Type, and live provider/event writes were not exercised. This change does not add manual health entry or alter sync ownership.
