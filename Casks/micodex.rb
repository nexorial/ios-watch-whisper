cask "micodex" do
  version "1.0-19"
  sha256 "6ddf56e367de1431022a1d657941fe08061c2f16b736e7a59fe9cc20c43d248d"

  url "https://github.com/nexorial/ios-watch-whisper/releases/download/mac-v#{version}/Micodex-#{version}-macOS-universal.zip"
  name "Micodex"
  desc "Remote receiver for Codex"
  homepage "https://kiskir.dev/projects/micodex"

  depends_on cask: "blackhole-2ch"
  depends_on macos: :ventura

  app "Micodex.app"

  caveats <<~EOS
    Install the separate Micodex Watch app from the App Store after its release.
    BlackHole 2ch is installed automatically as a dependency.
    Its installer may ask for an administrator password. Restart your Mac if requested.
    Open Micodex and follow Setup Guide for permissions, audio input, and pairing.
    Wi-Fi requires macOS 15 or later.
    Finish dictation and quit Micodex before upgrading or uninstalling.
    Pairing settings and the Mac certificate are preserved on uninstall.
  EOS
end
