# Security

For vulnerabilities, use [GitHub private vulnerability reporting](https://github.com/nexorial/ios-watch-whisper/security/advisories/new). Do not include secrets, pairing keys, recordings, or personal device information in public issues.

Micodex is a local remote-control tool. Only pair devices you own or are authorized to control. Keep the receiver on a trusted network and do not expose TCP port 8766 to the internet.

The Watch trusts the complete SHA-256 certificate fingerprint copied directly from the Mac, then performs system X.509 checks. A network-supplied certificate or six-digit pairing code alone never establishes server trust. The Mac also requires approval of a time-limited pairing request. Commands, acknowledgements, and audio frames use authenticated sessions and replay checks; pairing keys stay in Keychain. The Mac TLS identity stays in its permission-restricted Application Support directory.

Removing a pairing on the Mac revokes its access. A changed certificate requires a new trusted connection code. TLS certificates currently expire after one year; renewal and re-pairing are manual. Do not disable verification to work around expiry.

Accessibility access lets the Mac receiver control the selected app. Micodex limits actions to supported targets, but target UI changes or interruptions can prevent a stop request from completing. Always check the target app if a stop error appears. No security audit or absolute interruption guarantee is claimed.
