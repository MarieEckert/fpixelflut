#!/bin/bash

IP="151.219.13.203"
PORT="1234"

for i in $(seq 1 $1); do
	./fpf "${IP}" "${PORT}" &
	sleep 2
done

trap "./fpf ${IP} ${PORT} &" SIGCHLD

while true
do
	sleep 1
done

