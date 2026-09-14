# Glowing voice orb

Replaces the folded ribbon in `CoachVoiceOrb` with a closed, round SceneKit sphere, inspired by the supplied emerald voice-screen reference. Layered green/teal currents move across the lit surface; a translucent radial glow sits behind it. The surface is opaque, with glossy highlights and subtle microtexture.

The GPU applies small radial displacements, preserving a circular silhouette. Existing smoothed microphone/reply levels gently affect breathing, movement, emission, and halo intensity. Drag tilts the orb; tap gives it a brief impulse. Geometry is created once, without per-frame mesh allocations. Reduce Motion freezes animation; Reduce Transparency removes the halo. The blue text screen and green response-card layouts are unchanged in this follow-up.

The captured preview uses simulated amplitude and no microphone or provider calls. Physical-device performance and actual microphone capture are not verified by this fixture.

Validation: preview and normal-entry iPhone simulator builds both succeeded. Native preview inspection after correcting additive halo blending confirmed that the sphere and glow render without rectangular edges. `git diff --check` passed. No interaction/provider logic changed in this follow-up.
