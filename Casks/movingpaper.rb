cask "movingpaper" do
  version "0.038"
  sha256 "5d9e6ffb4471a8f9e529378e4ecc26ee49074af2c553fab24dc66a612e255450"

  url "https://github.com/8bittts/movingpaper/releases/download/v#{version}/MovingPaper-#{version}.dmg",
      verified: "github.com/8bittts/movingpaper/"
  name "MovingPaper"
  desc "Moving (wall)paper for your desktop"
  homepage "https://github.com/8bittts/movingpaper"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "MovingPaper.app"

  zap trash: [
    "~/Library/Application Support/MovingPaper",
    "~/Library/Application Support/com.8bittts.movingpaper",
    "~/Library/Caches/com.8bittts.movingpaper",
    "~/Library/Preferences/com.8bittts.movingpaper.plist",
    "~/Library/Saved Application State/com.8bittts.movingpaper.savedState",
  ]
end
