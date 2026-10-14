#!/bin/sh
set -eu

origin=${1:?usage: check-health.sh https://plc-reader.example.com}
health=$(curl --fail --silent --show-error --max-time 10 "$origin/_health")
committed=$(printf '%s' "$health" | jq -er '.lastCommittedOpTime | sub("\\.[0-9]+Z$"; "Z") | fromdateiso8601')
age=$(($(date +%s) - committed))

if [ "$age" -lt -300 ] || [ "$age" -gt 300 ]; then
	echo "replica is stale: last committed operation is ${age}s old" >&2
	exit 1
fi

printf '%s\n' "$health"
