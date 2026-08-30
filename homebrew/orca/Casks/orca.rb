cask "orca" do
  arch arm: "arm64", intel: "x64"

  version "1.4.192"
  sha256 arm:   "c8d661992e7de892c7ef257c48c0e8fb3cf7441bf42240db00fb72098262433e",
         intel: "d8926ea4151a302292b255008886d2e797ea053f12ad7c601b472f3f59b0190b"

  url "https://github.com/stablyai/orca/releases/download/v#{version}/orca-macos-#{arch}.dmg",
      verified: "github.com/stablyai/orca/"
  name "Orca"
  desc "IDE for orchestrating AI coding agents across terminals and worktrees"
  homepage "https://onorca.dev/"

  livecheck do
    url :url
    strategy :github_latest
  end

  # Orca can self-update between rebuilds. nix-darwin marks this cask greedy so
  # activation still reconciles Homebrew to the reviewed release pinned here.
  auto_updates true
  conflicts_with cask: "orca@rc"
  depends_on macos: :big_sur

  app "Orca.app"
  binary "#{appdir}/Orca.app/Contents/Resources/bin/orca"

  zap trash: [
    "~/.orca",
    "~/Library/Application Support/Orca",
    "~/Library/Caches/com.stablyai.orca",
    "~/Library/Caches/com.stablyai.orca.ShipIt",
    "~/Library/HTTPStorages/com.stablyai.orca",
    "~/Library/Preferences/com.stablyai.orca.plist",
    "~/Library/Saved Application State/com.stablyai.orca.savedState",
  ]
end
