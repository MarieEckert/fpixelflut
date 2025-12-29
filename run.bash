#!/bin/bash

IP="151.219.62.20"
PORT="1337"
STARTX="${2:-0}"
NPROCS="${1:-1}"

RUNNING='1'

PIDS=()
declare -a PIDS

AllesUmbringen() {
	RUNNING='0'
	echo "giving some time for the main loop to exit"
	sleep 3.5
	for i in $(seq 1 "${NPROCS}"); do
		echo "killing ${PIDS[$i]}"
		kill "${PIDS[$i]}"
	done
	echo "done."
}

trap "AllesUmbringen" SIGINT

for i in $(seq 1 "${NPROCS}"); do
	./fpf "${IP}" "${PORT}" "${STARTX}" &
	PIDS["$i"]="$!"
	sleep 2
done

while [ "${RUNNING}" -eq 1 ]
do
	for i in $(seq 1 "${NPROCS}"); do
		if [ "${RUNNING}" -ne 1 ]
		then
			break
		fi

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

