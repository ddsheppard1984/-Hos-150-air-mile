# HOS150 paired server + SideStore release policy

Every user-facing HOS150 server/web deployment requires a matching **HOS150 iPhone IPA / SideStore source** release and verification. Do **not** silently mark the whole release complete if SideStore publishing is pending or failed.

1. Back up and deploy the web/API safely; verify user records preserved.
2. On `feature/hos150-native-ios-sidestore-20261031`, bump `ios/project.yml` `MARKETING_VERSION` monotonically; update `ios/release-info.json` with paired web build identifier, script hotfix/cache marker and user-facing release notes.
3. Commit both changed files together on that branch. Pushing an `ios/**` file automatically triggers `.github/workflows/hos150-ios-sidestore.yml` on GitHub macOS and publishes an unsigned IPA to the `hos150-ios-updates` branch.
4. Verify GitHub Actions conclusion **success** and `ota/source.json` reflects the new `version`, newer `buildVersion`, correct `com.houseofsqueak.hos150` bundle ID, and a valid `HOS150.ipa`.
5. Report both web deploy and SideStore feed status separately. Never imply the iPhone has installed the update: the user still taps Update in SideStore (with required VPN/refresh).
6. Retain rollback image, backups and previous release info. Never repurpose the SpiritLab/ghostapp iOS workflow.

SideStore feed: https://raw.githubusercontent.com/ddsheppard1984/-Hos-150-air-mile/hos150-ios-updates/ota/source.json

Note: a Squeak local guarded deploy currently does **not** authenticate to GitHub automatically. If no credentialed trigger is available, publish through the connected GitHub release workflow in the same work session before claiming the release fully complete.
