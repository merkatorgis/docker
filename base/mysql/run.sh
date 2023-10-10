#!/bin/bash
set -e

MYSQL_ROOT_PASSWORD=${1:-$DOCKER_USER}
MYSQL_DATABASE=${2:-$DOCKER_USER}

IMAGE=$IMAGE
CONTAINER=$CONTAINER
RESTART=$RESTART
IP=$IP

DOCKER_USER=$DOCKER_USER
DOCKER_ENV=$DOCKER_ENV
DOCKER_BINDS_DIR=$DOCKER_BINDS_DIR

SECRET=${SECRET}

gateway=$(docker network inspect "$DOCKER_USER" | grep 'Gateway' | grep -oP '\d+\.\d+\.\d+\.\d+')

MYSQL_PORT=$(docker4gis/port.sh "${MYSQL_PORT:-3306}")

docker volume create "$CONTAINER" >/dev/null
docker container run --restart "$RESTART" --name "$CONTAINER" \
	-e DOCKER_USER="$DOCKER_USER" \
	-e SECRET="$SECRET" \
	-e DOCKER_ENV="$DOCKER_ENV" \
	-e MYSQL_ROOT_PASSWORD="$MYSQL_ROOT_PASSWORD" \
	-e MYSQL_DATABASE="$MYSQL_DATABASE" \
	-e CONTAINER="$CONTAINER" \
	-e GATEWAY="$gateway" \
	--mount type=bind,source="$DOCKER_BINDS_DIR"/secrets,target=/secrets \
	--mount type=bind,source="$DOCKER_BINDS_DIR"/fileport,target=/fileport \
	--mount type=bind,source="$DOCKER_BINDS_DIR"/runner,target=/util/runner/log \
	--mount source="$CONTAINER",target=/var/lib/mysql \
	-p "$MYSQL_PORT":3306 \
	--network "$DOCKER_USER" \
	--ip "$IP" \
	-d "$IMAGE"

# wait for db
docker container exec "$CONTAINER" mysql.sh force "$MYSQL_DATABASE" -e ""
