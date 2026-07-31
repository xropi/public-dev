#!/bin/sh
# usage: ./build.sh <Config> [extra cmake --build args]
# Configures once into build/ with a multi-config generator, then builds the
# requested config. build-debug.sh and build-release.sh wrap this.
set -e

config="${1:?usage: $0 <Config> [args...]}"
shift

cd "$(dirname "$0")"

# configure only if the tree is not there yet; cmake --build re-runs it as needed
[ -f build/CMakeCache.txt ] || cmake -G "Ninja Multi-Config" -B build -S .

cmake --build build --config "$config" "$@"

echo "built: build/$config/app   (ini staged at build/x.ini for $config)"
