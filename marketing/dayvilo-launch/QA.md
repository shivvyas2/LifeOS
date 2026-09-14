# Launch film QA

The films use real app screen captures with synthetic sample data, native SceneKit mascot motion, and a native coach recording with simulated audio input. The brand name is a working proposal. No production app strings were renamed and the normal app entry point was restored after capture. The normal iOS/Watch/extensions build passed with preview flags disabled.

Reviewed portrait and landscape proof frames across all scenes for readable headings, captions, color consistency, and device framing. Replaced initial screenshots taken before simulator drawing completed. Replaced the notes editor shot with the notes library after observing horizontal overflow in the standalone editor fixture; this finding still needs a separate app layout investigation. Corrected the calendar crop and the Lock Screen close-up, and matched the coach frame fill to the blue scene.

The current activity timer is shown, not the proposed glass redesign or unimplemented automatic sensor reconnection. The Lock Screen close-up shows the system’s dimmed timer state, which redacts seconds. Current app names (Almanac/LIFO) can appear within native screenshots; the film’s proposed brand is Dayvilo.

Automated media verification is recorded in `exports/verification.json`: exact dimensions, duration, frame count, H.264/AAC, stereo audio, and a complete error-free decode for each export. This validates the media files, not production integration or physical-device behavior.
