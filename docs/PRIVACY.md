# Local privacy controls

The canonical [privacy policy](https://kiskir.dev/projects/micodex/privacy) describes the app, optional permissions, and Codex's separate processing.

To stop access, quit the Mac receiver and revoke Micodex's Accessibility, microphone, local-network, Bluetooth, or optional location permissions in system settings. Removing a Watch from the Mac's approved pairings revokes its remote-control access.

To remove all local Mac configuration, first remove pairings in the app and quit it. In Finder, inspect `~/Library/Application Support/WatchWhisper/tls` (the legacy name is retained for upgrades). Removing that directory deletes the local TLS identity and requires a new connection code on every Watch. Remove the `com.nexorial.watchwhisper.mac` preferences only if you intend to reset all Mac settings. In Keychain Access, Micodex pairing items use service `com.nexorial.watchwhisper.pairing`; delete only the items belonging to this app, not unrelated credentials.

Watch connection preferences are local to the app. Forgetting a Mac removes its active pairing key; Keychain items can survive uninstalling an app. Revoke access on the Mac as well when retiring a Watch. Micodex has no developer cloud account, recordings archive, or server-side pairing database.

Do not paste connection diagnostics or audio containing private information into public issues. Use GitHub private vulnerability reporting for security-sensitive reports.
