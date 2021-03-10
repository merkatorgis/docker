#!/bin/bash

# TODO: Replace with actual path to angular code
wwwroot="$(pwd)/../../code/woningvoorraad"

# "$wwwroot"/.npmrc provides any Nexus credentials to the builder
if ! [ -f "$wwwroot"/.npmrc ]; then
    # if it's not in the project source; try to get it from the user's home dir
    [ -f ~/.npmrc ] && cp ~/.npmrc "$wwwroot"
fi

"$BASE"/build.sh "$wwwroot"
