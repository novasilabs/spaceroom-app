cask "spaceroom" do
  version "0.10.2"
  sha256 "a2d1916a9209287e9f2f292988cc820f83b59bda6760b189083c009d504573b6"

  url "https://github.com/novasilabs/spaceroom-app/releases/download/v#{version}/Spaceroom-#{version}.dmg"
  name "Spaceroom"
  desc "Free, open-source cleaner where everything it removes can be restored"
  homepage "https://github.com/novasilabs/spaceroom-app"

  livecheck do
    url :url
    strategy :github_releases
  end

  depends_on macos: :sonoma

  app "Spaceroom.app"

  # Spaceroom isn't notarized. Homebrew flags what it downloads as coming from the internet,
  # which would make macOS block the first launch; the download's checksum is verified above,
  # so the flag is removed here.
  postflight_steps do
    run "/usr/bin/xattr", args:           ["-dr", "com.apple.quarantine", "{{appdir}}/Spaceroom.app"],
                          writable_paths: ["Spaceroom.app"],
                          writable_base:  :appdir
  end

  zap trash: [
    "~/Library/Application Support/Spaceroom",
    "~/Library/Caches/com.novasilabs.spaceroom",
    "~/Library/HTTPStorages/com.novasilabs.spaceroom",
    "~/Library/Preferences/com.novasilabs.spaceroom.plist",
    "~/Library/Saved Application State/com.novasilabs.spaceroom.savedState",
  ]
end
