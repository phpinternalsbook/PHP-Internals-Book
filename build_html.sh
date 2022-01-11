#!/usr/bin/env bash

# https://sipb.mit.edu/doc/safe-shell/
set -eufo pipefail

shopt -s failglob

sphinx-build -b html -d doctrees Book BookHTML
php generate_php5_redirects.php
