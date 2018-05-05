#!/usr/bin/env bash

# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"       # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
TMPDIR='/tmp'
CALLER="$(who am i | awk '{print $1}')"                 # Username assuming root
NOW=$(date +%s)
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/$pkg_root.log"
SCRIPT_VER="1.3"

# rkhunter components
VERSION='1.4.6'        # rkhunter version
URL="https://sourceforge.net/projects/rkhunter/files/rkhunter/$VERSION"
base="rkhunter-$VERSION"
gzip=$base'.tar.gz'
checksum=$gzip'.sha256'

# references for standard functionality
source $pkg_path/core/std_functions.sh

# exit codes
source $pkg_path/core/exitcodes.sh

# formmating
source $pkg_path/core/colors.sh

# special colors
ORANGE='\033[0;33m'
header=$(echo -e ${bold}${brightred})

# --- declarations ------------------------------------------------------------

# indent
function indent02() { sed 's/^/  /'; }
function indent10() { sed 's/^/          /'; }

function help_menu(){
    cat <<EOM

                    ${header}Rkhunter Installer${bodytext}

  ${title}DESCRIPTION${bodytext}

        Utility to install latest version of rkhunter on local
        machine.  For questions, see the Rkhunter official
        project site at ${url}http://rkhunter.sourceforge.net${bodytext}


  ${title}SYNOPSIS${bodytext}

        $  sh ${title}$pkg${bodytext}   <${yellow}OPTION${reset}>


  ${title}OPTIONS${bodytext}
            -d | --download     Download Rkhunter components only
            -i | --install      Install Rkhunter (full)
            -p | --perl         Install Perl Module Dependencies
           [-c | --clean        Remove installation artifacts ]
           [-h | --help         Print this menu               ]
           [-l | --layout       Binary installation directory ]
           [-q | --quiet        Supress all output to stdout  ]
           [-r | --remove       Remove Rkhunter and components]

  ___________________________________________________________________

            ${yellow}Note${bodytext}: this installer must be run as root.
  ___________________________________________________________________

EOM
    #
    # <-- end function put_rule_help -->
}

function parse_parameters() {
    if [[ ! "$@" ]]; then
        help_menu
        exit 0
    else
        while [ $# -gt 0 ]; do
            case $1 in
                -h | --help)
                    help_menu
                    shift 1
                    exit 0
                    ;;
                -c | --clean)
                    CLEAN_UP="true"
                    shift 1
                    ;;
                -d | --download)
                    DOWNLOAD_ONLY="true"
                    shift 1
                    ;;
                -l | --layout)
                    if [ $2 ]; then
                        LAYOUT="$2"
                    else
                        std_error_exit "You must supply a path with the layout parameter. Example:
                        \n\t\t$ sh rkhunter-install.sh --layout /usr" 1
                    fi
                    shift 2
                    ;;
                -i | --install)
                    INSTALL="true"
                    shift 1
                    ;;
                -p | --perl)
                    PERL_UPDATE="true"
                    shift 1
                    ;;
                -q | --quiet)
                    QUIET="true"
                    shift 1
                    ;;
                -r | --remove)
                    UNINSTALL="true"
                    shift 1
                    ;;
                *)
                    echo "unknown parameter. Exiting"
                    exit 1
                    ;;
            esac
        done
    fi
    # set default for layout
    if [ ! $LAYOUT ]; then
        LAYOUT="default"
    fi
    #
    # <-- end function parse_parameters -->
}

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
    else
        if [ "$(stat -c %U $log_file)" = "root" ] && [ $CALLER ]; then
            chown $CALLER:$CALLER $log_file
        fi
    fi

    ## check if awscli tools are configured ##
    if [[ ! -f $HOME/.aws/config ]]; then
        std_error_exit "awscli not configured, run 'aws configure'. Aborting (code $E_DEPENDENCY)" $E_DEPENDENCY
    fi

    ## check for required cli tools ##
    binary_depcheck grep jq sha256sum wget perl

    # success
    std_logger "$pkg: all dependencies satisfied." "INFO" $log_file

    #
    # <<-- end function depcheck -->>
}

function download(){
    ## download rkhunter required components
    local file1="$1"
    local file2="$2"
    #
    for file in $file1 $file2; do
        if [ -f $file ]; then
            std_message "Pre-existing ${title}$file${reset} file found -- downloaded successfully" "INFO"
        else
            wget $URL/$file
            if [ -f $file ]; then
                std_message "${title}$file${reset} downloaded successfully" "INFO"
            else
                std_message "${title}$file${reset} download ${red}FAIL${reset}" "WARN"
            fi
        fi
    done
    return 0
}

function install_rkhunter(){
    ## dynamic malware scanner ##
    local layout="$1"
    local result
    #
    result=$(sha256sum -c $checksum | awk '{print $2}')

    if [ "$result" = "OK" ]; then
        gunzip $gzip
        tar -xvf $base'.tar'
        cd $base
        sh installer.sh --layout $layout --install
    else
        std_message "rkhunter integrity check failure" "WARN"
    fi
    # test installation
    if [ $(which rkhunter 2>/dev/null) ]; then
        std_message "${title}rkhunter installed successfully${reset}" "INFO"
        CLEAN_UP="true"
    fi
}

function perl_modules(){
    ## update rkhunter perl module dependencies ##
    local choice
    #
    std_message "RKhunter has a dependency on many Perl modules which may
          or may not be installed on your system." "INFO"
    read -p "    Do you want to install missing perl dependenies? [y]: " choice

    if [ -z $choice ] || [ "$choice" = "y" ]; then
        # perl update script
        source $pkg_path/core/perlconfig.sh $QUIET
        return 0
    else
        std_message "User cancel. Exit" "INFO"
    fi
}

function propupd_baseline(){
    ## create system file properites database ##
    local database="var/lib/rkhunter/db/rkhunter.dat"
    local rkh=$(which rkhunter)
    #
    if [ ! $database ]; then
        $SUDO $rkh --propupd
        std_message "Created system properites database ($database)" "INFO" $LOG_FILE
    else
        std_message "Existing system properites database found. Skipping creation" "INFO" $LOG_FILE
    fi
}

function clean_up(){
    ## rmove installation files ##
    cd $pkg_path
    std_message "Remove installation artificts" "INFO"
    for residual in $base $base'.tar' $gzip $checksum; do
        rm -fr $residual
        std_message "Removing $residual." "INFO" "pprint"
    done
}


# --- main ------------------------------------------------------------


depcheck $LOG_DIR $LOG_FILE
parse_parameters $@

if [ $EUID -ne 0 ]; then
    std_message "You must run this installer as root. Exit" "WARN"
    exit 1
fi

if [ "$DOWNLOAD_ONLY" ]; then
    download $gzip $checksum

elif [ "$PERL_UPDATE" ]; then
    perl_modules

elif [ "$INSTALL" ]; then
    download $gzip $checksum
    install_rkhunter $LAYOUT
    perl_modules
    propupd_baseline
fi

if [ "$CLEAN_UP" ]; then
    clean_up
fi

# <-- end -->
exit 0
