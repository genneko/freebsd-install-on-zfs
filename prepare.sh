#!/bin/sh
#
# prepare.sh - create a folder and copy template files into it.
#
prog=$(basename $0)
basedir=$(dirname $(readlink -f $0))

targetdir=$1
if [ -z "$targetdir" ]; then
	echo "usage: $prog <foldername>"
	exit 1
fi

if [ -d "$targetdir" ]; then
	echo "Folder '$targetdir' already exists."
	exit 1
elif [ -e "$targetdir" ]; then
	echo "File '$targetdir' already exists."
	exit 1
fi

mkdir "$targetdir"
cp -v $basedir/install.sh $targetdir
for f in $basedir/*.sample; do
	cp -v $f $targetdir/$(echo -n $(basename $f) | sed -r 's/\.sample$//')
done
exit 0
