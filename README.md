# LuisUrrutia Homebrew Tap

Personal Homebrew tap for casks I want to own instead of trusting a third-party tap.

## Raycast Beta

```sh
brew tap LuisUrrutia/tap
brew install --cask raycast@beta
```

The tap repository should be published as `LuisUrrutia/homebrew-tap`, which Homebrew exposes as `LuisUrrutia/tap`.

To check Raycast Beta locally:

```sh
bash scripts/check-raycast-beta.sh
```

To update the cask locally from the latest `Raycast_Beta_<version>_<build>_arm64.dmg` URL:

```sh
bash scripts/update-raycast-beta-cask.sh
```

To run the automation tests:

```sh
bash tests/check-raycast-beta.sh
```

The daily GitHub Action checks `https://www.raycast.com/new`. If a newer Beta DMG exists, it updates `Casks/raycast@beta.rb` on the `automation/raycast-beta` branch and opens or updates one PR for that latest version. If another open PR already updates the cask to that same version, the workflow exits without creating a duplicate.
