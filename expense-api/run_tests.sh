#!/usr/bin/env bash
# Mints a throwaway RSA keypair and exports the gateway-assertion trio BEFORE
# bal test starts the service (the interceptor reads them at listener init),
# then runs the package verify: bal build && bal test.
set -euo pipefail

KEY_DIR="${EXPENSE_TEST_KEY_DIR:-/tmp/expense-api-test-keys}"
mkdir -p "$KEY_DIR"
rm -f "$KEY_DIR/gateway.key" "$KEY_DIR/gateway.crt" "$KEY_DIR/other.key" "$KEY_DIR/other.crt"

openssl req -x509 -newkey rsa:2048 \
  -keyout "$KEY_DIR/gateway.key" -out "$KEY_DIR/gateway.crt" \
  -days 1 -nodes -subj '/CN=test-gateway' >/dev/null 2>&1

openssl req -x509 -newkey rsa:2048 \
  -keyout "$KEY_DIR/other.key" -out "$KEY_DIR/other.crt" \
  -days 1 -nodes -subj '/CN=other-gateway' >/dev/null 2>&1

export GATEWAY_ASSERTION_CERTIFICATE="$(cat "$KEY_DIR/gateway.crt")"
export GATEWAY_ASSERTION_ISSUER="aep-gateway-test"
export GATEWAY_ASSERTION_HEADER="x-jwt-assertion"

cd "$(dirname "$0")"
bal build && bal test "$@"