#!/usr/bin/env bash

lpass_note() {
  lpass show --notes "Shared-Build Service/$1"
}

dir="$(cd "$(dirname "$0")" && pwd)"

concourse_service_account_key=$(lpass_note 'gcp-concourse-service-account-json-key')

cat <(cat $dir/resources.yml && cat $dir/jobs.yml) | pbcopy

fly -t wings set-pipeline \
  -p buildpack \
  --var concourse-service-account-key-json="$concourse_service_account_key" \
  -c <(cat $dir/resources.yml && cat $dir/jobs.yml)
