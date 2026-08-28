cask "orca" do
  arch arm: "arm64", intel: "x64"

  version "1.4.190"
  sha256 arm:   "a88a74363848d3a1dcb619b82e16ce48ea565777f74e8c917f0d2d50711c373e",
         intel: "e8ff1289961b8474afb74c81aab73911137dc8838d6e4f47452538960fe3be15"

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
