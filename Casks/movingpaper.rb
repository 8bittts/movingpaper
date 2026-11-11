cask "movingpaper" do
  version "0.045"
  sha256 "5925ad208c15abcbc32e7912af8184a05eb4e36460c417d0618cf6651606c13e"

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
