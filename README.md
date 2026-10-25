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
| `github.com/sagernet/sing-openconnect` | `0001-f5-saml-browser-challenge.patch` | F5 BIG-IP SAML login: when the gateway hands the logon to a SAML IdP, raise a browser challenge for the `MRHSession` (and `F5_ST`) cookies instead of failing with "unexpected first F5 HTML form ID" |
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
nix build .#sing-box     # result/bin/sing-box
nix flake check
```

## Release

Push a tag `v<sing-box version>-p<n>` (e.g. `v1.14.4-p1`) on a commit of
`main` whose CI passed:

```sh
git tag -a v1.14.4-p1 -m v1.14.4-p1 && git push origin v1.14.4-p1
```

The release workflow checks that the tag is well formed, names the
`version` in `package.nix` and points at `main`, then runs `nix flake check`
and `nix build .#sing-box` on macOS arm64 (without a shared cache), checks the
binary's version, and publishes a GitHub release with
`sing-box-<version>-darwin-arm64.tar.gz` (same layout as upstream's) and its
`.sha256`. To rerun it for an existing tag, use the workflow's manual trigger
with that tag.

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
