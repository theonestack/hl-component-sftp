#!/bin/sh

if [ "$(which docker)" == "" ]; then
    if [ "$(which pip)" == "" ]; then
        echo "You need either PIP or DOCKER to package Sns Slack notifier"
        exit -1
    fi
    pip install -r requirements.txt -t .
else
    docker run --rm -v $PWD:/src -w /src python:3.6-alpine pip install -r requirements.txt -t /src
fi