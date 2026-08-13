#!/bin/bash
set -e

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/system_monitor.conf}"
CRON_SCHEDULE="${CRON_SCHEDULE:-* * * * *}"

args=("$@")
mode="manual"

if [[ ${#args[@]} -gt 0 ]]; then
  case "${args[0]}" in
    cron)
      mode="cron"
      args=("${args[@]:1}")
      ;;
    manual)
      mode="manual"
      args=("${args[@]:1}")
      ;;
  esac
fi

# If the entrypoint is called with a --config argument, use that file for SMTP settings too.
for ((i=0; i < ${#args[@]}; i++)); do
  case "${args[i]}" in
    --config)
      CONFIG_FILE="${args[i+1]:-$CONFIG_FILE}"
      break
      ;;
    --config=*)
      CONFIG_FILE="${args[i]#*=}"
      break
      ;;
  esac
done

if [[ -f "$CONFIG_FILE" ]]; then
  # shellcheck source=/dev/null
  source "$CONFIG_FILE"
fi

if [[ -n "${SMTP_HOST:-}" ]]; then
  cat > /etc/msmtprc <<EOF
defaults
auth           ${SMTP_AUTH:-on}
tls            ${SMTP_TLS:-on}
tls_starttls   ${SMTP_STARTTLS:-on}
tls_certcheck  ${SMTP_TLS_CERTCHECK:-on}
tls_trust_file /etc/ssl/certs/ca-certificates.crt
logfile        /var/log/msmtp.log

account        default
host           ${SMTP_HOST}
port           ${SMTP_PORT:-587}
user           ${SMTP_USER:-}
password       "${SMTP_PASSWORD:-}"
from           ${EMAIL_FROM:-}
EOF
  chmod 600 /etc/msmtprc
fi

if [[ "$mode" == "cron" ]]; then
  cat > /etc/cron.d/system-monitor <<EOF
SHELL=/bin/bash
PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

${CRON_SCHEDULE} root /bin/bash /app/system_monitor.sh --config "$CONFIG_FILE" >> /var/log/system_monitor_cron.log 2>&1
EOF
  chmod 0644 /etc/cron.d/system-monitor
  touch /var/log/system_monitor_cron.log
  exec cron -f
fi

exec /bin/bash /app/system_monitor.sh "${args[@]}"
