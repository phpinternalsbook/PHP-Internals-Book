# get rid of old files, so we don't keep them around in the git repo
# when a file or directory was renamed
rm -rf BookHTML/html/*/
rm -f BookHTML/html/*.html
rm -f BookHTML/html/.buildinfo

sphinx-build -b html -d BookHTML/doctrees -a Book BookHTML/html
php generate_php5_redirects.php