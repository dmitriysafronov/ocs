#!/usr/bin/env bash

die () {
    echo "find-latest-tag.sh: $@"
    exit 1
}

get_all_tags() {
    i=0

    while [ $? == 0 ]; do
    i=$((i+1))
    curl https://registry.hub.docker.com/v2/repositories/${1}/tags/?page=$i 2> /dev/null | jq '."results"[]["name"]' 2> /dev/null
    done

    if [ $? != 0 ]; then
    true
    fi
}

###################################################

image=${1}

all_tags="$(get_all_tags ${image} \
    | sed 's/"//g' \
    | grep -vE '^latest$' \
)"

query=${2}
if [ -z "${query}" ]; then
    query=''
fi

tag="$(printf "%s\n" $all_tags \
    | grep -oE "${query}" \
    | sort -V \
    | tail -1 \
)"

if [ -z "${tag}" ]; then
    die "cannot find tag matching regex: ${2}"
fi

echo "tag=${tag}" >> $GITHUB_OUTPUT
