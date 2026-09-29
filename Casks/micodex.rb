cask "micodex" do
  version "1.0,16"
  sha256 "15d76b5e5e675a2e48f18ebd6cf1444f21c59cc36c1ecbcd468c9d68bdb13520"

  url "https://github.com/nexorial/ios-watch-whisper/releases/download/mac-v#{version.csv.first}-#{version.csv.second}/Micodex-#{version.csv.first}-#{version.csv.second}-macOS-universal.zip"
  name "Micodex"
  desc "Remote receiver for Codex"
  homepage "https://kiskir.dev/projects/micodex"

  depends_on macos: :ventura

  app "Micodex.app"

  caveats <<~EOS
    Install the separate Micodex Watch app from the App Store after its release.
    Wi-Fi requires macOS 15 or later. Watch dictation also needs BlackHole 2ch:
      brew install --cask blackhole-2ch
    Finish dictation and quit Micodex before upgrading or uninstalling.
    Pairing settings and the Mac certificate are preserved on uninstall.
  EOS
end
