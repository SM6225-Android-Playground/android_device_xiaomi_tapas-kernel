#!/bin/env bash

# Safe mode
set -xeuo pipefail

# Variables
BASE_DIR="."
DTB_DIR="$BASE_DIR/dtbs"
DTS_DIR="$DTB_DIR/dts"

# Restore any current changes
git restore "$DTB_DIR"

# Function for labelling nodes
function label() {
    sed -i "s/$2 {/$3: $2 {/g" "$1"
}

# Create fresh DTS_DIR
if [[ -d "$DTS_DIR" ]]; then
    rm -rf "$DTS_DIR"
fi
mkdir -p "$DTS_DIR"

# Initialize dts repo
git -C "$DTS_DIR" init
git -C "$DTS_DIR" commit --allow-empty -m iec

# Dump existing dtb to dts repo
while read -r dtb; do
    dtc -q -I dtb -O dts "$dtb" -o "${dtb/.dtb/}.dts"
done <<<"$(find "$DTB_DIR" -type f -iname '*.dtb')"

# Commit unmodified dts in dts repo
mv "$DTB_DIR"/*.dts "$DTS_DIR"
git -C "$DTS_DIR" add '*.dts'
git -C "$DTS_DIR" commit -m dts

# Add our patches to decompiled dts and compile to dtb
while read -r dts; do
    # Skip patching for dtb fragments
    if ! grep -q 'fragment' "$dts"; then
        # Label restart node and add warm reboot flag
        label "$dts" "restart@440b000" "restart"
        echo "&restart { qcom,force-warm-reboot; };" >>"$dts"
        # Skip patching if new ramoops node present
        if ! grep -q 'ramoops@9ff00000' "$dts"; then
            # Label old ramoops node and delete it
            label "$dts" "ramoops@5D000000" "ramoops"
            echo "/delete-node/ &ramoops;" >>"$dts"
            # Label reserved memory node and add new ramoops node
            label "$dts" "reserved-memory" "reserved_memory"
            echo '&reserved_memory { ramoops@9ff00000 { compatible = "ramoops"; reg = <0x0 0x9ff00000 0x0 0x00100000>; console-size = <0x100000>; max-reason = <0x04>; status = "ok"; }; };' >>"$dts"
        fi
        # Convert dts back to dtb
        dtc -q -I dts -O dtb "$dts" -o "${dts/.dts/}.dtb"
    fi
done <<<"$(find "$DTS_DIR" -type f -iname '*.dts')"

# Commit intermediate dts to dts repo
echo -e "\n\nINTERMEDIATE DTS\n\n"
git -C "$DTS_DIR" add '*.dts'
git -C "$DTS_DIR" commit -m dts-intermediate
git -C "$DTS_DIR" -P diff --color HEAD~1..HEAD >"$DTS_DIR"/dts-intermediate.diff
cat "$DTS_DIR"/dts-intermediate.diff

# Unpack newly compiled dtbs to DTS_DIR
while read -r dtb; do
    dtc -q -I dtb -O dts "$dtb" -o "${dtb/.dtb/}.dts"
done <<<"$(find "$DTS_DIR" -type f -iname '*.dtb')"

# Commit final dts to dts repo
echo -e "\n\nFINAL DTS\n\n"
git -C "$DTS_DIR" add '*.dts'
git -C "$DTS_DIR" commit --amend --no-edit --allow-empty
git -C "$DTS_DIR" -P diff --color HEAD~1..HEAD >"$DTS_DIR"/dts-final.diff
cat "$DTS_DIR"/dts-final.diff

# Move new dtbs from dts repo to DTB_DIR
mv "$DTS_DIR"/*.dtb "$DTB_DIR"

# Remove DTS_DIR
rm -rf "$DTS_DIR"
