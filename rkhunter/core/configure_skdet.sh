#!/usr/bin/env bash

#_________________________________________________________________________
#                                                                         |
#  Author:      Blake Huber                                               |
#  Purpose:     # Skdet Module  | rkhunter                                |
#  Requires:    rkhunter                                                  |
#  Environmen   t Variables (required, global):                           |
#  User:        $user                                                     |
#  Output:      CLI                                                       |
#  Error:       stderr                                                    |
#  Log:         ~/logs/rkhunter-install.log                               |
#_________________________________________________________________________|


# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"       # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
host=$(hostname)
system=$(uname)
TMPDIR='/tmp'
skdet_config='1.0'
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
    binary_depcheck grep sha1sum wc
    # success
    std_logger "$pkg: dependency check satisfied." "INFO" $log_file
    #
    # <<-- end function depcheck -->>
}

function integrity_check(){
    ## integrity check of all skdet components ##
    sha1sums -c *.sha1 > results.sha1
    fail=$(cat results.txt | grep FAIL | wc -l)
    if [ "$fail" = "0" ]; then
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


root_permissions

# ----- begin ----- #

std_message "Begin skdet module configuration" "INFO"
cp -r $pkg_path/skdet $TMPDIR/
cd $TMPDIR/skdet
RK=$($SUDO which rkhunter)

tar jxvf "skdet-1.0.tar.bz2"
mv 'skdet-fix-includes.diff' skdet-1.0/

# integrity check
if ! integrity_check; then
    std_error "Skdet component integrity check fail. The following error occurred:\n" "INFO"
    echo -e "\n$(grep "FAIL" results.txt)\n"
    exit $E_DEPENDENCY
else
    std_message "Skdet component integrity check PASS" "INFO"
    cd skdet-*/
    rm -rf skdet                    # delete unpatched exec
    patch -p1 < *.diff              # apply patch
    make
    $SUDO cp skdet /usr/local/bin/        # install

    # regenerate system file properties database
    std_message "Regenerating Rkhunter system file properties db to include skdet" "INFO"
    $SUDO $RK --propupd
    # configuration status
    std_message "Skdet Module Config for Rkhunter ${green}COMPLETE${bodytext}" "INFO" $LOG_FILE
    exit 0
fi
