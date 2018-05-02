#!/usr/bin/env bash

# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"       # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
TMPDIR='/tmp'
NOW=$(date +%s)
LOG_FILE="$LOG_DIR/$pkg_root.log"
SCRIPT_VER="1.3"

# rkhunter components
VERSION='1.4.6'        # rkhunter version
URL="https://sourceforge.net/projects/rkhunter/files/rkhunter/$VERSION"
base="rkhunter-$VERSION"
gzip=$base'.tar.gz'
checksum=$gzip'.sha256'

source $pkg_path/core/colors.sh

# formatting
ORANGE='\033[0;33m'
RED=$(tput setaf 1)
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
            -d | --download     Download rkhunter components only
            -i | --install      Install rkhunter (full)
           [-l | --layout       Binary installation directory ]
           [-r | --remove       Remove installation artifacts ]

  ___________________________________________________________________

            ${yellow}Note${bodytext}: this installer must be run as root.
  ___________________________________________________________________

EOM
    #
    # <-- end function put_rule_help -->
}

function parse_parameters() {
    if [ ! $@ ]; then
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
                -r | --remove)
                    CLEAN_UP="true"
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

function std_logger(){
    local msg="$1"
    local prefix="$2"
    local log_file="$3"
    #
    if [ ! $prefix ]; then
        prefix="INFO"
    fi
    if [ ! -f $log_file ]; then
        # create log file
        touch $log_file
        if [ ! -f $log_file ]; then
            echo "[$prefix]: $pkg ($VERSION): failure to call std_logger, $log_file location not writeable"
            exit $E_DIR
        fi
    else
        echo "$(date +'%Y-%m-%d %T') $host - $pkg - $VERSION - [$prefix]: $msg" >> "$log_file"
    fi
}

function std_error(){
    local msg="$1"
    #std_logger "[ERROR]: $msg"
    echo -e "\n${yellow}[ ${red}ERROR${yellow} ]$reset  $msg\n" | indent04
}

function std_error_exit(){
    local msg="$1"
    local status="$2"
    std_error "$msg"
    exit $status
}

function std_message(){
    local msg="$1"
    local prefix="$2"
    local format="$3"
    #
    [[ $quiet ]] && return
    shift
    pref="----"
    if [[ $1 ]]; then
        pref="${1:0:5}"
        shift
    fi
    if [ $format ]; then
        echo -e "${yellow}[ $cyan$pref$yellow ]$reset  $msg" | indent04
    else
        echo -e "\n${yellow}[ $cyan$pref$yellow ]$reset  $msg\n" | indent04
    fi
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
    fi

    ## check if awscli tools are configured ##
    if [[ ! -f $HOME/.aws/config ]]; then
        std_error_exit "awscli not configured, run 'aws configure'. Aborting (code $E_DEPENDENCY)" $E_DEPENDENCY
    fi

    ## check for required cli tools ##
    binary_depcheck aws grep sha256sum wget

    # success
    std_logger "$pkg: dependency check satisfied." "INFO" $log_file

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

parse_parameters $@

if [ $EUID -ne 0 ]; then
    std_message "You must run this installer as root. Exit" "WARN"
    exit 1
fi

if [ $DOWNLOAD_ONLY ]; then
    download $gzip $checksum
elif [ $INSTALL ]; then
    download $gzip $checksum
    install_rkhunter $LAYOUT
fi

if [ $CLEAN_UP ]; then
    clean_up
fi

# <-- end -->
exit 0
