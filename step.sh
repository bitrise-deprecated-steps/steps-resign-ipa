#!/bin/bash

THIS_SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "Installing Gemfile"
gemfile_output=$(BUNDLE_GEMFILE="${THIS_SCRIPT_DIR}/Gemfile" bundle install)

echo
BUNDLE_GEMFILE="${THIS_SCRIPT_DIR}/Gemfile" bundle exec ruby "${THIS_SCRIPT_DIR}/step.rb"
