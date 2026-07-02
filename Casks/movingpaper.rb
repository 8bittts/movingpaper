cask "movingpaper" do
  version "0.040"
  sha256 "0344cd751b2e6339eb6045641f3c910cad36b421ff8b1c310a95df0c62b4dc2c"

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
