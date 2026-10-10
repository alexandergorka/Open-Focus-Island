cask "open-focus-island" do
  version "0.1.0"
  sha256 "5ff7029a3a2239bce6944b789ac9b94f3f0963afe65b1c4c536ee4861bb33c7c"

  url "https://github.com/alexandergorka/Open-Focus-Island/releases/download/v#{version}/Open-Focus-Island-#{version}.zip"
  name "Open Focus Island"
  desc "Focus timer that lives in the notch"
  homepage "https://github.com/alexandergorka/Open-Focus-Island"

  depends_on macos: ">= :sonoma"

  app "Open Focus Island.app"

  zap trash: "~/Library/Preferences/org.openfocusisland.app.plist"

  caveats <<~EOS
    Open Focus Island is not notarized by Apple yet. macOS blocks the first launch:
    open System Settings > Privacy & Security and click "Open Anyway".
  EOS
end
