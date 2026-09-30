# Badminton motion analysis

This slice adds an opt-in, account-scoped badminton review flow.

The Apple Watch samples Core Motion user acceleration, rotation rate, and device attitude while a badminton workout is running. A bounded threshold detector records candidate wrist motion bursts and a small set of relative orientation frames. It reports wrist rotation in radians per second (shown as degrees per second on screen) and gravity-removed acceleration in g. The result is called a candidate or estimate throughout the UI because it has not been trained or validated against labeled badminton footage.

The setup asks for height, weight, playing hand, and Watch wrist once per account. Height and weight personalize the account and future avatar/energy work; they are not used to claim racket-head speed or posture accuracy. The Watch must be on the playing wrist for the detector to run. WHOOP data can continue to provide recovery, heart-rate, and workout context through its authorized integration, but its public API does not provide a raw swing-motion stream.

The iPhone review stores the account-bound analysis with the synced workout. Its 3D scene shows a court, net, and an illustrative wrist replay. It explicitly marks court position, shuttle/racket speed, impact angle, and full-body posture as unmeasured. Those require an additional calibrated source, such as an iPhone camera placed beside the court or court-position hardware. A future camera mode can add Vision pose and court calibration after an on-device consent flow; it should be validated against annotated sessions before showing technique scores.

## Validation status

- `BadmintonSwingDetectorTests` covers a synthetic settled burst, gaps, and invalid orientation.
- iOS and the embedded Watch target build successfully with Xcode 26.3 / SDK 26.2.
- Hardware validation is still required for threshold tuning, false-positive rate, handedness, and the relationship between wrist rotation and actual strokes. The current detector must not be presented as a coaching or medical measurement.

References: [Apple Core Motion](https://developer.apple.com/documentation/CoreMotion), [WHOOP API](https://developer.whoop.com/api/), and [BadminSense](https://arxiv.org/abs/2603.21825) as research context rather than an integrated model.
