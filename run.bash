#!/bin/bash

IP="151.219.13.203"
PORT="1234"
STARTX="${2:-0}"

PIDS=()
declare -a PIDS

for i in $(seq 1 "$1"); do
	./fpf "${IP}" "${PORT}" "${STARTX}" &
	PIDS["$i"]="$!"
	sleep 2
done

while true
do
	for i in $(seq 1 "$1"); do
		pid="${PIDS[$i]}"
		if ps -p "$pid" > /dev/null
		then
			echo "${pid} is ok"
			continue
		fi

		echo "pid ${pid} stopped, restarting..."
		./fpf "${IP}" "${PORT}" "${STARTX}" &
		PIDS["$i"]="$!"
		sleep 2
	done
	sleep 1
done

