#!/bin/sh
#
# prepare.sh - create a folder and copy template files into it.
#
prog=$(basename $0)
basedir=$(dirname $(readlink -f $0))

echoerr() {
	echo "$@" >&2
}

targetdir=$1
if [ -z "$targetdir" ]; then
	echoerr "usage: $prog <foldername>"
	exit 1
fi

mode=install
if [ -d "$targetdir" ]; then
	if [ "$(readlink -f $targetdir)" = "$basedir" ]; then
		echoerr "This is the program location. Use another directory."
		exit 1
	fi
	mode=update
	echoerr "Updating install.sh and samples in the existing '$targetdir' folder..."
elif [ -e "$targetdir" ]; then
	echoerr "File '$targetdir' already exists. Use another name."
	exit 1
else
	echoerr "Creating '$targetdir' folder..."
	mkdir "$targetdir"
fi

#cp -v $basedir/install.sh $targetdir
for f in $basedir/install.sh $basedir/*.sample; do
	fbase=$(basename $f)
	if [ -f "$targetdir/$fbase" ]; then
		if diff -u $targetdir/$fbase $f >&2; then
			echoerr "$fbase: unchanged."
		else
			echoerr "$fbase: CHAGNED."
			cp -v $f $targetdir >&2
		fi
	else
		echoerr "$fbase: NEW FILE."
		cp -v $f $targetdir >&2
	fi

	if [ "$mode" = "install" -a "$fbase" != "install.sh" ]; then
		dfile=$(echo -n $fbase | sed -r 's/\.sample$//')
		cp -v $f $targetdir/$dfile >&2
	fi
done
exit 0
