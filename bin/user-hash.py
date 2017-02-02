#!/usr/bin/env python3

import sys

try:
    import bcrypt
except ImportError:
    sys.exit("Install bcrypt please")

users = {
    "circl": "myPlainTextPassword",
}

print("users = {")
for key in users:
    print("    '{}': {},".format(key, bcrypt.hashpw(users[key].encode('utf-8'), bcrypt.gensalt(16))))
print("}")

print("Either create or add the above to: web/DMAusers.py")
