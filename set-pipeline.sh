#!/usr/bin/env bash

dir="$(cd "$(dirname "$0")" && pwd)"

fly -t wings set-pipeline \
  -p buildpack \
  -c <(cat $dir/resources.yml && cat $dir/jobs.yml)