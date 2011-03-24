#!/bin/bash

## Name:
##     stackmount.sh
##
## Version:
##     $Format:Git ID: (%h) %ci$
##
## Purpose:
##     Stack encfs on top of sshfs, in order to mount a remote encrypted
##     directory. This enables remote storage of sensitive data on hosts
##     which may not be fully secure, e.g. on a virtual private server.
##
## Caveats:
##     Hardlinks do not work. This is a limitation of sshfs.
##
## Usage:
##     stackmount.sh [-h|-u|-v|-d]
##
## Options:
##     -h = help
##     -u = usage
##     -v = version
##     -d = dismount
##
## Environment Variables:
##     CONFIG
##         optional configuration file
##     REMOTE_HOST
##         target hostname for SSH connections
##     HOST_MOUNTPOINT
##         directory where REMOTE_HOST will be mounted
##     REMOTE_ROOT
##         remote directory to mount onto HOST_MOUNTPOINT; this will
##         usually be the path to the user's home directory
##     DIRNAME
##         name (not path) of decrypted directory to mount locally; a
##         dot is prepended to identify the encrypted backing directory
##         on the remote host.
##     DECRYPTED_MOUNTPOINT
##         parent directory for DIRNAME, where decrypted data will be
##         mounted
##
## Errorlevels:
##     0 = Success
##     1 = Failure
##     2 = Other
##
## Copyright:
##     Copyright (c) 2011 by Todd A. Jacobs <bash_junkie@codegnome.org>
##     All Rights Reserved
##
## License:
##     Released under the GNU General Public License (GPL)
##     http://www.gnu.org/copyleft/gpl.html
##
##     This program is free software; you can redistribute it and/or
##     modify it under the terms of the GNU General Public License as
##     published by the Free Software Foundation; either version 3 of the
##     License, or (at your option) any later version.
##
##     This program is distributed in the hope that it will be useful,
##     but WITHOUT ANY WARRANTY; without even the implied warranty of
##     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
##     General Public License for more details.

######################################################################
# Initialization
######################################################################
set -e
set -o pipefail

: "${CONFIG:=$HOME/.stackmountrc}"

# Use these defaults unless overriden. Note: the config file takes
# precendence over environment variables passed on the command line,
# because config_parse() isn't called until after these values are
# initialized.
: "${REMOTE_HOST:=localhost}"
: "${HOST_MOUNTPOINT:=$HOME/mnt/$REMOTE_HOST}"
: "${REMOTE_ROOT:=$HOME}"
: "${DIRNAME:=c1e05ee6-e6f2-47af-b4fe-123d8f48666c}"
: "${DECRYPTED_MOUNTPOINT:=$HOME/mnt}"

######################################################################
# Functions
######################################################################
# Toggle the current status of the shell's pipefail option.
function toggle_pipefail {
    # Test returns true if option is set.
    if shopt -o pipefail; then
	shopt -u -o pipefail
    else
	shopt -s -o pipefail
    fi
}

# Toggle the current status of the shell's exit-on-error option.
function toggle_exit {
    # Test returns true if option is set.
    if [[ $- =~ e ]]; then
	set +e
    else
	set -e
    fi
}

# Parse the config file, but only assign to expected variables and
# prohibit further expansion of the lvalue. Note: this will prevent
# people from using $HOME, ~, or other expansions in the file--that
# seems a fair trade to avoid malicious logic like "DIRNAME=$(rm -rf
# /foo)" in the resource file.
function config_parse {
    # Store original status of exit-on-error, and then disable it to avoid
    # pipe failures when grep doesn't find a match.
    if [[ $- =~ e ]]; then
	local EXIT_ON_ERROR=$?
	toggle_exit
    fi

    [[ -r "$CONFIG" ]] || return
    VALID_PARAMS=( REMOTE_HOST
		   REMOTE_ROOT
		   HOST_MOUNTPOINT
		   DIRNAME
		   DECRYPTED_MOUNTPOINT )
    for param in ${VALID_PARAMS[*]}; do
	value=$( egrep "^${param}=[[:print:]]+" "$CONFIG" |
	         egrep -o '=.+' | sed 's/^=//' )
	[[ -n "$value" ]] && eval $param='"$value"'
    done

    # Restore exit-on-error if it was orginally set.
    [[ $EXIT_ON_ERROR -eq 0 ]] && toggle_exit
}

function sshfs_mount {
    echo Mounting $REMOTE_HOST ...
    mkdir -p "$HOST_MOUNTPOINT"
    sshfs "${REMOTE_HOST}:${REMOTE_ROOT}" \
	  "$HOST_MOUNTPOINT" \
	  -o compression=yes
}

function encfs_mount {
    echo Mounting $DECRYPTED ...
    mkdir -p "$ENCRYPTED" "$DECRYPTED"
    encfs    "$ENCRYPTED" "$DECRYPTED"
}

# Unmount FUSE filesystems in the reverse order in which they were
# mounted, and remove empty mountpoints when done.
function ordered_unmount {
    for dir in "$DECRYPTED" "$HOST_MOUNTPOINT"; do
	fusermount -u "$dir"
	rmdir "$dir"
	echo Unmounted: $dir
    done
}

# Show brief help on usage.
function ShowUsage {
    # Lines of usage information in the documentation section at the
    # top.
    local LINES=1

    # Set display options based on the number of lines.
    local TAB=$'\t'
    if [ $LINES -gt 1 ]; then
        echo "Usage: "
    else
        unset TAB
        echo -n "Usage: "
    fi

    # Display usage information parsed from this file.
    egrep -A ${LINES} "^## Usage:" "$0" | tail -n ${LINES} |
        sed -e "s/^##[[:space:]]*/$TAB/"
    exit 2
}

# Show this program's revision number.
function ShowVersion {
    perl -ne 'print "$1\n" and exit 
        if /^##\s*\$(Revision: \d+\.?\d*)/' "$0"
    exit 2
}

# Use egrep to parse and display the help comments from the top of the
# file.
function ShowHelp {
    egrep '^##([^#]|$)' $0 | sed -e 's/##//' -e 's/^ //'
    exit 2
}

# Process command-line options. Ensure that "shift $SHIFT" is called
# outside of the function to remove arguments that were handled.
options_parse () {
    unset ACTION SHIFT
    while getopts ":huvd" opt; do
	case $opt in
	    h) ShowHelp ;;
	    d) ACTION=unmount ;;
	    v) ShowVersion ;;
	    u|\?) ShowUsage ;;
	esac # End "case $opt"
    done # End "while getopts"

    # Number of processed options to shift out of the way.
    SHIFT=$(($OPTIND - 1))
}

######################################################################
# Main
######################################################################
options_parse "$@"
shift $SHIFT
config_parse

ENCRYPTED="${HOST_MOUNTPOINT}/.${DIRNAME}"
DECRYPTED="${DECRYPTED_MOUNTPOINT}/${DIRNAME}"
if [[ $ACTION == unmount ]]; then
    ordered_unmount
else
    sshfs_mount
    encfs_mount
fi
