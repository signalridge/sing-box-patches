#!/usr/bin/env bash
# Moves package.nix to sing-box's latest stable release (version, source hash,
# vendorHash), then builds every release target and writes a report of what
# still needs a person: a moved sing-openconnect pin, patches that no longer
# apply, and upstream build tag or ldflags changes.
#
# Needs nix, gh (authenticated), jq. Writes the report to $REPORT
# (default: update-report.md) and, under GitHub Actions, the outputs
# updated, version and title.
set -euo pipefail

cd "$(dirname "$0")/.."
report="${REPORT:-update-report.md}"
output="${GITHUB_OUTPUT:-/dev/null}"
log="$(mktemp)"
trap 'rm -f "$log" package.nix.bak README.md.bak' EXIT

upstream_file() {
	gh api "repos/SagerNet/sing-box/contents/$1?ref=v$2" -H "Accept: application/vnd.github.raw"
}
openconnect_pin() {
	upstream_file go.mod "$1" | awk '$1 == "github.com/sagernet/sing-openconnect" { print $2 }'
}
sorted_list() {
	tr ',' '\n' | sed '/^$/d' | sort
}

current="$(sed -n 's/^  version = "\(.*\)";$/\1/p' package.nix)"
latest="$(gh api repos/SagerNet/sing-box/releases/latest --jq .tag_name)"
latest="${latest#v}"
if [[ ! "$latest" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
	echo "unexpected latest stable release: $latest" >&2
	exit 1
fi
if [[ "$latest" == "$current" ]]; then
	echo "sing-box $current is the latest stable release"
	echo "updated=false" >>"$output"
	exit 0
fi
echo "updating sing-box $current -> $latest"

source_hash="$(nix flake prefetch --json "github:SagerNet/sing-box/v$latest" | jq -er .hash)"
sed -i.bak \
	-e "s|^  version = \".*\";$|  version = \"$latest\";|" \
	-e "s|^    hash = \".*\";$|    hash = \"$source_hash\";|" \
	-e "s|^  vendorHash = \".*\";$|  vendorHash = lib.fakeHash;|" \
	package.nix
vendor_hash="$(nix build .#sing-box.goModules --no-link 2>&1 | sed -n 's/^ *got: *//p' | tail -n 1 || true)"
if [[ "$vendor_hash" != sha256-* ]]; then
	echo "could not determine vendorHash for $latest" >&2
	exit 1
fi
sed -i.bak "s|^  vendorHash = lib.fakeHash;$|  vendorHash = \"$vendor_hash\";|" package.nix

attention=()

old_pin="$(openconnect_pin "$current")"
new_pin="$(openconnect_pin "$latest")"
if [[ "$old_pin" == "$new_pin" ]]; then
	pin_note="unchanged (\`$new_pin\`)"
else
	sed -i.bak -e "s|$old_pin|$new_pin|g" -e "s|${old_pin##*-}|${new_pin##*-}|g" README.md
	pin_note="moved from \`$old_pin\` to \`$new_pin\`: rebase the patches onto \`${new_pin##*-}\` and rerun their tests in the clone"
	attention+=("sing-openconnect pin moved")
fi

ours="$(nix eval --json .#sing-box.tags | jq -r 'join(",")' | sorted_list)"
theirs="$(upstream_file release/DEFAULT_BUILD_TAGS_OTHERS "$latest" | sorted_list)"
if [[ "$ours" == "$theirs" ]]; then
	tags_note="match upstream's \`release/DEFAULT_BUILD_TAGS_OTHERS\`"
else
	tags_note="differ from upstream's \`release/DEFAULT_BUILD_TAGS_OTHERS\`:"$'\n\n```diff\n'"$(diff <(echo "$ours") <(echo "$theirs") || true)"$'\n```'
	attention+=("build tags changed")
fi
old_ldflags="$(upstream_file release/LDFLAGS "$current")"
new_ldflags="$(upstream_file release/LDFLAGS "$latest")"
if [[ "$old_ldflags" == "$new_ldflags" ]]; then
	ldflags_note="unchanged"
else
	ldflags_note="changed from \`$old_ldflags\` to \`$new_ldflags\`: update \`ldflags\` in package.nix"
	attention+=("ldflags changed")
fi

build_status=0
{
	nix flake check -L
	nix eval --json .#lib.releaseTargets | jq -r '.[] | ".#sing-box-" + .' | xargs nix build --no-link --keep-going -L
} >"$log" 2>&1 || build_status=$?
if [[ "$build_status" -eq 0 ]]; then
	build_note="\`nix flake check\` and all release targets build, with every patch applied."
else
	attention+=("build failed")
	build_note="failed (exit $build_status)."
	if grep -q "Reversed (or previously applied) patch detected" "$log"; then
		build_note+=" A patch is already in upstream: delete it from patches/ and the README table."
	elif grep -qiE "hunk .*failed|can.t find file to patch" "$log"; then
		build_note+=" A patch no longer applies: rebase it in the clone."
	fi
	build_note+=$'\n\n<details><summary>Last lines of the build log</summary>\n\n```\n'"$(grep -v '^warning: Git tree' "$log" | tail -n 60)"$'\n```\n\n</details>'
fi

title="Update sing-box to $latest"
if [[ "${#attention[@]}" -gt 0 ]]; then
	attention_list="$(
		IFS=,
		echo "${attention[*]}"
	)"
	title+=" (needs attention: ${attention_list//,/, })"
fi

cat >"$report" <<EOF
Moves sing-box from \`$current\` to \`$latest\`
([release notes](https://github.com/SagerNet/sing-box/releases/tag/v$latest)):
\`version\`, source \`hash\` and \`vendorHash\` in package.nix.

- **sing-openconnect pin:** $pin_note
- **Build tags:** $tags_note
- **LDFLAGS:** $ldflags_note
- **Build:** $build_note

After merging, tag \`v$latest-p1\` on main to publish.
EOF

{
	echo "updated=true"
	echo "version=$latest"
	echo "title=$title"
} >>"$output"
echo "$title"
