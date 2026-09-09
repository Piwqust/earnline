#!/bin/sh
set -eu

# Inspect only public configuration; never print a supplied credential.
/usr/bin/python3 - <<'PYTHON'
import base64
import json
import os
import re
import sys
from urllib.parse import urlsplit


def fail(message):
    print("error: " + message)
    sys.exit(1)


for name in ("EARNLINE_SUPABASE_PRODUCTION_URL", "EARNLINE_PRIVACY_POLICY_URL"):
    raw = os.environ.get(name, "").strip()
    try:
        url = urlsplit(raw)
        valid = (url.scheme == "https" and bool(url.hostname)
                 and not url.username and not url.password
                 and not any(c.isspace() for c in raw) and url.port != 0)
    except ValueError:
        valid = False
    if not valid:
        fail("Release requires " + name + " with a valid HTTPS host.")

key = os.environ.get("EARNLINE_SUPABASE_PRODUCTION_PUBLISHABLE_KEY", "").strip()
if re.fullmatch(r"sb_publishable_[A-Za-z0-9_-]+", key):
    sys.exit(0)
try:
    parts = key.split(".")
    if len(parts) != 3 or not all(parts):
        raise ValueError()
    payload = json.loads(base64.urlsafe_b64decode(parts[1] + "=" * (-len(parts[1]) % 4)))
    if payload.get("role") != "anon":
        raise ValueError()
except (ValueError, TypeError, AttributeError):
    fail("Release requires a public Supabase publishable key or anon JWT; server keys are forbidden.")
PYTHON
