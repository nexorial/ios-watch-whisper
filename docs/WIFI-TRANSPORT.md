# Wi-Fi connection

Use the [README setup steps](../README.md#quick-start). Wi-Fi requires macOS 15+, an awake Mac receiver, and a reachable IPv4 local network. The service listens on TCP 8766.

First installation uses **Copy Connection Code** on the Mac and **Trust This Mac & Connect** on the Watch. The code carries the full certificate fingerprint; obtain it directly from your own Mac. A six-digit pairing comparison is a second approval step and cannot substitute for this full pin.

The developer-only `scripts/prepare-wifi.sh` creates a local xcconfig containing the Mac address and public fingerprint. `install-watch.sh` uses it for direct device installation. `prepare-app-store.sh` explicitly blanks both values and `verify-export.py` rejects public packages containing developer configuration.

For a changed DHCP address, edit only the Watch's **Mac IP Address**. For a different Mac or renewed certificate, choose **More Options → Set Up Another Mac** and copy its code. Existing bundle IDs, Keychain accounts, and TLS identity paths retain the legacy `watchwhisper` names for compatibility.

Run `./scripts/test-wifi-security.sh` to exercise the real local HTTPS listener, pairing approval, ticket binding, session authentication, replay rejection, wrong-pin rejection, revocation, audio finalization, duplicate receivers, and port-conflict recovery. The test uses isolated credentials and a demo controller. It does not establish real Watch audio or Codex UI behavior.
