cask "open-focus-island" do
  version "0.1.0"
  sha256 :no_check # Set by the release workflow.

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
