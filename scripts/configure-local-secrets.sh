#!/bin/zsh

set -euo pipefail

: "${SEENA_BACKEND_URL:?SEENA_BACKEND_URL is required}"
: "${SEENA_APP_TOKEN:?SEENA_APP_TOKEN is required}"

if [[ "$SEENA_BACKEND_URL" != https://* ]]; then
  print -u2 "SEENA_BACKEND_URL must use HTTPS."
  exit 1
fi

if (( ${#SEENA_APP_TOKEN} != 64 )) || [[ "$SEENA_APP_TOKEN" == *[^[:xdigit:]]* ]]; then
  print -u2 "SEENA_APP_TOKEN must be a 64-character hexadecimal token."
  exit 1
fi

script_directory="${0:A:h}"
repository_root="${script_directory:h}"
destination="$repository_root/Config/Secrets.xcconfig"
plist_destination="$repository_root/SeeNA/Secrets.plist"
backend_host="${SEENA_BACKEND_URL#https://}"

umask 077
{
  print -r -- "// Generated locally. Never commit this file."
  print -r -- 'SEENA_BACKEND_URL = https:/$()/'"$backend_host"
  print -r -- "SEENA_APP_TOKEN = $SEENA_APP_TOKEN"
} > "$destination"

/usr/bin/plutil -create xml1 "$plist_destination"
/usr/bin/plutil -insert SEENA_BACKEND_URL -string "$SEENA_BACKEND_URL" "$plist_destination"
/usr/bin/plutil -insert SEENA_APP_TOKEN -string "$SEENA_APP_TOKEN" "$plist_destination"
/bin/chmod 600 "$plist_destination"

print "Configured local SeeNA backend settings."
