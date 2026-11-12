cask "movingpaper" do
  version "0.046"
  sha256 "337973ac4699d9ec15aaaa23f5f2b9df420bfcee6749d649cfa24dbc19604572"

  url "https://github.com/8bittts/movingpaper/releases/download/v#{version}/MovingPaper-#{version}.dmg",
      verified: "github.com/8bittts/movingpaper/"
  name "MovingPaper"
  desc "Moving (wall)paper for your desktop"
  homepage "https://github.com/8bittts/movingpaper"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on arch: :arm64
  depends_on macos: :golden_gate

  app "MovingPaper.app"

  zap trash: [
    "~/Library/Application Support/com.8bittts.movingpaper",
    "~/Library/Application Support/MovingPaper",
    "~/Library/Caches/com.8bittts.movingpaper",
    "~/Library/Preferences/com.8bittts.movingpaper.plist",
    "~/Library/Saved Application State/com.8bittts.movingpaper.savedState",
  ]
end
