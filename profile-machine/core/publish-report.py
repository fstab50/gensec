"""Summary

Author / Deployment Owner:  Blake Huber

Summary:
    Generates report to send to s3 via Amazon Simple Notification System (SNS)

    This function may be run either from AWS Lambda or a Linux cli environment,
    see README.md for instructions.

Attributes:
    IAM_CLIENT (TYPE): Description
    REGIONS (list): Description
    S3_WEB_REPORT (bool): Description
    S3_BUCKET (str): Description
    S3_WEB_REPORT_OBFUSCATE_ACCOUNT (bool): Description
    SCRIPT_OUTPUT_JSON (bool): Description
"""


import os
import sys
import json
import re
import time
import tempfile
import getopt
import inspect
import datetime

# random generation
from os import urandom
from base64 import b64encode

# aws
import boto3
from boto3.dynamodb.conditions import Key, Attr
from botocore.client import Config
from botocore.exceptions import ClientError

# pdf report gen
import pdfkit

# project
from _version import __version__
from renderers import shortAnnotation, json2html
from binary_application import pdf_binary_application
import environment
from colors import Colors
import loggers


# --- static globals -------------------------------------------------------------


# logger object
logger = loggers.getLogger(__version__)

# default region if lamda deployed, run standalone from client
DEFAULT_REGION = read_env_variable('DEFAULT_REGION')

# writeable os temp directory
TMPDIR = tempfile.gettempdir() + '/'


def random_key():
    """
    Generates random key (string) for Amazon s3 urls
    """

    illegal_chars = ['+', '&', '=', '@', '?', ':', ',']

    a = urandom(64)
    token = b64encode(a).decode('utf-8')
    randomkey = token.split('=')[0]
    for char in illegal_chars:
        clean_key = randomkey.replace(char, 'z')
        randomkey = clean_key
    return clean_key


def s3report(htmlReport, account, pdf_flag):
    """Summary

    Args:
        htmlReport (TYPE): Description

    Returns:
        TYPE: Description
    """
    url_data = []

    try:
        session = boto3.Session(profile_name=S3_PROFILE, region_name=DEFAULT_REGION)
        S3_CLIENT = session.client('s3', config=Config(signature_version='s3v4'))

    except ClientError as e:
        logger.exception("[s3report]: problem creating boto3 client (Code: %s Message: %s)" %
                         (e.response['Error']['Code'], e.response['Error']['Message']))
        raise

    baseName = "Linux Security Profile Report" + \
        str(account) + "_" + str(datetime.now().strftime('%Y%m%d_%H%M'))

    # pdf report format
    pdfName = baseName + ".pdf"
    pdfKey = random_key() + '/' + pdfName
    pdfURL = 'https://s3-' + DEFAULT_REGION + '.amazonaws.com/' + S3_BUCKET + '/' + pdfKey

    # html report format
    reportName = baseName + ".html"
    htmlKey = random_key() + '/' + reportName
    htmlURL = 'https://s3-' + DEFAULT_REGION + '.amazonaws.com/' + S3_BUCKET + '/' + htmlKey

    with tempfile.NamedTemporaryFile(delete=False) as f:
        for item in htmlReport:
            f.write(item.encode())
            f.flush()
        try:
            f.close()
            # upload html report
            S3_CLIENT.upload_file(f.name, S3_BUCKET, htmlKey)
            # put object acl to allow access 7 days via lifecycle rules
            response = S3_CLIENT.put_object_acl(
                ACL='public-read',
                Bucket=S3_BUCKET,
                Key=htmlKey
            )
            # os.unlink(f.name) -- causes exception when returning urls to caller
        except ClientError as e:
            logger.warning("Boto3 Error: Failed to upload report (html) to s3 (Code: %s Message: %s)" %
                           (e.response['Error']['Code'], e.response['Error']['Message']))
            raise
        except Exception as e:
            logger.warning("Unknown Error: Failed to upload report (html) to S3: " + str(e))
            raise

        if pdf_flag:
            try:
                with open(f.name) as f1:
                    newname = f1.name + '.html'
                    os.rename(f1.name, newname)
                    f1.close()
                    pdfkit.from_file(newname, TMPDIR + pdfName)
                # upload pdf file object
                S3_CLIENT.upload_file(TMPDIR + pdfName, S3_BUCKET, pdfKey)
                # put object acl to allow access 7 days via lifecycle rules
                response = S3_CLIENT.put_object_acl(
                    ACL='public-read',
                    Bucket=S3_BUCKET,
                    Key=pdfKey
                )
            except ClientError as e:
                logger.warning("Boto3 Error: Failed to upload report (pdf) to s3 (Code: %s Message: %s)" %
                               (e.response['Error']['Code'], e.response['Error']['Message']))
                raise
            except Exception as e:
                logger.warning("Unknown Error: Failed to upload report (pdf) to S3: " + str(e))
                raise
    #
    return (htmlURL, pdfURL)


def send_results_to_sns(account_alias, url, pdf_flag, pdf_url=''):
    """Summary

    Args:
        url (TYPE): SignedURL created by the S3 upload function

    Returns:
        TYPE: Description
    """
    # Get correct region for the TopicARN
    region = (SNS_TOPIC_ARN.split("sns:", 1)[1]).split(":", 1)[0]

    try:
        if CLI_TOOLING_AUTH:
            sns_session = boto3.Session(profile_name=SNS_PROFILE, region_name=region)
            client = sns_session.client('sns')
        else:
            client = boto3.client('sns', region_name=region)
    except ClientError as e:
        logger.exception("[send_results_to_sns]: problem creating boto3 client (Code: %s Message: %s)" %
                         (e.response['Error']['Code'], e.response['Error']['Message']))
        raise

    if pdf_flag:
        msg = 'Baseline Report (PDF):\n' + pdf_url + '\n'
    else:
        msg = 'Baseline Report (html):\n' + url + '\n'

    # msg dict for sns client
    msg_dict = {'default': msg}

    # sns publish
    client.publish(
        TopicArn=SNS_TOPIC_ARN,
        Subject="MPCAWS Account (" + str(account_alias).upper() +
        ") Security Baseline - " + str(time.strftime("%c")),
        Message=json.dumps(msg_dict),
        MessageStructure='json'
    )


url = 'http://mys3bucket/scorpio/2018-04-10/rkhunter.pdf'
msg = 'Baseline Report (html):\n' + url + '\n'
msg
msg_dict = {'default': msg}
msg_dict
import boto3
client = boto3.client('sns')
client = boto3.client('sns', region_name='us-east-1')
SNS_TOPIC_ARN = 'arn:aws:sns:us-east-1:716415911659:admin'
SUBJECT = '2018-04-11 scorpio | Lynis General Security Profile Report'
client.publish(
    TopicArn=SNS_TOPIC_ARN,
    Subject=SUBJECT,
    Message=json.dumps(msg_dict),
    MessageStructure='json'
)
