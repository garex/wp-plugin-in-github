#!/bin/bash

################################################################################
# Deploy WordPress Plugin to svn from Github
# Author: Sudar <http://sudarmuthu.com>
#
# License: Beerware ;)
#
# You should invoke this script from the Plugin directory, but you don't need
# to copy this script to every Plugin directory. You can just have one copy
# somewhere and then invoke it from multiple Plugin directories.
#
# Usage:
#  ./path/to/deploy-plugin.sh [-p plugin-name] [-u svn-username] [-m main-plugin-file]
#            [-a assets-dir-name] [-t tmp directory] [-i path/to/i18n] [-h history/changelog file]
#
# Refer to the README.md file for information about the different options
#
# Credit: Uses most of the code from the following places
#       https://github.com/deanc/wordpress-plugin-git-svn
#       https://github.com/thenbrent/multisite-user-management/blob/master/deploy.sh
#       https://github.com/ocean90/svn2git-tools/
################################################################################

# default configurations
PLUGINSLUG=${PWD##*/}                    # The name of the Plugin. By default the directory name is used
MAINFILE="$PLUGINSLUG.php"               # this should be the name of your main php file in the WordPress Plugin
ASSETS_DIR="assets-wp-repo"              # the name of the assets directory that you are using
POT_DIR="languages/"                     # name of your language file directory
SVNUSER="ustimenko"                      # your svn username
TMPDIR="/tmp"                            # temp directory path
HISTORY_FILE="CHANGELOG.md"              # changelog/history file
TMP_ADDON_DIR="tmp_addon"                # Temp folder where addon files will be stored
EXTRA_FILES="../$PLUGINSLUG-*"           # Path to extra addon files
PROCESS_EXTRA_FILES=false                # Whether to process extra files or not
CURRENTDIR=`pwd`
COMMIT_MSG_FILE='wp-plugin-commit-msg.tmp'

# Get the directory in which this shell script is present
cd $(dirname "${0}") > /dev/null
SCRIPT_DIR=$(pwd -L)
cd - > /dev/null

# WordPress i18n path. You can check it out from http://i18n.svn.wordpress.org/tools/trunk/
I18N_PATH=$SCRIPT_DIR/../i18n

# Readme converter
README_CONVERTER=$SCRIPT_DIR/readme-converter.sh
README_MD=`git ls-files | grep -i readme.md`

# lifted this code from http://www.shelldorado.com/goodcoding/cmdargs.html
while [ $# -gt 0 ]
do
    case "$1" in
        -p)  PLUGINSLUG="$2"; MAINFILE="$PLUGINSLUG.php"; shift;;
        -u)  SVNUSER="$2"; shift;;
        -m)  MAINFILE="$2"; shift;;
        -a)  ASSETS_DIR="$2"; shift;;
        -i)  I18N_PATH="$2"; shift;;
        -t)  TMPDIR="$2"; shift;;
        -h)  HISTORY_FILE="$2"; shift;;
        -x)  PROCESS_EXTRA_FILES=true; shift;;     # Handle additional extra addon files. This is very specific to my usecase. You may not need it.
        -*)
            echo >&2 \
            "usage: $0 [-p plugin-name] [-u svn-username] [-m main-plugin-file] [-a assets-dir-name] [-t tmp directory] [-i path/to/i18n] [-h history/changelog file]"
            exit 1;;
        *)  break;;	# terminate while loop
    esac
    shift
done

# git config
GITPATH="$CURRENTDIR"

# svn config
SVNPATH="$TMPDIR/$PLUGINSLUG" # path to a temp SVN repo. No trailing slash required and don't add trunk.
SVNPATH_ASSETS="$TMPDIR/$PLUGINSLUG-assets" # path to a temp assets directory.
SVNURL="http://plugins.svn.wordpress.org/$PLUGINSLUG/" # Remote SVN repo on wordpress.org

# removing local SVN path
rm -rf $SVNPATH

#SVNURL="file:///home/ustimenko/projects/UstimenkoAlexander/wp-testing/plugins-svn-wordpress-org-repo/$PLUGINSLUG/" # Remote SVN repo on wordpress.org

cd $GITPATH

# Let's begin...
echo ".........................................."
echo
echo "Preparing to deploy WordPress Plugin"
echo
echo ".........................................."
echo

# Retrieve commit message of last tag
# LAST_TAG=`git describe --tags --abbrev=0`
LAST_TAG=`git tag -l | tail -n1`
# git log --format=%B -n 1 $LAST_TAG > $TMPDIR/$COMMIT_MSG_FILE
git cat-file -p $(git rev-parse $LAST_TAG) | tail -n +6 > $TMPDIR/$COMMIT_MSG_FILE

echo
# Process /assets directory
if [ -d $GITPATH/$ASSETS_DIR ]; then
    echo "[Info] Assets directory found. Processing it."

    if svn checkout $SVNURL/assets $SVNPATH_ASSETS; then
        echo "[Info] Assets directory is checked out to: $SVNPATH_ASSETS"
    else
        echo "[Info] Assets directory is not found in SVN. Creating it."
        # /assets directory is not found in SVN, so let's create it.
        # Create the assets directory and check-in.
        # I am doing this for the first time, so that we don't have to checkout the entire Plugin directory, every time we run this script.
        # Since it takes lot of time, especially if the Plugin has lot of tags
        svn checkout $SVNURL $TMPDIR/$PLUGINSLUG
        cd $TMPDIR/$PLUGINSLUG
        mkdir assets
        svn add assets
        svn commit -m "Created the assets directory in SVN"
        rm -rf $TMPDIR/$PLUGINSLUG
        svn checkout $SVNURL/assets $SVNPATH_ASSETS
    fi

	find $SVNPATH_ASSETS -type f -not -path '*.svn*' -delete
    cp $GITPATH/$ASSETS_DIR/* $SVNPATH_ASSETS # copy assets
    cd $SVNPATH_ASSETS # Switch to assets directory

    svn status | grep "^!" > /dev/null 2>&1 # Check if deleted assests exists
    if [ $? -eq 0 ]; then
        svn status | grep "^!" | awk '{print $2}' | xargs svn delete # Remove deleted assets
    fi

    svn status | grep "^?\|^M" > /dev/null 2>&1 # Check if new or updated assets exists
    if [ $? -eq 0 ]; then
        svn status | grep "^?" | awk '{print $2}' | xargs svn add # Add new assets
    fi

	svn propset svn:mime-type image/jpeg *.jpg
	svn propset svn:mime-type image/png *.png

	svn status | egrep "^ ?(A|M|D)" > /dev/null 2>&1 # Check if we have somethign staged
    if [ $? -eq 0 ]; then
		    svn status | egrep "^ ?(A|M|D)"
		    read -rsp $'[ .. ] Ready to commit assets. Press enter...\n'
            svn commit --username=$SVNUSER -m "Updated assets"
            echo "[Info] Assets committed to SVN."
        else
            echo "[Info] Contents of Assets directory unchanged. Ignoring it."
    fi

    # Let's remove the assets directory in /tmp which is not needed any more
    rm -rf $SVNPATH_ASSETS
else
    echo "[Info] No assets directory found."
fi

cd $GITPATH

echo
echo "[Info] Creating local copy of SVN repo ..."
svn co $SVNURL/trunk $SVNPATH

echo "[Info] Merging SVN and GIT"
cd $SVNPATH
cp -r $GITPATH/.git .

echo "[Info] Checking out last tag"
GIT_BRANCH=`git rev-parse --abbrev-ref HEAD`
git reset --hard $LAST_TAG
cp $GITPATH/.gitignore .
echo .svn >> .gitignore
echo /vendor >> .gitignore
echo /readme.txt >> .gitignore

echo "[Info] Removing deleted files (as they not tracked in git)"
git ls-files --others --exclude-standard | xargs rm -rf

echo "[Info] Ignoring github specific files and deployment script"
# There is no simple way to exclude readme.md. http://stackoverflow.com/q/16066485/24949
svn propset svn:ignore "[Rr][Ee][Aa][Dd][Mm][Ee].[Mm][Dd]
.git
$HISTORY_FILE
$ASSETS_DIR
composer.lock
.gitignore" "$SVNPATH"

# Addin vendors
if [ -f composer.json ]; then
    echo "[Info] Adding vendors files"

    # Leave only needed vendor stuff
    # composer install --no-dev --no-progress --dry-run | grep 'Nothing to install or update' > /dev/null ||
    composer update --no-interaction --prefer-dist --no-dev
    composer install --no-interaction --prefer-dist --no-dev

    # Copy-paste
    cd $GITPATH/vendor
    tar cf - --exclude='.git' --exclude='.hg' . | (mkdir -p $SVNPATH/vendor && cd $SVNPATH/vendor && tar xvf - )
fi

echo "[Info] Changing directory to SVN and committing to trunk"
cd $SVNPATH

# remove assets directory if found
if [ -d $ASSETS_DIR ]; then
    rm -rf $ASSETS_DIR
fi

echo "[Info] Remove development-only stuff"
rm -rf db/sql languages/*.po tests tools vendor/bin phpunit.xml.dist

# Merge History file
if [ -f "$README_MD" ] && [ -f "$HISTORY_FILE" ]; then
    echo "[Info] Changelog file $HISTORY_FILE found. Merging it with readme file"
    cat $HISTORY_FILE >> $README_MD
fi

# Convert markdown in readme.md file to WordPress readme.txt format
if [ -f "$README_MD" ]; then
    echo "[Info] Convert readme file into WordPress format"
    $README_CONVERTER $README_MD readme.txt to-wp
fi

# Add all new files that are not set to be ignored
svn status | grep -v "^.[ \t]*\..*" | grep "^?" && svn status | grep -v "^.[ \t]*\..*" | grep "^?" | awk '{print $2}' | xargs svn add

# Remove deleted files
svn status | grep "^\!" > /dev/null 2>&1 # Check if deleted exists
if [ $? -eq 0 ]; then
    svn status | grep "^\!" | awk '{print $2}' | xargs svn delete # Remove deleted
fi


# Get aggregated commit msg and add comma in between them
COMMIT_MSG=`cat $TMPDIR/$COMMIT_MSG_FILE`
rm $TMPDIR/$COMMIT_MSG_FILE


echo
echo "[Info] Preview changes to be commited"
svn status | egrep "^ ?(A|M|D)"

read -rsp $'[ .. ] Ready to commit to SVN. Press enter...\n'
svn commit --username=$SVNUSER -m "$COMMIT_MSG"

echo "[Info] Creating new SVN tag & committing it"
svn copy . $SVNURL/tags/$LAST_TAG/ -m "Tagging $LAST_TAG for release"

echo "[Info] Removing temporary directory $SVNPATH"
rm -fr $SVNPATH/

echo "[Info] Checking our back to $GIT_BRANCH"
cd $GITPATH
git checkout $GIT_BRANCH

# Revert vendors as it was
if [ -f composer.json ]; then
    echo "[Info] Revert vendors as it was"
    cd $GITPATH

    # Revert as it was
    composer update --no-interaction --prefer-dist
fi

echo "[Info] Done"
