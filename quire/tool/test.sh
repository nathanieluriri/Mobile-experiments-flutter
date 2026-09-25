#!/bin/sh
# Runs the suite from a clean failures folder, so every diff in it belongs to
# this run rather than to one that has since been fixed.
set -e
cd "$(dirname "$0")/.."
rm -rf test/failures
exec flutter test "$@"
