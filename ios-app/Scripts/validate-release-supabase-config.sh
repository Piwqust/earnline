#!/bin/sh
set -eu

case "${EARNLINE_SUPABASE_PRODUCTION_URL:-}" in
  https://*) ;;
  *)
    echo "error: Release requires EARNLINE_SUPABASE_PRODUCTION_URL (HTTPS)."
    exit 1
    ;;
esac

key="${EARNLINE_SUPABASE_PRODUCTION_PUBLISHABLE_KEY:-}"
if [ -z "${key}" ]; then
  echo "error: Release requires EARNLINE_SUPABASE_PRODUCTION_PUBLISHABLE_KEY."
  exit 1
fi

case "${key}" in
  sb_secret_*|*service_role*)
    echo "error: Release configuration contains a secret/service-role Supabase key."
    exit 1
    ;;
esac

case "${EARNLINE_PRIVACY_POLICY_URL:-}" in
  https://*) ;;
  *)
    echo "error: Release requires EARNLINE_PRIVACY_POLICY_URL (HTTPS)."
    exit 1
    ;;
esac
