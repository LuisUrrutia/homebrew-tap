# LuisUrrutia Homebrew Tap

Personal Homebrew tap for casks I want to own instead of trusting a third-party tap.

## Raycast Beta

```sh
brew tap LuisUrrutia/tap
brew install --cask raycast@beta
```

The tap repository should be published as `LuisUrrutia/homebrew-tap`, which Homebrew exposes as `LuisUrrutia/tap`.

To update Raycast Beta, replace the `version` tuple and `sha256` in `Casks/raycast@beta.rb` from the latest `Raycast_Beta_<version>_<build>_arm64.dmg` URL.
