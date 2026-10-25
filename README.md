# sing-box-patches

[sing-box](https://github.com/SagerNet/sing-box) built from source with local
patches to its Go dependencies, as a Nix flake and as release archives laid out
like upstream's, for all of upstream's pure-Go platforms.

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
| `github.com/sagernet/sing-openconnect` | `0001-f5-saml-browser-challenge.patch` | F5 BIG-IP SAML login: when the gateway hands the logon to a SAML IdP, raise a browser challenge for the `MRHSession` and `F5_ST` cookies instead of failing with "unexpected first F5 HTML form ID". The challenge has no final URL (the landing page depends on the webtop): cookie challenges may now omit it and then complete once every requested cookie is set |
| `github.com/sagernet/sing-openconnect` | `0002-f5-options-parsing.patch` | F5 VPN options as real gateways send them: space-separated DNS/WINS/DNSSuffix lists, routes with dotted IPv4 or IPv6 netmasks, and optional values it cannot parse dropped with a warning (as openconnect does) instead of failing the connection |

Write a patch in a clone of the module at the pinned commit (`cbd68c45de58`),
run its tests there, commit, then export it with
`git format-patch -1 -o <this repo>/patches/github.com/sagernet/sing-openconnect/`.

### F5 SAML login

With an `openconnect` endpoint (`"flavor": "f5"`) and an `api` service, a
gateway that hands the logon to a SAML IdP leaves the endpoint in
`auth-pending`. Answer it with

```sh
sing-box api --url <api address> openconnect auth --endpoint <tag>
```

then log in through the printed gateway URL in any browser and paste the
gateway's `MRHSession` and `F5_ST` cookies when asked (DevTools > Application >
Cookies, or in the console:
`document.cookie.split('; ').filter(c => /^(MRHSession|F5_ST)=/.test(c)).join('\n')`).

## Build

```sh
nix build .#sing-box                 # this system: result/bin/sing-box
nix build .#sing-box-linux-arm64     # any release target, from any system
nix eval --json .#lib.releaseTargets # all release targets
nix flake check
```

Release targets are upstream's archives that build without cgo: darwin
(amd64, arm64), linux (amd64, arm64, 386, 386-softfloat, armv5/6/7,
mips-softfloat, mipsle, mipsle-softfloat, mips64-softfloat, mips64le,
mips64le-softfloat, ppc64le, riscv64, loong64, s390x), windows (amd64, 386,
arm64) and android-arm64, all with `CGO_ENABLED=0` and the same tags and
ldflags. Upstream builds android (and darwin) with cgo; android arm, 386 and
amd64 cannot link without it and are not built. Upstream's naive (cgo +
Cronet) variants, legacy Windows 7 / macOS 10.13 builds and
deb/rpm/OpenWrt/apk packages are not built either. Upstream's windows-arm64 build
backports a Go fix for CPU feature detection (crypto speed only); this one
uses nixpkgs' Go as is.

## Release

Push a tag `v<sing-box version>-p<n>` (e.g. `v1.14.4-p1`) on a commit of
`main` whose CI passed:

```sh
git tag -a v1.14.4-p1 -m v1.14.4-p1 && git push origin v1.14.4-p1
```

The release workflow checks that the tag is well formed, names the
`version` in `package.nix` and points at `main`, then builds every release
target with `nix build .#sing-box-<target>` (darwin on macOS, the rest on
Linux, without a shared cache). It checks each binary's embedded Go build
settings (GOOS, GOARCH and GOARM/GO386/GOMIPS), version and build tags, runs
the ones native to the runner, and publishes a GitHub release with
`sing-box-<version>-<target>.tar.gz` (`.zip` for windows, same layout as
upstream's), a `.sha256` for each and `SHA256SUMS`. To rerun it for an
existing tag, use the workflow's manual trigger with that tag.

Its last job copies `package.nix` and `patches/` to
[signalridge/nur-packages](https://github.com/signalridge/nur-packages) as
`pkgs/sing-box` (NUR forbids import-from-derivation, so it cannot import them
from here), checks the result the way NUR evaluates it and builds it with that
repository's nixpkgs, then pushes it with the `GH_PAT` secret. If only that
job fails, re-run it from the run's page ("Re-run failed jobs"); the release
itself is already published.

## Use

```sh
nix profile install github:signalridge/sing-box-patches#sing-box
```

or, through NUR, `nur.repos.signalridge.sing-box` (its overlay replaces
nixpkgs' `sing-box`), or the release archives.

## Automatic updates

Every Monday, `.github/workflows/update-sing-box.yml` runs
`scripts/update-sing-box.sh`. When sing-box has a newer stable release
(prereleases are skipped), the script moves `version`, the source `hash` and
`vendorHash` to it, builds every release target with the patches, and opens a
pull request on `update/sing-box`. The pull request's description says whether
the `sing-openconnect` pin moved, whether every patch still applies (or is
already upstream) and whether upstream's build tags or ldflags changed; its
title says "needs attention" when one of them needs a person. The pull request
is opened with the `GH_PAT` secret so that CI runs on it. Merging and tagging
stay manual. Dependabot keeps the pinned actions current.

Run the script locally the same way (needs `nix`, an authenticated `gh` and
`jq`): `scripts/update-sing-box.sh`.

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
