"""
Summary:
    produces a random character string commonly used to construct
    a randomized key space in Amazon S3.  Characters illegal in
    Amazon S3 are omitted from the random string before return

Returns:
    random key, approx 90 characters
"""

import sys
from os import urandom
from base64 import b64encode


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


print(random_key())
sys.exit(0)
