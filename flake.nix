{
  description = "sing-box with local patches to its dependencies";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";

  outputs =
    { self, nixpkgs }:
    let
      systems = [
        "aarch64-darwin"
        "x86_64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Release archives, named and configured like upstream's pure-Go builds
      # (release/DEFAULT_BUILD_TAGS without naive, so no cgo, cronet or
      # legacy-toolchain variants). Every target cross-compiles from any
      # system: sing-box-<target> builds the binary for <target>.
      targets = {
        "darwin-amd64" = {
          GOOS = "darwin";
          GOARCH = "amd64";
        };
        "darwin-arm64" = {
          GOOS = "darwin";
          GOARCH = "arm64";
        };
        "linux-amd64" = {
          GOOS = "linux";
          GOARCH = "amd64";
        };
        "linux-arm64" = {
          GOOS = "linux";
          GOARCH = "arm64";
        };
        "linux-386" = {
          GOOS = "linux";
          GOARCH = "386";
          GO386 = "sse2";
        };
        "linux-386-softfloat" = {
          GOOS = "linux";
          GOARCH = "386";
          GO386 = "softfloat";
        };
        "linux-armv5" = {
          GOOS = "linux";
          GOARCH = "arm";
          GOARM = "5";
        };
        "linux-armv6" = {
          GOOS = "linux";
          GOARCH = "arm";
          GOARM = "6";
        };
        "linux-armv7" = {
          GOOS = "linux";
          GOARCH = "arm";
          GOARM = "7";
        };
        "linux-mips-softfloat" = {
          GOOS = "linux";
          GOARCH = "mips";
          GOMIPS = "softfloat";
        };
        "linux-mipsle" = {
          GOOS = "linux";
          GOARCH = "mipsle";
          GOMIPS = "hardfloat";
        };
        "linux-mipsle-softfloat" = {
          GOOS = "linux";
          GOARCH = "mipsle";
          GOMIPS = "softfloat";
        };
        "linux-mips64-softfloat" = {
          GOOS = "linux";
          GOARCH = "mips64";
          GOMIPS64 = "softfloat";
        };
        "linux-mips64le" = {
          GOOS = "linux";
          GOARCH = "mips64le";
          GOMIPS64 = "hardfloat";
        };
        "linux-mips64le-softfloat" = {
          GOOS = "linux";
          GOARCH = "mips64le";
          GOMIPS64 = "softfloat";
        };
        "linux-ppc64le" = {
          GOOS = "linux";
          GOARCH = "ppc64le";
        };
        "linux-riscv64" = {
          GOOS = "linux";
          GOARCH = "riscv64";
        };
        "linux-loong64" = {
          GOOS = "linux";
          GOARCH = "loong64";
        };
        "linux-s390x" = {
          GOOS = "linux";
          GOARCH = "s390x";
        };
        "windows-amd64" = {
          GOOS = "windows";
          GOARCH = "amd64";
        };
        "windows-386" = {
          GOOS = "windows";
          GOARCH = "386";
        };
        "windows-arm64" = {
          GOOS = "windows";
          GOARCH = "arm64";
        };
        # Upstream builds android with cgo and the NDK. Only arm64 links
        # without cgo; android arm, 386 and amd64 require external linking.
        "android-arm64" = {
          GOOS = "android";
          GOARCH = "arm64";
        };
      };

      crossPackage =
        sing-box: target: goEnv:
        sing-box.overrideAttrs (old: {
          env = old.env // goEnv;
          # The binaries are already stripped by -s -w, and the host's strip
          # does not understand every target's format.
          dontStrip = true;
          # `go install` puts cross-compiled binaries under bin/<GOOS>_<GOARCH>.
          postBuild = (old.postBuild or "") + ''
            dir="$GOPATH/bin/${goEnv.GOOS}_${goEnv.GOARCH}"
            if [ -d "$dir" ]; then
              mv "$dir"/* "$GOPATH/bin/"
              rmdir "$dir"
            fi
          '';
          passthru = (old.passthru or { }) // {
            inherit goEnv;
          };
        });
    in
    {
      packages = forAllSystems (
        pkgs:
        let
          sing-box = pkgs.callPackage ./package.nix { };
        in
        {
          inherit sing-box;
          sing-box-openconnect-auth = pkgs.callPackage ./tools/openconnect-auth { };
          default = sing-box;
        }
        // nixpkgs.lib.mapAttrs' (
          target: goEnv: nixpkgs.lib.nameValuePair "sing-box-${target}" (crossPackage sing-box target goEnv)
        ) targets
      );
      checks = forAllSystems (pkgs: {
        inherit (self.packages.${pkgs.stdenv.hostPlatform.system}) sing-box;
        openconnect-auth =
          pkgs.runCommand "openconnect-auth-tests"
            {
              nativeBuildInputs = with pkgs; [
                bash
                jq
                coreutils
                ripgrep
                shellcheck
                shfmt
              ];
            }
            ''
                  test -x ${
                    self.packages.${pkgs.stdenv.hostPlatform.system}.sing-box-openconnect-auth
                  }/bin/sing-box-openconnect-auth
                  shellcheck ${./tools/openconnect-auth}/*.sh
                  shfmt -d -i 2 -ci ${./tools/openconnect-auth}/*.sh
              bash ${./tools/openconnect-auth}/tests.sh
                  touch "$out"
            '';
      });
      formatter = forAllSystems (pkgs: pkgs.nixfmt-rfc-style);
      # Target names for the release workflow's matrix.
      lib.releaseTargets = builtins.attrNames targets;
    };
}
