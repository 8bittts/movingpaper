cask "movingpaper" do
  version "0.036"
  sha256 "c231b305da0afb8c9c04f6133e7376eeb1b189fb60016cca97b504ada59ef7b5"

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
