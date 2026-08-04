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

# subproject binaries land under build/<project>/<config>/, not build/<config>/
echo "built: build/proj-a/$config/app-a, build/proj-b/$config/app-b"
echo "staged by build/stage-$config.cmake -> build/x.ini, build/data/cfg.txt, build/assets/"
