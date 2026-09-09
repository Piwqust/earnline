#!/usr/bin/env python3
"""Negative tests for the build-time gate; all credentials below are synthetic."""
import base64
import json
import os
import subprocess
from pathlib import Path

script = Path(__file__).with_name('validate-release-supabase-config.sh')

def token(role):
    payload = base64.urlsafe_b64encode(json.dumps({'role': role}).encode()).decode().rstrip('=')
    return 'header.' + payload + '.signature'

cases = [
    ('publishable', 'sb_publishable_test_only', 'https://example.invalid', True),
    ('anon JWT', token('anon'), 'https://example.invalid', True),
    ('service JWT', token('service_role'), 'https://example.invalid', False),
    ('secret', 'sb_secret_test_only', 'https://example.invalid', False),
    ('malformed JWT', 'x.invalid.x', 'https://example.invalid', False),
    ('wrong role', token('authenticated'), 'https://example.invalid', False),
    ('missing host', 'sb_publishable_test_only', 'https://', False),
    ('HTTP', 'sb_publishable_test_only', 'http://example.invalid', False),
    ('credentials in URL', 'sb_publishable_test_only', 'https://a:b@example.invalid', False),
]
for name, key, url, expected in cases:
    result = subprocess.run(['sh', str(script)], env={**os.environ,
        'EARNLINE_SUPABASE_PRODUCTION_URL': url,
        'EARNLINE_SUPABASE_PRODUCTION_PUBLISHABLE_KEY': key,
        'EARNLINE_PRIVACY_POLICY_URL': 'https://example.invalid/privacy'}, capture_output=True)
    assert (result.returncode == 0) == expected, name
    assert key.encode() not in result.stdout + result.stderr, 'Credential leaked in build output'
    print('PASS:', name)
