# TestFlight

Follow [Releasing](RELEASING.md). `scripts/prepare-testflight.sh` is a compatibility wrapper for the same portable App Store export; it does not upload or invite testers.

An older internal-only TestFlight build cannot be selected for a public App Store release. Export and upload the new public-compatible build, wait for Apple processing, and explicitly select it in the release record. Screenshot and review preparation remain separate from TestFlight distribution.
