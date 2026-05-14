cask "movingpaper" do
  version "0.033"
  sha256 "655142fd44f12ee5efdd80d32411b2c756d7fb6856f2c73a9081dd3f611f8920"

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
