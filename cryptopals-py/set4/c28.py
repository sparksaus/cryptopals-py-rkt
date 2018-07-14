# Challenge 28
## Implement a SHA-1 keyed MAC
import os

key = os.urandom(16)
### Find a SHA-1 implementation in the language you code in.
### Write a function to authenticate a message under a secret key
### by using a secret-prefix MAC, which is simply:
###    SHA1(key || message)
### Verify that you cannot tamper with the message without breaking the MAC
### you've produced, and that you can't produce a new MAC without knowing
### the secret key.
def hmac_sha1(message):
    return SHA1.digest(key + message)
