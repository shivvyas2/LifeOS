# Warm ribbon coach

Replaced the spherical voice presence with a parametric folded 3D ribbon: a thin, closed cross-section with three half twists, overlapping folds, and an open center. The mesh is built once; GPU deformation updates both positions and normals from the same surface function. Soft amber-to-coral shading, fine surface lines, HDR highlights, and warm lighting replace the cyan bubble.

Voice retains the existing frame-rate-independent AudioEnvelope. Listening uses microphone levels; spoken replies use playback levels; thinking changes the drift cadence. Touch tilt and tap impulse are preserved. Nonfinite input is rejected. Scene deactivation stops the display link. Reduce Motion fixes the shape and disables touch motion; Reduce Transparency makes the material fully opaque.

The coach backdrop now fades from muted amber into warm charcoal. Existing system typography, orange controls, response parsing, and comparison-table behavior are preserved. Response cells use cream and pale gold. The Today dot screen is unchanged.

Verification:
- Native iPhone simulator capture with synthetic voice levels: `iphone.png` and `voice-motion.mp4`.
- Existing AudioEnvelope tests: 3 passed (attack/release, frame-rate consistency, invalid-input bounds).
- Preview build and normal app build: both passed. Logs: `/private/tmp/coach-ribbon-build.log` and `/private/tmp/coach-ribbon-normal-build.log`.
- Direct tap/drag and system accessibility-toggle checks could not be performed because the host Mac was locked. These paths are implemented but are not claimed as manually verified. Physical-device performance is not measured in this pass.

Reference: user-supplied `7041311bf0811317fbd38da4d740aed0.jpg`. The implementation uses native SceneKit geometry and materials, not a raster animation. Geometry shader behavior follows [Apple’s shader-modifier documentation](https://developer.apple.com/documentation/scenekit/scnshadermodifierentrypoint/geometry).
