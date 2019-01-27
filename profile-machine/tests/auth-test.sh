function authenticated(){
    ## validates authentication using iam user or role ##
    local profilename="$1"
    local response
    local awscli=$(which aws)
    #
    response=$($awscli sts get-caller-identity --profile $profilename 2>&1)
    if [ "$(echo $response | grep Invalid)" ]; then
        std_message "The IAM profile provided ($profilename) failed to authenticate to AWS. Exit (Code $E_AUTH)" "AUTH"
        return 1
    elif [ "$(echo $response | grep found)" ]; then
        std_message "The IAM user or role ($profilename) cannot be found in your local awscli config. Exit (Code $E_BADARG)" "AUTH"
        return 1
    elif [ "$(echo $response | grep Expired)" ]; then
        std_message "The sts temporary credentials for the role provided ($profilename) have expired. Exit (Code $E_AUTH)" "INFO"
        return 1
    else
        return 0
    fi
}

awscli=$(which aws)

echo "Contents of which aws: $awscli"

if authenticated "$1"; then
    echo "profilename $1 is authenticated to aws"
else
    echo "FAIL:  profile $1 failed authentication"
fi
