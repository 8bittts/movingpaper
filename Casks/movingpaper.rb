cask "movingpaper" do
  version "0.034"
  sha256 "b86784eef191ee57ed2543bd26bb3a98427f3a1ff10b6f4859b14673c4cb62af"

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
