#!/bin/bash
# Copyright (C) <2023-2023> Intel Corporation
# SPDX-License-Identifier: MIT

# Install sar if not already
if ! command -v sar &> /dev/null
then
    echo "sar is not installed"
    echo "Installing sar..."
    sudo apt install sysstat -y
fi

function print_usage {
    echo >&2 "Usage:"
    echo >&2 "    $0 [args]"
    echo >&2 "    args:"
    echo >&2 "        -h|--help -- prints this message"
    echo >&2 "        -i|--interval -- sar sampling interval, default is $interval"
    echo >&2 "        -o|--output -- output file, default is $output"
}

function error_exit {
    print_usage
    exit -1
}

interval=1
output=cpu-util.txt

while [[ $# > 0 ]]
do
    key="$1"
    case $key in
    -i|--interval)
        if [ -z "$2" ]; then
            error_exit
        fi
        interval="$2"
        shift
        ;;
    -o|--output)
        if [ -z "$2" ]; then
            error_exit
        fi
        output="$2"
        shift
        ;;
    -h|--help)
        print_usage
        exit 0
        ;;
    *)
        error_exit
    ;;
    esac
    shift
done

nohup sar -P ALL $interval > $output 2>&1 &
