#!/usr/bin/env bash

# https://sipb.mit.edu/doc/safe-shell/
set -eufo pipefail

shopt -s failglob

# get rid of old files, so we don't keep them around in the git repo
# when a file or directory was renamed
rm -rf BookHTML/*/
rm -f BookHTML/*.html
rm -f BookHTML/.buildinfo

sphinx-build -b html -d doctrees -a Book BookHTML
php generate_php5_redirects.php
