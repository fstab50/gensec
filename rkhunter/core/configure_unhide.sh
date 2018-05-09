#!/usr/bin/env bash

#_________________________________________________________________________
#                                                                         |
#  Author:      Blake Huber                                               |
#  Purpose:     # Unhide Module  | rkhunter                               |
#  Requires:    rkhunter                                                  |
#  Environment Variables (required, global):                              |
#               N/A                                                       |
#  User:        root                                                      |
#  Output:      CLI                                                       |
#  Error:       stderr                                                    |
#  Log:         ~/logs/rkhunter-install.log                               |
#                                                                         |
#  Notes:       Install unhide binary prior to rkhunter (if possilble)    |
#               on a new OS not yet connected to the Internet             |
#_________________________________________________________________________|


# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"       # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
host=$(hostname)
system=$(uname)
TMPDIR='/tmp'
unhide_config='1.0'
QUIET="$1"                                              # Supress output to stdout; from caller


# logging
LOG_DIR="$HOME/logs"
if [ ! $LOG_FILE ]; then LOG_FILE="$LOG_DIR/$pkg_root.log"; fi

# source dependencies
if [ $(echo $pkg_path | grep core) ]; then
    # called standalone
    source $pkg_path/colors.sh
    source $pkg_path/exitcodes.sh
    source $pkg_path/std_functions.sh
else
    # called by another script
    source $pkg_path/core/colors.sh
    source $pkg_path/core/exitcodes.sh
    source $pkg_path/core/std_functions.sh
fi


# ---  declarations  -------------------------------------------------------------------------------


function binary_depcheck(){
    ## validate binary dependencies installed
    local check_list=( "$@" )
    local msg
    #
    for prog in "${check_list[@]}"; do
        if ! type "$prog" > /dev/null 2>&1; then
            msg="${title}$prog${bodytext} is required and not found in the PATH. Aborting (code $E_DEPENDENCY)"
            std_error_exit "$msg" $E_DEPENDENCY
        fi
    done
    #
    # <<-- end function binary_depcheck -->>
}

function depcheck(){
    ## validate cis report dependencies ##
    local log_dir="$1"
    local log_file="$2"
    local msg
    #
    ## test default shell ##
    if [ ! -n "$BASH" ]; then
        # shell other than bash
        msg="Default shell appears to be something other than bash. Please rerun with bash. Aborting (code $E_BADSHELL)"
        std_error_exit "$msg" $E_BADSHELL
    fi
    ## logging prerequisites  ##
    if [[ ! -d "$log_dir" ]]; then
        if ! mkdir -p "$log_dir"; then
            std_error_exit "$pkg: failed to make log directory: $log_dir. Exit" $E_DEPENDENCY
        fi
    fi
    if [ ! -f $log_file ]; then
        if ! touch $log_file 2>/dev/null; then
            std_error_exit "$pkg: failed to seed log file: $log_file. Exit" $E_DEPENDENCY
        fi
    fi
    ## check for required cli tools ##
    binary_depcheck cat grep tar gcc
    # success
    std_logger "$pkg: dependency check satisfied." "INFO" $log_file
    #
    # <<-- end function depcheck -->>
}

function is_installed(){
    ## validate if binary previously installed  ##
    local binary="$1"
    local location=$(which $binary)
    if [ $location ]; then
        std_message "$binary is already compiled and installed:  $location" "INFO" $LOG_FILE
        return 0
    else
        return 1
    fi
}


function integrity_check(){
    ## integrity check of all skdet components ##
    sha1sum -c *.sha1 > results.txt
    fail=$(cat results.txt | grep FAIL | wc -l)
    if [ "$fail" = "0" ]; then
        return 0
    else
        return 1
    fi
}

function post_install_test(){
    ## execute skdet binary ##
    if [ "$(unhide | grep Copyright)" ]; then
        return 0
    else
        return 1
    fi
}

function root_permissions(){
    ## validates required root privileges ##
    if [ $EUID -ne 0 ]; then
        std_message "You must run this installer as root or access root privileges via sudo. Exit" "WARN"
        read -p "    Continue? [quit]: " CHOICE
        if [ -z $CHOICE ] || [ "$CHOICE" = "quit" ] || [ "$CHOICE" = "q" ]; then
            std_message "Re-run as root or execute with sudo:
            \n\t\t$ sudo sh $pkg" "INFO"
            exit 0
        else
            SUDO="sudo"
        fi
    else
        SUDO=''
    fi
    return 0
}


# --- main ----------------------------------------------------------------------------------------


function configure_unhide_main(){
    # verify root privs & script deps
    root_permissions
    depcheck $LOG_DIR $LOG_FILE

    # check if installed
    if is_installed "unhide"; then
        std_logger "Exit configure - unhide already installed" "INFO" $LOG_FILE
        exit 0
    else
        std_message "Begin Unhide module configuration" "INFO" $LOG_FILE
        sleep 2

        cp -r $pkg_path/unhide $pkg_path/core $TMPDIR/
        cd $TMPDIR/unhide
        RK=$($SUDO which rkhunter)

        std_message "Unpacking tgz archive" "INFO" $LOG_FILE
        tar xvf unhide*.tgz

        std_message "Compiling unhide binary" "INFO" $LOG_FILE
        cd unhide-*
        gcc -Wall -O2 --static -pthread unhide-linux*.c unhide-output.c -o unhide-linux
        gcc -Wall -O2 --static unhide-tcp.c unhide-tcp-fast.c unhide-output.c -o unhide-tcp

       std_message "Installing unhide compiled binary" "INFO" $LOG_FILE
       cp 'unhide-linux' /usr/local/bin/ && cp 'unhide-tcp' /usr/local/bin/
       ln -s /usr/local/bin/unhide-linux /usr/local/bin/unhide

        # configuration status
        if post_install_test; then
            std_message "Unhide C library build for Rkhunter ${green}COMPLETE${bodytext}" "INFO" $LOG_FILE
            return 0
        else
            std_error "Unhide post-install test Fail" $E_CONFIG
            return 1
        fi
    fi
}
