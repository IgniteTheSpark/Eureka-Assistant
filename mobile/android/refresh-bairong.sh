#!/bin/bash

GROUP_LIB="com.bairong.lib"
GROUP_CONFIG="com.bairong.config"
VERSION=$1
OPTION=$2

# shellcheck disable=SC2164
SCRIPT_DIR="$(cd "$(dirname "$0")"; pwd)"
CACHE_TOOL="$SCRIPT_DIR/gradle-cache-tool.sh"

if [ ! -f "$CACHE_TOOL" ]; then
    echo "gradle-cache-tool.sh not found in $SCRIPT_DIR"
    exit 1
fi

echo "========================================"
echo "Gradle Cache Refresh Tool"
echo "Target: $GROUP_LIB"
echo "========================================"

if [ -z "$VERSION" ]; then

    echo "Cleaning ALL versions..."

    sh "$CACHE_TOOL" clean "$GROUP_LIB" "$OPTION"

else

    echo "Cleaning version: $VERSION"

    sh "$CACHE_TOOL" clean "$GROUP_LIB" "$VERSION" "$OPTION"

fi


echo "========================================"
echo "Gradle Cache Refresh Tool"
echo "Target: $GROUP_CONFIG"
echo "========================================"

if [ -z "$VERSION" ]; then

    echo "Cleaning ALL versions..."

    sh "$CACHE_TOOL" clean "$GROUP_CONFIG" "$OPTION"

else

    echo "Cleaning version: $VERSION"

    sh "$CACHE_TOOL" clean "$GROUP_CONFIG" "$VERSION" "$OPTION"

fi