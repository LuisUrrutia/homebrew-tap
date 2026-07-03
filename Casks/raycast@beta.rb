cask "raycast@beta" do
  version "0.67.1.0,ee5f4a9914"
  sha256 "4c6de70eaec3a0248038df2cec15833ee06affb4f78785eb89f4161a31750302"

  url "https://x-r2.raycast-releases.com/Raycast_Beta_#{version.csv.first}_#{version.csv.second}_arm64.dmg",
      verified: "x-r2.raycast-releases.com/"
  name "Raycast Beta"
  desc "Control your tools with a few keystrokes"
  homepage "https://www.raycast.com/"

  livecheck do
    url "https://www.raycast.com/new"
    regex(/Raycast[._-]Beta[._-]v?(\d+(?:\.\d+)+)[._-]([0-9a-f]+)[._-]arm64\.dmg/i)
    strategy :page_match do |page, regex|
      page.scan(regex).map { |match| "#{match[0]},#{match[1]}" }
    end
  end

  auto_updates true
  depends_on macos: :tahoe
  depends_on arch: :arm64

  app "Raycast Beta.app"

  uninstall quit:       "com.raycast-x.macos",
            login_item: "Raycast Beta"

  zap trash: [
    "~/Library/Application Scripts/com.raycast-x.macos",
    "~/Library/Application Support/com.raycast-x.macos",
    "~/Library/Caches/com.raycast-x.macos",
    "~/Library/Caches/SentryCrash/Raycast Beta",
    "~/Library/Cookies/com.raycast-x.macos.binarycookies",
    "~/Library/HTTPStorages/com.raycast-x.macos",
    "~/Library/Preferences/com.raycast-x.macos.plist",
    "~/Library/WebKit/com.raycast-x.macos",
  ]
end
