#!/bin/sh
# Official 4.5.2 editor + matching Web templates, verified against SHA512-SUMS.txt.
set -eu

version=4.5.2
case "$(dpkg --print-architecture)" in
    amd64)
        arch=x86_64
        editor_sha=e3ce6194b6d4d2dcef5e5b5136752c084d9d8b9071c10bc2d2011b947ec7439a257c8d23c541cb30699f16d9edea6dff36e6e84d2bec14a8fe9b4e9aacbe5a8d
        ;;
    arm64)
        arch=arm64
        editor_sha=fde4d772a578f0978a10eaf06a460a4ad867778e3edb5ed3be97adae07a7547915208b1582123a9cfbc0757f7f5aff6ffac966d83f996ded3bdcdac404322c91
        ;;
    *) echo 'Godot container build supports amd64 and arm64 only' >&2; exit 1 ;;
esac

release="https://github.com/godotengine/godot-builds/releases/download/${version}-stable"
editor="Godot_v${version}-stable_linux.${arch}"
templates="Godot_v${version}-stable_export_templates.tpz"
templates_sha=003aa33743f58fb657717f090fc872ed3975e48d08a6012201a2259970d458a63d4d8a83090585307c23455ebfa4e6e0050e1057761c34863536095e3fcfab6c
download_dir=$(mktemp -d)
trap 'rm -rf "$download_dir"' EXIT
cd "$download_dir"

curl --fail --location --retry 3 --output editor.zip "${release}/${editor}.zip"
printf '%s  editor.zip\n' "$editor_sha" | sha512sum --check -
unzip -q editor.zip
install -m 0755 "$editor" /usr/local/bin/godot

curl --fail --location --retry 3 --output templates.tpz "${release}/${templates}"
printf '%s  templates.tpz\n' "$templates_sha" | sha512sum --check -
unzip -q templates.tpz 'templates/web_nothreads_*.zip'
template_dir="/root/.local/share/godot/export_templates/${version}.stable"
mkdir -p "$template_dir"
mv templates/web_nothreads_*.zip "$template_dir/"
godot --headless --version
