#!/bin/bash

GRADLE_CACHE="$HOME/.gradle/caches/modules-2"

FILES_CACHE="$GRADLE_CACHE/files-2.1"

SYNC=false
DRYRUN=false

CMD=$1
GROUP=$2
ARTIFACT=$3
VERSION=$4

for arg in "$@"; do
  if [[ "$arg" == "--nosync" ]]; then
      SYNC=false
  fi
  if [[ "$arg" == "--dry-run" ]]; then
      DRYRUN=true
  fi
done


function list_groups() {
    echo "===== Cached Groups ====="
    ls "$FILES_CACHE"
}

function search_cache() {
    KEY=$1
    echo "===== Search: $KEY ====="
    find "$FILES_CACHE" -type d | grep "$KEY"
}

function delete_path() {
    TARGET=$1

    if [ -d "$TARGET" ]; then
        if $DRYRUN; then
            echo "[DRY] would delete: $TARGET"
        else
            echo "Deleting: $TARGET"
            rm -rf "$TARGET"
        fi
    fi
}

function clean_cache() {

    if [ -z "$GROUP" ]; then
        echo "Group required"
        exit 1
    fi

    if [ -z "$ARTIFACT" ]; then

        echo "Cleaning GROUP: $GROUP"

        delete_path "$FILES_CACHE/$GROUP"

    elif [ -z "$VERSION" ]; then

        echo "Cleaning ARTIFACT: $GROUP:$ARTIFACT"

        delete_path "$FILES_CACHE/$GROUP/$ARTIFACT"

    else

        echo "Cleaning VERSION: $GROUP:$ARTIFACT:$VERSION"

        delete_path "$FILES_CACHE/$GROUP/$ARTIFACT/$VERSION"

    fi
}

function gradle_sync() {

    if $SYNC && ! $DRYRUN; then
        echo "Running Gradle sync..."
        ./gradlew build
    else
        echo "Skip Gradle sync"
    fi
}


case "$CMD" in
    list)
        list_groups
        ;;
    search)
        search_cache "$GROUP"
        ;;
    clean)
        clean_cache
        gradle_sync
        ;;
    *)
        echo ""
        echo "Gradle Cache Tool"
        echo ""
        echo "Usage:"
        echo "  list                                   list cached groups"
        echo "  search <keyword>                       search cache"
        echo "  clean <group>"
        echo "  clean <group> <artifact>"
        echo "  clean <group> <artifact> <version>"
        echo ""
        echo "Options:"
        echo "  --dry-run       preview only"
        echo "  --nosync        skip gradle build"
        echo ""
        ;;
esac