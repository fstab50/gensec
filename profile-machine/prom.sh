#!/usr/bin/env bash

# globals
pkg=$(basename $0)                                      # pkg (script) full name
pkg_root="$(echo $pkg | awk -F '.' '{print $1}')"       # pkg without file extention
pkg_path=$(cd $(dirname $0); pwd -P)                    # location of pkg
host=$(hostname)
system=$(uname)
TMPDIR='/tmp'
NOW=$(date +'%Y-%m-%d')
CALLER="$(who am i | awk '{print $1}')"                 # Username assuming root
VERSION='1.5'

# std functionality
source $pkg_path/core/std_functions.sh

# exit codes
source $pkg_path/core/exitcodes.sh

# color module
source $pkg_path/core/colors.sh

# Initialize ansi colors
bold='\u001b[1m'                        # ansi format
wgray='\033[38;5;95;38;5;250m'          # white-gray
title=$(echo -e ${bold}${white})
bodytext=$(echo -e ${reset}${wgray})    # main body text; set to reset for native xterm
header=$(echo -e ${bold}${orange})


# --- declarations ------------------------------------------------------------


function help_menu(){
    cat <<EOM

                ${header}Profile Machine ${title}Security Profiler${bodytext}

 ${title}DESCRIPTION${bodytext}

        Utility to run malware and vulnerability scans against a
        Linux localhost machines.  Produces reports in both log
        and pdf formats. Optionally, uploads reports to Amazon S3
        at Amazon Web Services / ${url}https://aws.amazon.com${bodytext}



  ${title}SYNOPSIS${bodytext}

            $  sh ${title}$pkg${bodytext}   <${yellow}OPTION${bodytext}>


  ${title}OPTION${bodytext}
            -l | --lynis        Lynis General Security Scan Report
            -r | --rkhunter     Rkhunter Malware Scan Report
            -q | --quiet        Supress output to stdout (use when run
                                via cron or other automated scheduler)


        Options are mutually exclusive; IE, you may run more than
        1 report at a time by providing multiple option switches
  ___________________________________________________________________

            ${title}Note${bodytext}: this script must be run as ${red}root.${bodytext}
  ___________________________________________________________________

EOM
    #
    # <-- end function put_rule_help -->
}

function parse_parameters(){
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
                -l | --lynis)
                    GENERAL_SCAN="true"
                    shift 1
                    ;;
                -q | --quiet)
                    # set quiet = true to suppress output to stdout
                    QUIET="true"
                    shift 1
                    ;;
                -r | --rkhunter)
                    MALWARE_SCAN="true"
                    shift 1
                    ;;
                *)
                    echo "unknown parameter. Exiting"
                    exit 1
                    ;;
            esac
        done
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
    local reports_dir="$3"
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

    ## local reports directory ##
    if [[ ! -d "$reports_dir" ]]; then
        if ! mkdir -p "$reports_dir"; then
            std_error_exit "$pkg: failed to make local reports directory: $reports_dir. Exit" $E_DEPENDENCY
        fi
    fi

    ## check if awscli tools are configured ##
    if [[ ! -f $HOME/.aws/config ]]; then
        std_error_exit "awscli not configured, run 'aws configure'. Aborting (code $E_DEPENDENCY)" $E_DEPENDENCY
    fi

    ## check for required cli tools ##
    binary_depcheck aws gawk grep git hostname rkhunter sed uname wkhtmltopdf

    if [ ! -f $LYNIS_DIR/lynis ] || [ ! $(which lynis) ]; then
        std_warn "$pkg: Lynis general security profiler not found. Exit"
    fi

    # success
    std_logger "$pkg: dependency check satisfied." "INFO" $log_file
    #
    # <<-- end function depcheck -->>
}

function s3_upload(){
    ## uploads report to s3 ##
    local bucket="$1"
    local path="$2"
    local object="$3"
    local region="$4"
    local random
    #
    # public, randomized path
    random=$(python3 $pkg_path/core/random-key.py)
    PUBLIC_PATH="public/$random/$object"
    aws s3 cp $object s3://$bucket/$PUBLIC_PATH --region $region --profile $PROFILE
    sleep 2     # delay to allow keyspace construction
    aws s3api put-object-acl --acl public-read --bucket $bucket \
                            --key $PUBLIC_PATH --profile $PROFILE

    # for file
    aws s3 cp $object s3://$bucket/$path/$object --region $region --profile $PROFILE
    std_message "$object uploaded to s3://$bucket/$path/$object" "INFO" $LOG_FILE
    return 0
}

function sns_publish(){
    ## mails results of scan ##
    local subj="$1"
    local msg="$2"
    local structure="$3"
    #
    if [ $structure ]; then
        aws sns publish \
            --profile $PROFILE \
            --subject "$subj" \
            --topic-arn $SNS_TOPIC \
            --region $SNS_REGION \
            --message-structure 'json' \
            --message file://"$msg"
    else
        aws sns publish \
            --profile $PROFILE \
            --subject "$subj" \
            --topic-arn $SNS_TOPIC \
            --region $SNS_REGION \
            --message file://"$msg"
    fi
    return 0
}

function file_locally(){
    ## files report to local fs location ##
    local object="$1"
    local fs_location="$2"      # complete path; includes file name
    #
    chmod 755 $object
    mv $object $fs_location
    chown $CALLER:$CALLER $fs_location
    std_message "Filed target:\t${title}$object${reset}\n
    \tTo location:\t${title}$fs_location${reset}" "INFO" $LOG_FILE
    return 0
}

function create_sns_msg(){
    ## create file which forms msg sent via sns ##
    local path="$1"
    #
    cat <<EOM > $SNS_REPORT
    {
        "default": "SNS Security Report Upload\n\n$path\n"
    }
EOM
}

function clean_up(){
    ## remove fs objects ##
    rm $@ || true
    return 0
}

function exec_rkhunter(){
    ## execute rkhunter malware scanner ##
    local trigger="$1"
    local report="$NOW-($host)-rkhunter.pdf"
    local date=$(date)
    local hostname=$(hostname)
    #
    if [ ! $trigger ]; then return 0; fi
    ## update security job ##
    std_message "Updating rkhunter malware scanner on $host" "INFO" $LOG_FILE
    rkhunter --update
    ## run rkhunter ##
    std_message "Running rkhunter malware scan against $host" "INFO" $LOG_FILE
    if [ "$QUIET" ]; then
        rkhunter --check --sk | $pkg_path/core/ansi2html.sh --palette=linux > $TMPDIR/rkhunter.html
    else
        rkhunter --check --sk  --enable all --disable none | tee /dev/tty | $pkg_path/core/ansi2html.sh --palette=linux > $TMPDIR/rkhunter.html
    fi
    ## create report ##
    cd $TMPDIR
    # header
    cp $pkg_path/html/header-r.html $TMPDIR/header-r.html
    sed -i "s/DATE/$date/g" $TMPDIR/header-r.html
    sed -i "s/HOSTNAME/$hostname/g" $TMPDIR/header-r.html
    # footer
    cp $pkg_path/html/footer-r.html $TMPDIR/footer-r.html
    sed -i "s/FILENAME/$report/g" $TMPDIR/footer-r.html
    # pdf construction
    wkhtmltopdf --header-html $TMPDIR/header-r.html  \
                --footer-html $TMPDIR/footer-r.html $TMPDIR/rkhunter.html $TMPDIR/$report
    ## process output ##
    s3_upload "$S3_BUCKET" "$host" "$report" "$S3_REGION"
    file_locally "$TMPDIR/$report" "$LOCAL_REPORTS/$report"
    create_sns_msg "https://s3.$S3_REGION.amazonaws.com/$S3_BUCKET/$PUBLIC_PATH"
    sns_publish "$NOW ($host) | rkhunter malware scan" $SNS_REPORT "json"
    clean_up "$SNS_REPORT"
    return 0
}

function exec_lynis(){
    ## execute lynis security profile ##
    local trigger="$1"
    local report="$NOW-($host)-lynis-security-scan.pdf"
    local date=$(date)
    local hostname=$(hostname)
    #
    if [ ! $trigger ]; then return 0; fi
    ## update security job ##
    cd $LYNIS_DIR
    std_message "Updating lynis repository" "INFO" $LOG_FILE
    git pull
    std_message "START Lynis General Security Profiler" "INFO" $LOG_FILE
    # run security job ##
    if [ $QUIET ]; then
        ./lynis audit system | $pkg_path/core/ansi2html.sh --bg=dark --palette=linux > $TMPDIR/lynis.html
    else
        ./lynis audit system | tee /dev/tty | $pkg_path/core/ansi2html.sh --bg=dark --palette=linux > $TMPDIR/lynis.html
    fi
    ## create report ##
    cd $TMPDIR
    date=$(date)
    # header
    cp $pkg_path/html/header-l.html $TMPDIR/header-l.html
    sed -i "s/DATE/$date/g" $TMPDIR/header-l.html
    sed -i "s/HOSTNAME/$hostname/g" $TMPDIR/header-l.html
    # footer
    cp $pkg_path/html/footer-l.html $TMPDIR/footer-l.html
    sed -i "s/FILENAME/$report/g" $TMPDIR/footer-l.html
    # pdf construction
    wkhtmltopdf --header-html $TMPDIR/header-l.html  \
                --footer-html $TMPDIR/footer-l.html $TMPDIR/lynis.html $TMPDIR/$report

    ## process output ##
    s3_upload "$S3_BUCKET" "$host" "$report" "$S3_REGION"
    file_locally "$TMPDIR/$report" "$LOCAL_REPORTS/$report"
    create_sns_msg "https://s3.$S3_REGION.amazonaws.com/$S3_BUCKET/$PUBLIC_PATH"
    sns_publish "$NOW ($host) | Lynis Security Profiler" $SNS_REPORT "json"
    echo -e "\n---------------------------------------------------------------" >> $LOG_DIR/lynis.log
    echo -e "|          $NOW Lyis Security Profile START        |" >> $LOG_DIR/lynis.log
    echo -e "---------------------------------------------------------------\n" >> $LOG_DIR/lynis.log
    cat /var/log/lynis.log >> $LOG_DIR/lynis.log
    clean_up "$SNS_REPORT"
    return 0
}

function configuration_file(){
    ## parse config file parameters ##
    binary_depcheck "jq"    # json parser needed for this function
    # parse config parameters
    CONFIG_DIR="$HOME/.config/$pkg_root"
    CONFIG_FILE='configuration.json'
    if [ ! -f $CONFIG_DIR/$CONFIG_FILE ]; then
        std_message "Configuration directory or config file not found. Exit" "WARN"
        exit 1
    fi

    # lynis
    LYNIS_DIR=$(jq -r .configuration.LYNIS_DIR $CONFIG_DIR/$CONFIG_FILE)

    # aws
    PROFILE=$(jq -r .configuration.AWS_PROFILE $CONFIG_DIR/$CONFIG_FILE)
    S3_BUCKET=$(jq -r .configuration.S3_BUCKET $CONFIG_DIR/$CONFIG_FILE)
    S3_REGION=$(jq -r .configuration.S3_REGION $CONFIG_DIR/$CONFIG_FILE)
    SNS_REGION=$(jq -r .configuration.SNS_REGION $CONFIG_DIR/$CONFIG_FILE)
    SNS_TOPIC=$(jq -r .configuration.SNS_TOPIC $CONFIG_DIR/$CONFIG_FILE)
    SNS_REPORT="$TMPDIR/sns_file.json"

    # local fs vars
    LOCAL_REPORTS="$(jq -r .configuration.REPORTS_ROOT $CONFIG_DIR/$CONFIG_FILE)/$host"
    LOG_DIR=$(jq -r .configuration.LOG_DIR $CONFIG_DIR/$CONFIG_FILE)
    LOG_FILE="$LOG_DIR/$pkg_root.log"
    return 0
}

# ---  main  ------------------------------------------------------------------


if ! configuration_file; then
    std_error_exit "Problem parsing configuration file parameters. Exit" $E_DEPENDENCY
fi

depcheck $LOG_DIR $LOG_FILE $LOCAL_REPORTS

parse_parameters $@

if [ $EUID -ne 0 ]; then
    std_message "You must run this installer as root. Exit" "WARN" $LOG_FILE
    exit 1
fi

# malware scanner rkhunter
exec_rkhunter $MALWARE_SCAN

# security profile using lynis
exec_lynis $GENERAL_SCAN

# <-- end -->
exit 0
