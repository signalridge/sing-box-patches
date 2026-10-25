# sing-box-patches

[sing-box](https://github.com/SagerNet/sing-box) built from source with local
patches to its Go dependencies, as a Nix flake and as release tarballs laid out
like upstream's.

| | |
|---|---|
| sing-box | `1.14.4` (`package.nix`) |
| sing-openconnect | `v0.1.1-0.20260929151225-cbd68c45de58` (pinned by sing-box's `go.mod`) |
| Build tags | upstream `release/DEFAULT_BUILD_TAGS` minus `with_naive_outbound` (needs cgo + Cronet) |

## Patches

`patches/<module path>/NNNN-<topic>.patch` is applied with `-p1` to
`vendor/<module path>` before the build. A patch may add test files but not modify existing ones (vendoring drops them). The vendored module set stays
upstream's, so `vendorHash` only changes when sing-box does.

| Module | Patch | Purpose |
|---|---|---|
| `github.com/sagernet/sing-openconnect` | (none yet) | F5 BIG-IP SAML login as a browser challenge |

Write a patch in a clone of the module at the pinned commit (`cbd68c45de58`),
run its tests there, commit, then export it with
`git format-patch -1 -o <this repo>/patches/github.com/sagernet/sing-openconnect/`.

## Build

```sh
nix build .#sing-box     # result/bin/sing-box
nix flake check
```

## Release

Push a tag `v<sing-box version>-p<n>` (e.g. `v1.14.4-p1`). The release
workflow builds on macOS arm64 and attaches
`sing-box-<version>-darwin-arm64.tar.gz` (same layout as upstream's) and its
`.sha256`.

## Upgrading sing-box

1. Set `version` and the source `hash` in `package.nix`
   (`nix flake prefetch github:SagerNet/sing-box/v<version>`).
2. Set `vendorHash = lib.fakeHash;`, run `nix build`, copy the `got:` hash.
3. Check the pinned `sing-openconnect` commit in the new `go.mod`; rebase the
   patches onto it if it moved.
4. Compare the build tags with the new `release/DEFAULT_BUILD_TAGS` and
   `release/LDFLAGS`.

## License

GPL-3.0-or-later, as sing-box and sing-openconnect.
