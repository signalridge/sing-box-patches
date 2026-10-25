# sing-box-patches

[sing-box](https://github.com/SagerNet/sing-box) built with local patches to its
Go dependencies, as a Nix flake and as release archives.

| | |
|---|---|
| sing-box | `1.14.4` |
| sing-openconnect | `cbd68c45de58` (pinned by sing-box's `go.mod`) |
| Build tags | upstream's, minus `with_naive_outbound` (needs cgo) |

## Patches

| Patch | Purpose | Upstream |
|---|---|---|
| `0001-f5-saml-browser-challenge` | F5 BIG-IP SAML login as a browser challenge | [#5](https://github.com/SagerNet/sing-openconnect/pull/5) |
| `0002-f5-options-parsing` | F5 VPN options as real gateways send them | [#4](https://github.com/SagerNet/sing-openconnect/pull/4) |

Patches live in `patches/<module path>/` and apply to the vendored module.
Write one in a clone of the module at the pinned commit, then
`git format-patch -1 -o patches/<module path>/`. A patch may add test files
but not change existing ones.

## Use

```sh
nix profile install github:signalridge/sing-box-patches#sing-box
```

Also available as `nur.repos.signalridge.sing-box`, or as archives from the
[releases](https://github.com/signalridge/sing-box-patches/releases).

For an F5 gateway with SAML login (`openconnect` endpoint with
`"flavor": "f5"`, plus an `api` service), run

```sh
sing-box api --url <api address> openconnect auth --endpoint <tag>
```

log in through the printed URL in a browser, and paste the gateway's
`MRHSession` and `F5_ST` cookies. In the browser console:

```js
document.cookie.split('; ').filter(c => /^(MRHSession|F5_ST)=/.test(c)).join('\n')
```

## Build

```sh
nix build .#sing-box              # this system
nix build .#sing-box-linux-arm64  # any release target
```

## Release

```sh
git tag -a v1.14.4-p2 -m v1.14.4-p2 && git push origin v1.14.4-p2
```

Builds every target, publishes the release and syncs the package to
[nur-packages](https://github.com/signalridge/nur-packages).

## Updates

A weekly workflow opens a pull request when sing-box has a new stable release,
and flags it when a patch no longer applies. Run it locally with
`scripts/update-sing-box.sh`.

## License

GPL-3.0-or-later, as sing-box and sing-openconnect.
