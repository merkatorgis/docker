#!/bin/bash
set -e

POSTGRES_DB=${1:-$DOCKER_USER}
PGRST_DB_SCHEMA=${2:-$DOCKER_USER}

IMAGE=$IMAGE
CONTAINER=$CONTAINER
RESTART=$RESTART

DOCKER_USER=$DOCKER_USER
DOCKER_ENV=$DOCKER_ENV
DOCKER_BINDS_DIR=$DOCKER_BINDS_DIR

PGRST_JWT_SECRET=$(docker container exec "$DOCKER_USER-postgis" pg.sh force -Atc "select current_setting('app.jwt_secret')")

proxy=$PROXY_HOST
[ "$PROXY_PORT" ] && proxy=$proxy:$PROXY_PORT
PGRST_OPENAPI_SERVER_PROXY_URI=${PGRST_OPENAPI_SERVER_PROXY_URI:-https://$proxy/$DOCKER_USER/api}

docker container run --restart "$RESTART" --name "$CONTAINER" \
	-e DOCKER_USER="$DOCKER_USER" \
	--network "$DOCKER_USER" \
	-e PGRST_DB_URI="postgresql://web_authenticator:postgrest@$DOCKER_USER-postgis/$POSTGRES_DB" \
	-e PGRST_DB_SCHEMA="$PGRST_DB_SCHEMA" \
	-e PGRST_JWT_SECRET="$PGRST_JWT_SECRET" \
	-e PGRST_PRE_REQUEST="public.pre_request" \
	-e PGRST_DB_ANON_ROLE="web_anon" \
	-e PGRST_OPENAPI_SERVER_PROXY_URI="$PGRST_OPENAPI_SERVER_PROXY_URI" \
	-e PGRST_SERVER_PORT="8080" \
	-d "$IMAGE"
