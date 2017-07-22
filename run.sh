#!/bin/bash

PORT=80 # default port
rootdir="./rootdir";
error_404_page="/404.html"; # inside ./rootdir
keepalive_timeout=10;

while read line; do
    line=${line%%#*}; # strip comments
    read line <<< "$line"; # trim whitespace
    case "${line%%=*}" in
        PORT) PORT=${line:5};;
        ROOTDIR) rootdir=${line:8};;
        404_PAGE) error_404_page=${line:9};;
        KEEPALIVE_TIMEOUT) keepalive_timeout=${line:18};;
    esac
done < options

echo "Running server on port $PORT";

export rootdir;
export error_404_page;
socat -T$keepalive_timeout TCP4-LISTEN:$PORT,pktinfo,fork EXEC:./server.sh
