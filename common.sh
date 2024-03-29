#!/bin/bash
# SPDX-License-Identifier: Apache-2.0
# Copyright (C) Semihalf, 2022
# Author: Marek Maślanka <mm@semihalf.com>
#
# Common functions

logDebug()
{
	[[ "$LOG_LEVEL" > 0 ]] && return
	echo "[DEBUG] $1"
}
export -f logDebug

logInfo()
{
	[[ "$LOG_LEVEL" > 1 ]] && return
	echo "$1"
}
export -f logInfo

logWarn()
{
	[[ "$LOG_LEVEL" > 2 ]] && return
	echo -e "$ORANGE$1$NC"
}
export -f logWarn

logErr()
{
	echo -e "$1" >&2
}
export -f logErr

logFatal()
{
	echo -e "$RED$1$NC" >&2
}
export -f logFatal

filenameNoExt()
{
	[[ $# = 0 ]] && set -- "$(cat -)" "${@:2}"
	local basename=`basename "$1"`
	echo ${basename%.*}
}
export -f filenameNoExt

generateSymbols()
{
	local kofile=$1
	local path=`dirname $kofile`
	path=${path#*$MODULES_DIR}
	local outfile="$SYMBOLS_DIR/$path/"
	mkdir -p "$outfile"
	outfile+=$(filenameNoExt "$kofile")
	nm -f posix "$kofile" | cut -d ' ' -f 1,2 > "$outfile"
}
export -f generateSymbols

findObjWithSymbol()
{
	local sym=$1
	local srcfile=$2

	#TODO: For module objects try to find symbol in the same module
	#TODO: Consider checking type of the symbol
	grep -q "\b$sym\b" "$SYSTEM_MAP" && { echo vmlinux; return $NO_ERROR; }

	local out=`grep -lr "\b$sym\b" $SYMBOLS_DIR`
	[ "$out" != "" ] && { echo $(filenameNoExt "$out"); return $NO_ERROR; }

	local srcpath=$SOURCE_DIR/
	local modulespath=$MODULES_DIR/
	srcpath+=`dirname $srcfile`
	modulespath+=`dirname $srcfile`
	while true; do
		local files=`find "$modulespath" -maxdepth 1 -type f -name "*.ko"`
		if [ "$files" != "" ]; then
			while read -r file; do
				symfile=$(filenameNoExt "$file")
				[ -f "$SYMBOLS_DIR/$symfile" ] && continue
				generateSymbols $file
			done <<< "$files"

			out=`grep -lr "\b$sym\b" $SYMBOLS_DIR`
			[ "$out" != "" ] && { echo $(filenameNoExt "$out"); return $NO_ERROR; }
		fi
		[ -f "$srcpath/Kconfig" ] && break
		srcpath+="/.."
		modulespath+="/.."
	done

	exit $ERROR_CANT_FIND_SYMBOL
}
export -f findObjWithSymbol

getKernelVersion()
{
	grep -r UTS_VERSION "$LINUX_HEADERS/include/generated/" | \
	sed -n "s/.*UTS_VERSION\ \"\(.\+\)\"$/\1/p"

}
export -f getKernelVersion

getKernelReleaseVersion()
{
	grep -r UTS_RELEASE "$LINUX_HEADERS/include/generated/" | \
	sed -n "s/.*UTS_RELEASE\ \"\(.\+\)\"$/\1/p"
}
export -f getKernelReleaseVersion

# find modified files
modifiedFiles()
{
	if [[ "$CASHED_MODIFIED_FILES" ]]; then
		echo "$CASHED_MODIFIED_FILES"
		return
	fi

	if [ ! "$KERN_SRC_INSTALL_DIR" ]; then
		git -C "$workdir" diff --name-only | grep -E ".+\.[ch]$"
		return
	fi

	cd "$SOURCE_DIR/"
	local files=`find . -type f -name "*.c" -o -name "*.h"`
	cd $OLDPWD
	while read -r file; do
		if [ "$SOURCE_DIR/$file" -nt "$KERN_SRC_INSTALL_DIR/$file" ]; then
			cmp --silent "$SOURCE_DIR/$file" "$KERN_SRC_INSTALL_DIR/$file" || \
			echo "${file:2}"
		fi
	done <<< "$files"
}
export -f modifiedFiles

generateModuleName()
{
	local file=$1
	local crc=`cksum <<< "$file" | cut -d' ' -f1`
	crc=$( printf "%08x" $crc );
	local module="$(filenameNoExt $file)"
	local modulename=${module/-/_}
	echo deku_${crc}_$modulename
}
export -f generateModuleName

generateDEKUHash()
{
	local files=`
	find command -type f -name "*";				\
	find deploy -type f -name "*";				\
	find integration -type f -name "*";			\
	find . -maxdepth 1 -type f -name "*.sh";	\
	find . -maxdepth 1 -type f -name "*.c";		\
	echo ./deku									\
	`
	local sum=
	while read -r file; do
		sum+=`md5sum $file`
	done <<< "$files"
	sum=`md5sum <<< "$sum" | cut -d" " -f1`
	echo "$sum"
}
export -f generateDEKUHash
