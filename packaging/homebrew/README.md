# Homebrew Cask

The live cask lives in the tap repository
[`fso13/homebrew-tap`](https://github.com/fso13/homebrew-tap), file
`Casks/radiomac.rb`.

```bash
brew tap fso13/tap
brew install --cask radiomac
# or without adding the tap first:
brew install --cask fso13/tap/radiomac
```

`packaging/homebrew/radiomac.rb.template` is the source of truth. The
`scripts/update_homebrew_cask.sh` script renders the version and SHA-256 and
pushes the result to the tap. The Release workflow calls it after publishing a
stable release, using the `HOMEBREW_TAP_TOKEN` repository secret.

Manual update:

```bash
SHA256="$(shasum -a 256 "dist/RadioMac-1.2.3.dmg" | awk '{ print $1 }')"
scripts/update_homebrew_cask.sh 1.2.3 "$SHA256" "$HOMEBREW_TAP_TOKEN"
```
