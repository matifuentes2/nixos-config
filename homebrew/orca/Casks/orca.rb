cask "orca" do
  arch arm: "arm64", intel: "x64"

  version "1.4.196"
  sha256 arm:   "0890987a40d7307e86efba5d3cb853ad77844962e6cef65f93e8b604bb7d2e9f",
         intel: "a48b6d2c7bc19deeb1c55ce78b6d15e40b27498566f7cadbae2106ad6eac263c"

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
