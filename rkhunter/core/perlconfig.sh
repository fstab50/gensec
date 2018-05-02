#!/usr/bin/env bash

#_________________________________________________________________________
#                                                                         |
#                                                                         |
#  Author:   Blake Huber                                                  |
#  Purpose:  # Perl Module Updates | rkhunter                             |
#  Location: $EC2_REPO                                                    |
#  Requires: rkhunter, prom                                               |
#  Environment Variables (required, global):                              |
#  User:     $user                                                        |
#  Output:   CLI                                                          |
#  Error:    stderr                                                       |
#  Log:  $pkg_path/logs/prom.log                                          |
#                                                                         |
#                                                                         |
#_________________________________________________________________________|


#  Verify DISTRO; install Develpment tools (AML) || build essentials, etc (installs make)
#  Install cpan if not present using distro-specific pkg mgr
#  Run perl script to configure cpan if not configured previously.  (possible solution, may want to install cpanm per the link (see below)


# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"         # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
host=$(hostname)
system=$(uname)
TMPDIR='/tmp'
perlconfig_ver='1.0'

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
            msg="${title}$prog${reset} is required and not found in the PATH. Aborting (code $E_DEPENDENCY)"
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
dep_check

# ----- begin ----- #

cd $TMPDIR
RK=$($SUDO which rkhunter)

# generate list of missing packages:
std_message "Generating list of missing perl modules. Tests will run without these; however, Adding
\t   them will increase accuracy of malware scanning tests performed by Rkhunter." "INFO"
sudo $RK --list perl  | tee /dev/tty | grep MISSING | awk '{print $1}' > $TMPDIR/perl_pkg.list

num_modules=$(cat $TMPDIR/perl_pkg.list | wc -l)

std_message "There $num_modules that can be installed on your machine to complete the Rkhunter setup." "INFO"
echo -e "\n"
read -p "     Do you want to continue?  [y]:" CHOICE
if [ -z $CHOICE ] || [ "$CHOICE" = "y" ]; then
    std_message "Begin Perl Module Update... " "INFO" $LOG_FILE
else
    std_message "Cancelled by user" "INFO" $LOG_FILE
    exit 1
fi


ARR_MODULES=$(cat $TMPDIR/perl_pkg.list)
cpan_bin=$(which cpan)

for module in ${ARR_MODULES[@]}; do
    std_message "Installing perl module $module" "INFO" $LOG_FILE
    $SUDO $cpan_bin -i $module
done

echo -e "\nRkhunter Perl Module Dependency Status\n" | indent10
# print perl module report
$SUDO rkhunter --list perl

std_message "Perl Module Config for Rkhunter ${title}Complete${bodytext}" "INFO" $LOG_FILE
exit 0
