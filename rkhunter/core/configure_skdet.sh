#!/usr/bin/env bash

#_________________________________________________________________________
#                                                                         |
#  Author:   Blake Huber                                                  |
#  Purpose:  # Skdet Module  | rkhunter                                   |
#  Requires: rkhunter, prom                                               |
#  Environment Variables (required, global):                              |
#  User:     $user                                                        |
#  Output:   CLI                                                          |
#  Error:    stderr                                                       |
#  Log:  $pkg_path/logs/prom.log                                          |
#_________________________________________________________________________|



# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"       # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
host=$(hostname)
system=$(uname)
TMPDIR='/tmp'
perlconf_version='1.2'
QUIET="$1"                                              # Supress output to stdout; from caller

# arrays
declare -a ARR_MODULES

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
    binary_depcheck cpan perl rkhunter
    # success
    std_logger "$pkg: dependency check satisfied." "INFO" $log_file
    #
    # <<-- end function depcheck -->>
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
depcheck $LOG_DIR $LOG_FILE

# ----- begin ----- #

cd $TMPDIR
RK=$($SUDO which rkhunter)

# generate list of missing packages:
std_message "Generating list of missing ${yellow}Perl${reset} Modules. Scan Tests will run
\t      without these; however, Adding them will increase accuracy
\t      of malware scanning tests performed by Rkhunter." "INFO"

if [ $QUIET ]; then
    sudo $RK --list perl 2>/dev/null  | tail -n +3 | grep MISSING | awk '{print $1}' > $TMPDIR/perl_pkg.list
    std_logger "Missing perl modules list:\n $(cat $TMPDIR/perl_pkg.list)" "INFO" $LOG_FILE
else
    echo -e "\n${title}Rkhunter${bodytext} ${yellow}Perl${reset} Module Dependency Status\n" | indent04
    sudo $RK --list perl 2>/dev/null  | tail -n +3 | tee /dev/tty | grep MISSING | awk '{print $1}' > $TMPDIR/perl_pkg.list
fi

# perl configuration status
std_message "Skdet Module Config for Rkhunter ${green}COMPLETE${bodytext}" "INFO" $LOG_FILE
exit 0
