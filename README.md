# Squash Coach (iPhone)

Prop the phone up, do a set of swing reps, and get the numbers. Everything runs on the phone; nothing is uploaded.

**Status: first version, not yet run on a device.** The measuring logic is tested; the camera and screens have only been compiled.

## What it does
- Tracks your body with Apple's on-device pose tracking and counts swing reps (no ball needed).
- Per rep: how long the racket arm was up before the hit, hand height and elbow angle at the top, knee bend, and whether the arm was up before the front foot landed.
- A tick when the arm comes up; says "late" when it came up late.
- Set summary and a progress chart over sessions.
- Debug mode (on by default): saves the video, the skeleton on every frame and the counted reps to *Files › On My iPhone › Squash Coach › debug*, so the tracking can be checked against a heavier offline analysis.

## What it does not do yet
- It does not see the racket. "Racket arm up" means the forearm is pointing up with the hand at chest height or higher.
- No court, no ball, no shot quality.
- The professional ranges shown are provisional: this same logic, run on skeletons from about 1,700 professional backhand drives in broadcast footage, found a rep in fewer than half of them (the camera is high and the clips are one second long). Expect the thresholds to change after the first real sets.

## Layout
- `Sources/DrillCore`: the measuring logic. Plain Swift, no Apple frameworks, tested with `swift test` (including one real professional swing as a fixture).
- `App`: camera, pose tracking, debug recorder, screens (SwiftUI).
- `project.yml`: the Xcode project is generated with [XcodeGen](https://github.com/yonaskolb/XcodeGen): `xcodegen generate`, then open `SquashCoach.xcodeproj`.
- `.github/workflows/build.yml`: tests the logic, builds the app, and (when switched on) signs it and sends it to TestFlight.

## TestFlight from GitHub
Add these repository secrets, then set the repository variable `TESTFLIGHT` to `on`:
`ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (the contents of the App Store Connect API key file), `APPLE_TEAM_ID`.
An app with bundle ID `com.agarg21.squashcoach` must exist in App Store Connect.
