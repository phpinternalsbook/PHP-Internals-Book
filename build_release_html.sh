# get rid of old files, so we don't keep them around in the git repo
# when a file or directory was renamed
rm -rf BookHTML/*/
rm -f BookHTML/*.html
rm -f BookHTML/.buildinfo

sphinx-build -b html -d doctrees -a Book BookHTML
