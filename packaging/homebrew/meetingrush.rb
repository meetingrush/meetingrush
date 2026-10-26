# Template for the meetingrush/homebrew-tap repository. Set the release URL and sha256 for each version.
class Meetingrush < Formula
  desc "Full-screen meeting alerts with one-click join for macOS"
  homepage "https://github.com/meetingrush/meetingrush"
  url "https://github.com/meetingrush/meetingrush/archive/refs/tags/v0.1.0.tar.gz"
  sha256 "REPLACE_WITH_SHA256"
  license "GPL-3.0-or-later"

  depends_on macos: :sonoma

  def install
    system "make", "app", "SWIFT_BUILD_FLAGS=--disable-sandbox"
    prefix.install "dist/MeetingRush.app"
  end

  def caveats
    <<~EOS
      Launch it with:
        open #{opt_prefix}/MeetingRush.app

      To find it in Spotlight and Launchpad:
        ln -sf #{opt_prefix}/MeetingRush.app ~/Applications/MeetingRush.app

      macOS asks again for calendar access after each upgrade, because the build is signed ad-hoc.
    EOS
  end

  test do
    assert_path_exists prefix/"MeetingRush.app/Contents/MacOS/MeetingRush"
  end
end
