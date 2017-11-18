#!/bin/sh

set -e

dst="$(dirname "$0")/gen"

rm -rf "$dst"
cp -r "$(nix-build -E '((import <nixpkgs> {}).callPackage ../. {}).arm-mras-src' --no-out-link)/gen" "$dst"
chown -R "$(whoami)" "$dst"
chmod -R 755 "$dst"