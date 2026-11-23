#!/bin/bash
cd "$(dirname "$0")" || exit 1
/bin/bash scripts/update-custom-handy.sh
result=$?
printf '\nPress Return to close this window.\n'
read -r
exit "$result"
