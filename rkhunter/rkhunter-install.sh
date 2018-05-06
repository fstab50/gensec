#!/usr/bin/env bash

# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"       # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
TMPDIR='/tmp'
CALLER="$(who am i | awk '{print $1}')"                 # Username assuming root
NOW=$(date +"%Y-%m-%d %H:%M")
SCRIPT_VERSION="1.4"                                           # Installer version

# confiugration file
CONFIG_DIR="$HOME/.config/rkhunter"
CONFIG_FILE='config.json'
declare -A config_dict

# logging
LOG_DIR="$HOME/logs"
LOG_FILE="$LOG_DIR/$pkg_root.log"

# rkhunter system properties database
SYSPROP_DATABASE="/var/lib/rkhunter/db/rkhunter.dat"

# rkhunter components
VERSION='1.4.6'        # rkhunter version
URL="https://sourceforge.net/projects/rkhunter/files/rkhunter/$VERSION"
base="rkhunter-$VERSION"
gzip=$base'.tar.gz'
checksum=$gzip'.sha256'
perl_script="$pkg_path/core/configure_perl.sh"
skdet_script="$pkg_path/core/configure_skdet.sh"

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

            -d | --download     Download Rkhunter components only
            -i | --install      Install Rkhunter (full)
            -p | --perl         Install Perl Module Dependencies
           [-c | --clean        Remove installation artifacts ]
           [-C ] --configure    Rewrite local config file  <value> ]
           [-f | --force        Force (reinstall)             ]
           [-h | --help         Print this menu               ]
           [-l | --layout       Binary installation directory ]
           [-q | --quiet        Supress all output to stdout  ]
           [-r | --remove       Remove Rkhunter and components]

  ${title}OPTIONS${bodytext}
        ${title}--configure${bodytext} (string): Configure can be used as a parameter by
        itself, or with the following values:

            $ $pkg --configure ${yellow}local${bodytext}

        Manually configure a new local configuration file if used with
        --force option.  Alternatively, the diplay option can be used
        to display the local configuration file

            $ $pkg --configure ${yellow}display${bodytext}

        ${title}--force${bodytext} (parameter): Force an operation indicated by other
        command switches.
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
                -C | --configure)
                    CONFIGURATION="true"
                    if [ $2 ]; then
                        case $2 in
                            "local" | "file | ""uninstall" | "UNINSTALL" | "uninstaller" | "UNINSTALLER")
                                CONFIGURE_UNINSTALL="true"
                                shift 2
                                ;;
                            "display" | "show" | "file")
                                CONFIGURE_DISPLAY="true"
                                shift 2
                                ;;
                            "skdet" | "Skdet")
                                CONFIGURE_SKDET="true"
                                shift 2
                                ;;
                        esac
                    else
                        shift 1
                    fi
                    ;;
                -d | --download)
                    DOWNLOAD_ONLY="true"
                    shift 1
                    ;;
                -f | --force)
                    FORCE="true"
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

function configuration_file(){
    ## parse config file parameters ##
    local config_dir="$1"
    local config_file="$2"
    #
    if [ "$config_dir" = "" ] || [ "$config_file" = "" ]; then
        config_dir=$CONFIG_DIR
        config_file=$CONFIG_FILE
    fi
    if [[ ! -d "$config_dir" ]]; then
        if ! mkdir -p "$config_dir"; then
            std_error_exit "$pkg: failed to make local config directory: $config_dir. Exit" $E_DEPENDENCY
        else
            set_file_permissions $config_dir
        fi
    fi
    if [ ! -f "$config_dir/$config_file" ]; then
        return 1
    else
        if [ "$(stat -c %U $config_file 2>/dev/null)" = "root" ] && [ $CALLER ]; then
            set_file_permissions $config_file
        fi
        return 0
    fi
}

function configure_display(){
    ## displayes local conf file ##
    local config_path="$CONFIG_DIR/$CONFIG_FILE"
    if configuration_file; then
        echo -e "\n  ${BOLD}CONFIG_PATH${UNBOLD}:  ${yellow}$config_path${reset}\n"
        cat $config_path 2>/dev/null | jq .
        echo -e "\n"
    else
        std_error_exit "No local configuration found" $E_CONFIG
    fi
}

function configure_perl(){
    ## update rkhunter perl module dependencies ##
    local choice
    #
    std_message "RKhunter has a dependency on many Perl modules which may
          or may not be installed on your system." "INFO"
    read -p "    Do you want to install missing perl dependenies? [y]: " choice

    if [ $QUIET ]; then
        source $pkg_path/core/configure_perl.sh $QUIET
    else
        if [ -z $choice ] || [ "$choice" = "y" ]; then
            # perl update script
            source $pkg_path/core/configure_perl.sh $QUIET
            return 0
        else
            std_message "User cancel. Exit" "INFO"
            return 0
        fi
    fi
}

function configure_skdet(){
    ## configure dependent rootkit c module, skdet ##
    local choice
    #
    std_message "RKhunter has a dependency on a C library named ${yellow}Skdet${bodytext}
          which must be compiled and installed on your system." "INFO"
    read -p "    Do you want to install and configure Skdet? [y]: " choice

    if [ $QUIET ]; then
        source $pkg_path/core/configure_skdet.sh $QUIET
        if configure_skdet_main; then return 0; else return 1; fi
    else
        if [ -z $choice ] || [ "$choice" = "y" ]; then
            # perl update script
            source $pkg_path/core/configure_skdet.sh $QUIET
            if configure_skdet_main; then return 0; else return 1; fi
        else
            std_message "User cancel. Exit" "INFO"
            return 0
        fi
    fi
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
    if [ ! -d "$log_dir" ]; then
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

    ## configuration file path
    configuration_file $CONFIG_DIR $CONFIG_FILE

    ## check if awscli tools are configured ##
    if [[ ! -f $HOME/.aws/config ]]; then
        std_error_exit "awscli not configured, run 'aws configure'. Aborting (code $E_DEPENDENCY)" $E_DEPENDENCY
    fi

    ## check for required cli tools ##
    binary_depcheck grep jq perl sha256sum wget

    ## dependent installer modules
    if [ ! -f "$perl_script" ]; then
        std_warn "$perl_script script dependency not found"
    elif [ ! -f "$skdet_script" ]; then
        std_warn "$skdet_script script dependency not found"
    fi
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

    # store installer in case of need for uninstaller in future
    set_uninstaller "installer.sh" $layout "$CONFIG_DIR/$CONFIG_FILE"

    # test installation
    if [ $(which rkhunter 2>/dev/null) ]; then
        std_message "${title}rkhunter installed successfully${reset}" "INFO"
        CLEAN_UP="true"
    fi
}

function propupd_baseline(){
    ## create system file properites database ##
    local database="var/lib/rkhunter/db/rkhunter.dat"
    local rkh=$(which rkhunter)
    #
    if [ ! $database ]; then
        $SUDO $rkh --propupd
        SYSPROP_GENERATED_DATE=$(date -d @"$(sudo stat -c %Y $database)")
        std_message "Created system properites database ($database)" "INFO" $LOG_FILE
    else
        std_message "Existing system properites database found. Skipping creation" "INFO" $LOG_FILE
    fi
}

function unpack(){
    ## unpacks gzip and does integrity check (sha256) ##
    local result
    #
    result=$(sha256sum -c $checksum | awk '{print $2}')
    # integrity check pass; unpack
    if [ "$result" = "OK" ]; then
        gunzip $gzip
        tar -xvf $base'.tar'
        cd $base
        return 0
    else
        std_error_exit "rkhunter integrity check failure. Exit" $E_CONFIG
        return 1
    fi
}

function perl_version(){
    ## disvover installed perl binary version ##
    local perl_bin=$(which perl)
    local version_quotes
    local version
    #
    version_quotes="$($perl_bin -V:version | awk -F '=' '{print $2}' | rev | cut -c 3-10)"
    version=$(echo $version_quotes | rev | cut -c 2-10)
    echo $version
}

function set_file_permissions(){
    ## sets file permissions to calling user's id ##
    local path="$1"
    local mode="$2"
    if ! $mode; then mode=700; fi
    chmod -R $mode $path
    chown -R $CALLER:$CALLER $path
    return 0
}

function set_uninstaller(){
    ## post-install setup of uninstaller for future use ##
    local uninstall_script="$1"         # rkhunter official installer
    local layout_parameter="$2"         # layout parameter used during install
    local config_path="$3"              # path to config_file
    declare -A config_dict              # key, value dictionary
    #
    if [ -f $config_path ] && [ ! $FORCE ]; then
        std_error_exit "Configuration file ($config_path) exists, use --force to overwrite. Exit" $E_CONFIG
    else
        if unpack; then
            # copy installer to configuration directory for future use as uninstaller
            cp $uninstall_script "$CONFIG_DIR/"
        else
            std_error_exit "Unknown problem during unpacking of rkhunter component download & unpack. Exit" $E_CONFIG
        fi
        # proceed with creating configuration file
        config_dict["RKhunter-installer"]=$SCRIPT_VERSION
        config_dict["INSTALL_DATE"]=$NOW
        config_dict["PERL_VERSION"]=$(perl_version)
        config_dict["CONFIG_DIR"]=$CONFIG_DIR
        config_dict["UNINSTALL_SCRIPT_PATH"]="$CONFIG_DIR/$uninstall_script"
        config_dict["LAYOUT"]=$layout_parameter
        # system properites entry
        if [ -f $SYSPROP_DATABASE ]; then
            PROPUPD_DATE=$(date -d @"$(sudo stat -c %Y $SYSPROP_DATABASE)")
            config_dict["SYSPROP_DATABASE"]=$SYSPROP_DATABASE
            config_dict["SYSPROP_DATE"]=$PROPUPD_DATE
        fi

        # write configuration file
        array2json config_dict $config_path

        if configuration_file $CONFIG_DIR $CONFIG_FILE; then
            std_message "Uninstaller Configuration ${green}COMPLETE${reset}" "INFO" $LOG_FILE
            return 0
        else
            std_message "Problem configuring uninstaller" "WARN" $LOG_FILE
            return 1
        fi
    fi
}

function clean_up(){
    ## rmove installation files ##
    local dir="$1"
    #
    if [ $dir ]; then
        rm -fr $dir
    else
        cd $pkg_path
        std_message "Remove installation artificts" "INFO"
        for residual in $base $base'.tar' $gzip $checksum; do
            rm -fr $residual
            std_message "Removing $residual." "INFO" $LOG_FILE
        done
    fi
}


# --- main ------------------------------------------------------------


depcheck $LOG_DIR $LOG_FILE
parse_parameters $@

## operations not requiring root privileges ##

if [ "$DOWNLOAD_ONLY" ]; then
    download $gzip $checksum
    exit 0
elif [ $CONFIGURATION ] && [ $CONFIGURE_DISPLAY ]; then
    configure_display
    exit 0
fi

## operations requiring root ##

if [ $EUID -ne 0 ]; then
    std_message "You must run this installer as root. Exit" "WARN"
    exit 1
fi

if [ "$PERL_UPDATE" ]; then
    configure_perl

elif [ $CONFIGURATION ] && [ $CONFIGURE_UNINSTALL ]; then
    download $gzip $checksum
    set_uninstaller "installer.sh" $LAYOUT "$CONFIG_DIR/$CONFIG_FILE"
    clean_up

elif [ $CONFIGURATION ] && [ $CONFIGURE_SKDET ]; then
    configure_skdet
    clean_up "$TMPDIR/skdet"

elif [ $CONFIGURATION ]; then
    if ! configuration_file; then
        std_message "Config file not found, possible rkhunter installer has not run before.\n
        \tIf it has been executed run:\n
        \t\t$ sudo $pkg --configure uninstall\n
        \tto generate a local configuration file." "INFO" $LOG_FILE
        exit $E_CONFIG
    else
        std_message "${title}--configure${bodytext} must be used with one of the following options:
        \n\n\t\t* ${yellow}local${bodytext}: configure local rkhunter-installer conf file
        \n\t\t* ${yellow}skdet${bodytext}: configure skdet module dependenies
        \n\t\t* ${yellow}display${bodytext}: display local installer conf file\n" "INFO"
    fi

elif [ "$INSTALL" ]; then
    download $gzip $checksum
    install_rkhunter $LAYOUT
    configure_perl
    propupd_baseline
    configuration_file

elif [ "$UNINSTALL" ]; then
    remove_rkhunter $LAYOUT
fi

if [ "$CLEAN_UP" ]; then
    clean_up
fi

# <-- end -->
exit 0
