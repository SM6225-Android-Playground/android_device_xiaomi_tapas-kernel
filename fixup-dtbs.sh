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
find "$DTB_DIR" -type f -iname '*.dtb' | while read -r dtb; do
    dtc -q -I dtb -O dts "$dtb" -o "${dtb/.dtb/}.dts"
done

# Commit unmodified dts in dts repo
mv "$DTB_DIR"/*.dts "$DTS_DIR"
git -C "$DTS_DIR" add .
git -C "$DTS_DIR" commit -m dts

# Add our patches to decompiled dts and compile to dtb
find "$DTS_DIR" -type f -iname '*.dts' | while read -r dts; do
    if ! grep -q fragment "$dts"; then
        label "$dts" "restart@440b000" "restart"
        label "$dts" "ramoops@5D000000" "ramoops"
        echo "&restart { qcom,force-warm-reboot; };" >>"$dts"
        echo "&ramoops { max-reason = <4>; };" >>"$dts"
        dtc -q -I dts -O dtb "$dts" -o "${dts/.dts/}.dtb"
    fi
done

# Commit intermediate dts to dts repo
echo -e "\n\nINTERMEDIATE DTS\n\n"
git -C "$DTS_DIR" add .
git -C "$DTS_DIR" commit -m dts-intermediate
git -C "$DTS_DIR" -P diff HEAD~1..HEAD

# Unpack newly compiled dtbs to DTS_DIR
find "$DTS_DIR" -type f -iname '*.dtb' | while read -r dtb; do
    dtc -q -I dtb -O dts "$dtb" -o "${dtb/.dtb/}.dts"
done

# Commit final dts to dts repo
echo -e "\n\nFINAL DTS\n\n"
git -C "$DTS_DIR" add .
git -C "$DTS_DIR" commit -m dts-final
git -C "$DTS_DIR" -P diff HEAD~1..HEAD

# Move new dtbs from dts repo to DTB_DIR
mv "$DTS_DIR"/*.dtb "$DTB_DIR"

# Remove DTS_DIR
rm -rf "$DTS_DIR"
