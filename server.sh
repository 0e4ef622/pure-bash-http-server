#!/bin/bash

set -f;
LC_ALL="C"; # count bytes when doing stuff like ${#this}

echo New connection with $SOCAT_PEERADDR >> activity.log

: ${rootdir?} ${error_404_page?}
header_Connection="keep-alive";

declare -A mime_types;
while read a b; do
    [ -n "$b" ] && for i in $b; do
        mime_types["$i"]="$a";
    done;
done < mime.types

# BEGIN UGLY BINARY HACKS

split_file() { # split input along null bytes
    # Usage: split VAR < FILE
    local i=0;
    while read -r -d ''; do
        REPLY=${REPLY//\'/\'\"\'\"\'};
        eval "$1[$((i++))]='$REPLY'";
    done
    REPLY=${REPLY//\'/\'\"\'\"\'};
    eval "$1[$i]='$REPLY'";
}

join_file() { # undo what split_file did
    # Usage: join VAR[@] > FILE; example: join image[@] > image.png
    local i=0;
    local -a arr;
    arr=("${!1}"); # https://savannah.gnu.org/support/?110538
    local arrlen=${#arr[@]};
    for piece in "${arr[@]}"; do
        echo -n "$piece";
        if [ $((i++)) -lt $(( arrlen - 1 )) ]; then
            echo -en '\x00';
        fi
    done
}

# END UGLY BINARY HACKS

redirect_to() {
    status_code=301;
    status_msg="Moved Permanently";
    other_response_headers="$other_response_headers""Location: $1\r\n";
    response="";
    content_type="text/plain";
}

get_dir() {
    if [ "${1: -1}" != "/" ]; then
        redirect_to "$1/";
        return;
    fi

    dir="$rootdir$1";
    if [ -e "$dir/index.html" ]; then
        get_file "$1/index.html";
    else
        content_type="text/html";
        response="<!DOCTYPE html>
<html>
    <head>
        <title>Index of $1</title>
    </head>
    <body>
        <h1>Index of $1</h1>
        <hr/>
        $( (set +f;
            cd "$dir";
            shopt -s extglob;
            [ "${1##+(/)}" ] && echo "<a href=\"${1%/*/}/\">..</a><br/>";
            shopt -u extglob;
            for i in *; do
                [ -d "$i" ] && i="$i/"
                [ -e "$i" ] && echo "<a href=\"$i\">$i</a><br/>";
            done) )
    </body>
</html>
";
    fi
}

get_file() {
    file="$rootdir$1";
    #if [ -x "$file" ]; then
    #    split_file response < <("$file");
    #else
        split_file response < "$file";
    #fi

    name=${1##*/};
    extension=${name##*.};

    if [ "$name" = "$extension" ]; then
        shopt -s extglob;
        content_type=$(
            case "$name" in
                [Mm]akefile|GNU[Mm]akefile|+([[:upper:]])) echo "text/plain";;
                *) echo "application/octet-stream";;
            esac
        );
        shopt -u extglob;
    else
        content_type=${mime_types[$extension]};
        [ -z "$content_type" ] && content_type="application/octet-stream";
    fi
}

do_404() {
    status_code=404;
    status_msg="Not Found";
    get_file "$error_404_page";
}

get_range() {
    # TODO finish
    IFS="=" read unit range <<< "$2";
    if [ "$unit" != "bytes" ]; then
        get_file "$1";
        return;
    fi
    if [ "${range/,/}" != "$range" ]; then # if theres more than one range
        status_code=416;
        status_msg="Range Not Satisfiable";
        content_type="";
        return;
    fi
    get_file "$1";
    IFS="-" read begin end <<< "$range";
    status_code=206
    status_msg="Partial Content";
}

while [ "$header_Connection" = "keep-alive" ]; do
    unset response; # if the requested file is a binary file, this will become an array of data to be joined by null bytes
    status_code=200;
    status_msg="OK";
    content_type="text/plain";
    other_response_headers="";
    read method requested_file http_version;
    [ "$http_version" = "HTTP/1.0" ] && header_Connection="close";
    requested_file=${requested_file%%\?*}; # ignore everything after an ? for now
    requested_file=${requested_file//\\/\\\\};
    requested_file=${requested_file//%/\\x};
    requested_file=$(echo -en "$requested_file");

    echo [`printf '%(%a %b %d %T %Z %Y)T\n' -1`]: $SOCAT_PEERADDR accessed $requested_file >> activity.log; # log requests
    >> unique_ips.log;
    ipfound=0;
    while read ip _; do
        if [ "$ip" = "$SOCAT_PEERADDR" ]; then
            ipfound=1;
            break;
        fi
    done < unique_ips.log
    if [ "$ipfound" = "0" ]; then
        echo $SOCAT_PEERADDR >> unique_ips.log;
    fi

    while read line; do
        # read headers and do something with them
        line=${line///}; # kill those pesky CRs

        header=${line%%:*}; # the stuff before the semicolon
        value=${line#*: }; # the stuff after the semicolon and space
        value=${value//\'/\\\'}; # sanitize

        header=${header//-/_};
        if [ "$header" != "${header/[^a-zA-Z_0-9]/}" ]; then
            status_code=400;
            status_msg="Bad Request";
            response="quit tryin to hax mah server";
            break;
        fi
        eval "header_$header='$value'";
        if [ -z "$line" ]; then
            break;
        fi
    done

    if [ "$status_code" != "400" ]; then
        if [ -e "$rootdir$requested_file" ]; then
            if [ -d "$rootdir$requested_file" ]; then
                get_dir "$requested_file";
            else
                #if [ -z "$header_Range" ] && [ "$method" = "GET" ]; then
                #    get_range "$requested_file" "$header_Range";
                #else
                get_file "$requested_file";
                #fi
            fi
        else
            do_404;
        fi
    fi

    date=$(TZ=UTC printf '%(%a, %d %b %Y %T GMT)T\n' -1);
    date="${date% *} GMT";

    echo -e "HTTP/1.1 $status_code $status_msg\r";
    #echo -e "Accept-Ranges: bytes\r";
    echo -e "Date: $date\r";
    if [ -n "$content_type" ]; then echo -e "Content-Type: $content_type\r"; fi
    tmp="${response[*]}";
    echo -e "Content-Length: ${#tmp}\r";
    echo -e "Connection: $header_Connection\r";
    echo -e -n "$other_response_headers";
    echo -e "\r";
    join_file response[@];
done
