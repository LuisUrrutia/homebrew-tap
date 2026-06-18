cask "raycast@beta" do
  version "0.65.1.0,66eacbc22e"
  sha256 "2bd3aeaa5511d04de1215a274ae058016140bd0099406df97ecbf93963bc80a3"

  url "https://x-r2.raycast-releases.com/Raycast_Beta_#{version.csv.first}_#{version.csv.second}_arm64.dmg",
      verified: "x-r2.raycast-releases.com/"
  name "Raycast Beta"
  desc "Control your tools with a few keystrokes"
  homepage "https://www.raycast.com/"

  app "Raycast Beta.app"
end
