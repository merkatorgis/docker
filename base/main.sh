#!/bin/bash

DOCKER_BASE=$(realpath "$(dirname "$0")")
export DOCKER_BASE

DOCKER_BINDS_DIR=$(realpath ~)/docker-binds
export DOCKER_BINDS_DIR

export DOCKER_REGISTRY=$DOCKER_REGISTRY
export DOCKER_USER=$DOCKER_USER
export DOCKER_REPO=$DOCKER_REPO

export DOCKER_ENV=DEVELOPMENT

export PROXY_HOST=${PROXY_HOST:-localhost}
export PROXY_PORT=${PROXY_PORT:-7443}
export PROXY_PORT_HTTP=${PROXY_PORT_HTTP:-7780}
export SECRET=$SECRET
export APP=$APP
export API=$API
export HOMEDEST=$HOMEDEST

export POSTFIX_DESTINATION=$POSTFIX_DESTINATION
export POSTFIX_DOMAIN=$POSTFIX_DOMAIN

export MSYS_NO_PATHCONV=1

dir=$1
action=$2
shift 2

this() {
	"$0" "$dir" "$@"
}

dir() {
	# Perform the current action in the given component/package directory, with
	# the given parameters.
	repo=$1
	shift 1
	if [ "$repo" ] && ! [ "$repo" = "$DOCKER_REPO" ]; then
		dir_found=$(mktemp)
		rm "$dir_found"
		for env_file in ../*/.env; do
			[ -f "$env_file" ] || break
			(
				# shellcheck source=/dev/null
				. "$env_file"
				if [ "$repo" = "$DOCKER_REPO" ]; then
					dir=$(dirname "$env_file")
					touch "$dir_found"
					# echo " ! cd to $dir"
					cd "$dir" || exit 1
					"$DOCKER_BASE"/../docker4gis "$action" "$@"
				fi
			)
		done
		if [ -f "$dir_found" ]; then
			rm "$dir_found"
			exit 0
		else
			echo "Cannot find directory for $repo."
			exit 1
		fi
	fi
}

case "$action" in
build)
	dir "$1"
	this test &&
		"$DOCKER_BASE/.docker4gis/docker4gis/build.sh"
	;;
run)
	dir package "$@"
	tag=$1
	if [ "$tag" ]; then
		eval "$(docker container run --rm "$DOCKER_REGISTRY"/"$DOCKER_USER"/package:"$tag")"
	else
		if runscript=$(BASE=$DOCKER_BASE/.docker4gis "$DOCKER_BASE"/package/list.sh dirty); then
			eval "$runscript" && echo &&
				docker container ls
		else
			false
		fi
	fi && echo && this test
	;;
br)
	this build "$1" && echo &&
		this run
	;;
push)
	dir "$1"
	"$DOCKER_BASE/push.sh"
	;;
test)
	dir "$1"
	"$DOCKER_BASE/test.sh"
	;;
stop)
	"$DOCKER_BASE/stop.sh"
	;;
geoserver)
	app_name=${1:-$DOCKER_USER}
	container=$DOCKER_USER-geoserver
	data_dir=$(docker container exec "$container" bash -c 'echo "$GEOSERVER_DATA_DIR"')
	from=$container:$data_dir/workspaces/$app_name
	to=geoserver/conf/$app_name/workspaces
	echo "About to overwrite './$to/$app_name' with '$from'"
	read -rn 1 -p 'Press any key to continue (or Ctrl-C to cancel)...'
	echo
	rm -rf "${to:?}/$app_name"
	docker container cp "$from" "$to"
	;;
*)
	echo "Unknown action: $action"
	;;
esac
