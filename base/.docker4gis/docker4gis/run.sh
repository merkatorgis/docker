#!/bin/bash

repo=$1
tag=$2
shift 2

DOCKER_REGISTRY=$DOCKER_REGISTRY
DOCKER_USER=$DOCKER_USER
DOCKER_BINDS_DIR=$DOCKER_BINDS_DIR
DOCKER_ENV=${DOCKER_ENV:-DEVELOPMENT}
export DOCKER_ENV
[ "$DOCKER_ENV" = DEVELOPMENT ] &&
    RESTART=no ||
    RESTART=always
export RESTART

# create before running any container, to have this owned by the user running
# the run script (instead of a container's root user)
mkdir -p "$DOCKER_BINDS_DIR"/fileport/"$DOCKER_USER"

IMAGE=$DOCKER_REGISTRY/$DOCKER_USER/$repo:$tag
export IMAGE

CONTAINER=$DOCKER_USER-$repo
[ "$repo" = proxy ] && CONTAINER=docker4gis-proxy
export CONTAINER

NETWORK=$DOCKER_USER
[ "$repo" = proxy ] && NETWORK=$CONTAINER
export NETWORK

echo
echo "Starting $CONTAINER from $IMAGE..."

# Pull the image from the registry if we don't have it locally, so that we
# have it ready to run a new container right after we stop the running one.
container=$(docker container create "$IMAGE") || exit 1
docker container rm "$container" >/dev/null

if old_image=$(docker container inspect --format='{{ .Config.Image }}' "$CONTAINER" 2>/dev/null); then
    if [ "$old_image" = "$IMAGE" ]; then
        docker container start "$CONTAINER" &&
            exit 0 || # Existing container from same image is started, and we're done.
            echo "The existing container failed to start; we'll remove it, and create a new one..."
    fi
    docker container stop "$CONTAINER" >/dev/null || exit $?
    docker container rm "$CONTAINER" >/dev/null || exit $?
fi

temp=$(mktemp -d)
finish() {
    err_code=${1:-$?}
    rm -rf "$temp"
    exit "$err_code"
}

if
    dotdocker4gis="$(dirname "$0")"/.docker4gis.sh
    BASE=$("$dotdocker4gis" "$temp" "$IMAGE")
then
    pushd "$BASE" >/dev/null || finish 1
    docker4gis/network.sh "$NETWORK" || finish 2
    export FILEPORT=$DOCKER_BINDS_DIR/fileport/$DOCKER_USER
    mkdir -p "$FILEPORT" || finish 3
    export VOLUME=$CONTAINER
    docker volume create "$VOLUME" >/dev/null || finish 4
    # Execute the (base) image's run script,
    # passing args read from its args file,
    # substituting environment variables,
    # and skipping lines starting with a #.
    envsubst <args | grep -v "^#" | xargs \
        ./run.sh "$@"
    result=$?
    popd >/dev/null || finish 1
fi

finish "$result"
