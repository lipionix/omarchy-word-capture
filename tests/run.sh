#!/bin/sh
# Run every test: sh tests/run.sh (needs node for the logic tests).
set -e
here=$(dirname -- "$0")
node "$here/model.test.js"
sh "$here/append.test.sh"
