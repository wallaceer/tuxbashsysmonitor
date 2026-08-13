#!/bin/bash

# =============================
# Default configuration
# =============================
SERVERNAME=$(hostname -f)
CPU_COUNT=$(nproc 2>/dev/null || grep -c '^cpu[0-9]' /proc/cpuinfo 2>/dev/null || echo 1)

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
DEFAULT_CONFIG_FILE="$SCRIPT_DIR/system_monitor.conf"
CONFIG_FILE="${MONITOR_CONF:-$DEFAULT_CONFIG_FILE}"
OS_NAME=$(uname -s)

# Platform-specific commands
if [[ "$OS_NAME" == "Darwin" ]]; then
    PS_CMD="ps -Ao pid,user,comm,%mem,%cpu -r"
else
    PS_CMD="ps -eo pid,user,comm,%mem,%cpu --sort=-%cpu"
fi

# =============================
# Command-line arguments
# =============================
TEST_MODE=false
while [[ $# -gt 0 ]]; do
    case "$1" in
        --test)
            TEST_MODE=true
            shift
            ;;
        --config)
            CONFIG_FILE="$2"
            shift 2
            ;;
        --config=*)
            CONFIG_FILE="${1#*=}"
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            exit 1
            ;;
    esac
done

# Load external configuration if present
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
else
    echo "Warning: configuration file not found: $CONFIG_FILE" >&2
    echo "Using internal defaults." >&2
fi

# Fallback defaults when configuration values are not provided.
: "${EMAIL_TO:=}"
: "${EMAIL_FROM:=}"
: "${CPU_LIMIT:=}"
: "${RAM_LIMIT:=}"
: "${DISK_LIMIT:=}"
: "${LOAD_LIMIT:=$CPU_COUNT}"
: "${STATE_FILE:=/tmp/monitor_sistema_html.state}"
: "${HIST_FILE:=/tmp/monitor_sistema_storico.csv}"
: "${GRAPH_FILE:=/tmp/monitor_sistema_grafico.png}"
: "${TOP_PROCESSES_LOG:=/tmp/top_processes.log}"
: "${TELEGRAM_BOT_TOKEN:=}"
: "${TELEGRAM_CHAT_ID:=}"
: "${WHATSAPP_TWILIO_ACCOUNT_SID:=}"
: "${WHATSAPP_TWILIO_AUTH_TOKEN:=}"
: "${WHATSAPP_TWILIO_FROM:=}"
: "${WHATSAPP_TWILIO_TO:=}"
: "${WHATSAPP_TWILIO_CONTENT_SID:=}"

# =============================
# Notification helpers
# =============================
send_telegram_alert() {
    local message="$1"

    if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
        echo "Warning: Telegram notification is not fully configured; skipping." >&2
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "Warning: curl is not installed; skipping Telegram notification." >&2
        return 0
    fi

    local response_file
    response_file=$(mktemp)
    local status
    status=$(curl -sS -o "$response_file" -w "%{http_code}" -X POST \
        "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=$message")

    if [[ "$status" != "200" ]]; then
        local response_body
        response_body=$(tr '\n' ' ' < "$response_file")
        echo "Warning: Telegram notification returned HTTP status $status. Response: $response_body" >&2
    fi

    rm -f "$response_file"
}

send_whatsapp_alert() {
    local message="$1"
    message=${message//$'\n'/ }

    if [[ -z "$WHATSAPP_TWILIO_ACCOUNT_SID" || -z "$WHATSAPP_TWILIO_AUTH_TOKEN" || -z "$WHATSAPP_TWILIO_FROM" || -z "$WHATSAPP_TWILIO_TO" ]]; then
        echo "Warning: WhatsApp notification is not fully configured; skipping." >&2
        return 0
    fi

    if ! command -v curl >/dev/null 2>&1; then
        echo "Warning: curl is not installed; skipping WhatsApp notification." >&2
        return 0
    fi

    local response_file
    response_file=$(mktemp)
    local status
    local curl_args=(-sS -o "$response_file" -w "%{http_code}" -u "${WHATSAPP_TWILIO_ACCOUNT_SID}:${WHATSAPP_TWILIO_AUTH_TOKEN}" -X POST "https://api.twilio.com/2010-04-01/Accounts/${WHATSAPP_TWILIO_ACCOUNT_SID}/Messages.json")

    if [[ -n "$WHATSAPP_TWILIO_CONTENT_SID" ]]; then
        curl_args+=(--data-urlencode "To=$WHATSAPP_TWILIO_TO" --data-urlencode "From=$WHATSAPP_TWILIO_FROM" --data-urlencode "ContentSid=$WHATSAPP_TWILIO_CONTENT_SID" --data-urlencode "ContentType=twilio/text")
    else
        curl_args+=(--data-urlencode "To=$WHATSAPP_TWILIO_TO" --data-urlencode "From=$WHATSAPP_TWILIO_FROM" --data-urlencode "Body=$message")
    fi

    status=$(curl "${curl_args[@]}")

    if [[ "$status" != "201" ]]; then
        local response_body
        response_body=$(tr '\n' ' ' < "$response_file")
        echo "Warning: WhatsApp notification returned HTTP status $status. Response: $response_body" >&2
    fi

    rm -f "$response_file"
}

# =============================
# Dati collection
# =============================
if $TEST_MODE; then
    CPU_USAGE=95
    CPU_PER_CORE_STR="cpu0:95%, cpu1:95%, cpu2:95%, cpu3:95%"
    CPU_OVER_THRESHOLD_STR="cpu0:95%, cpu1:95%, cpu2:95%, cpu3:95%"
    LOAD_USAGE=5.0
    RAM_USAGE=92
    DISK_USAGE=97
else
    # Calculate per-CPU usage (Linux /proc/stat) and determine maximum CPU usage
    CPU_PER_CORE_STR=""
    CPU_OVER_THRESHOLD_STR=""
    if [ -r /proc/stat ]; then
        CPU_STATS1="/tmp/cpu_stat1.$$"
        CPU_STATS2="/tmp/cpu_stat2.$$"
        grep '^cpu[0-9]' /proc/stat > "$CPU_STATS1"
        sleep 1
        grep '^cpu[0-9]' /proc/stat > "$CPU_STATS2"
        CPU_CALC=$(awk 'FNR==NR {a[$1]=$0; next} {
            n1 = split(a[$1], x)
            n2 = split($0, y)
            idle1 = x[5]; idle2 = y[5]
            t1=0; t2=0
            for(i=2;i<=n1;i++) t1+=x[i]
            for(i=2;i<=n2;i++) t2+=y[i]
            use=0
            if (t2>t1) use = (1 - (idle2 - idle1)/(t2 - t1)) * 100
            printf "%s,%d\n", $1, int(use)
        }' "$CPU_STATS1" "$CPU_STATS2")
        rm -f "$CPU_STATS1" "$CPU_STATS2"
        if [ -n "$CPU_CALC" ]; then
            CPU_MAX=0
            SEP=""
            CPU_OVER_THRESHOLD_STR=""
            while IFS=, read -r cpu val; do
                CPU_PER_CORE_STR+="$SEP"$cpu":"$val"%"
                SEP=", "
                if [ "$val" -gt "$CPU_MAX" ]; then
                    CPU_MAX=$val
                fi
                if [ "$val" -ge "$CPU_LIMIT" ]; then
                    if [[ -n "$CPU_OVER_THRESHOLD_STR" ]]; then
                        CPU_OVER_THRESHOLD_STR+=" , "
                    fi
                    CPU_OVER_THRESHOLD_STR+="$cpu:$val%"
                fi
            done <<< "$CPU_CALC"
            CPU_USAGE=$CPU_MAX
        else
            if command -v top >/dev/null 2>&1; then
                CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk -F. '{print $1}')
            else
                CPU_USAGE=0
            fi
            CPU_PER_CORE_STR="N/A"
        fi
    else
        if command -v top >/dev/null 2>&1; then
            CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk -F. '{print $1}')
        else
            CPU_USAGE=0
        fi
        CPU_PER_CORE_STR="N/A"
    fi

    if [ -r /proc/loadavg ]; then
        LOAD_USAGE=$(cut -d ' ' -f1 /proc/loadavg)
    else
        if [[ "$OS_NAME" == "Darwin" ]]; then
            LOAD_USAGE=$(uptime | awk -F'load averages?:' '{print $2}' | cut -d',' -f1 | sed 's/^[[:space:]]*//')
        else
            LOAD_USAGE=$(uptime | awk -F'load average:' '{print $2}' | cut -d',' -f1 | sed 's/^[[:space:]]*//')
        fi
    fi

    if command -v free >/dev/null 2>&1; then
        RAM_USAGE=$(free | awk '/Mem/ {printf("%.0f", $3/$2 * 100)}')
    elif [[ "$OS_NAME" == "Darwin" ]]; then
        TOTAL_MEM=$(sysctl -n hw.memsize)
        FREE_PAGES=$(vm_stat | awk '/Pages free/ {free=$3} /Pages inactive/ {inactive=$3} END {print free+inactive}')
        RAM_USAGE=$(awk -v total="$TOTAL_MEM" -v free_pages="$FREE_PAGES" 'BEGIN {used=(total-(free_pages*4096)); printf("%.0f", used/total*100)}')
    else
        RAM_USAGE=0
    fi
    if command -v df >/dev/null 2>&1; then
        DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
    else
        DISK_USAGE=0
    fi
fi

cat /dev/null > "$TOP_PROCESSES_LOG"
if [[ "$OS_NAME" == "Darwin" ]]; then
    UPTIME=$(uptime | awk -F'(up |,)' '{print $2}' | sed 's/^ *//; s/ *$//')
else
    if uptime -p >/dev/null 2>&1; then
        UPTIME=$(uptime -p)
    else
        UPTIME=$(uptime | awk -F'(up |,)' '{print $2}' | sed 's/^ *//; s/ *$//')
    fi
fi
TOP_PROCESSES=$(eval "$PS_CMD" | head -n 16 | awk 'BEGIN {
    print "<table border=\"1\"><tr><th>PID</th><th>User</th><th>Command</th><th>% Memory</th><th>% CPU</th></tr>"
}
NR>1 {
    print "<tr><td>" $1 "</td><td>" $2 "</td><td>" $3 "</td><td>" $4 "</td><td>" $5 "</td></tr>"
}
END {
    print "</table>"
}') # Top 15 processes
{
    printf '%s\n' "$TOP_PROCESSES"
} >> "$TOP_PROCESSES_LOG"

# =============================
# Historical data generationn
# =============================
DATE_NOW=$(date "+%Y-%m-%d %H:%M:%S")
echo "$DATE_NOW,$CPU_USAGE,$RAM_USAGE,$DISK_USAGE,$UPTIME" >> "$HIST_FILE"

# =============================
# Status check
# =============================
STATUS="OK"
LOAD_ALERT=false
if awk "BEGIN {exit !($LOAD_USAGE >= $LOAD_LIMIT)}"; then
    LOAD_ALERT=true
fi
if $LOAD_ALERT; then
    STATUS="ALERT"
fi

PREV_STATUS=""
if [[ -f "$STATE_FILE" ]]; then
    PREV_STATUS=$(cat "$STATE_FILE")
fi

# In test mode forziamo l'invio
if $TEST_MODE; then
    STATUS="ALERT"
    PREV_STATUS="OK"
fi

echo "$STATUS" > "$STATE_FILE"

# =============================
# Exit if the status is the same
# =============================
if [[ "$STATUS" == "$PREV_STATUS" && $TEST_MODE == false ]]; then
    exit 0
fi

# =============================
# Make HTML table
# =============================
#Color for alert field
CPU_BCK_COLOR=RAM_BCK_COLOR=DISK_BCK_COLOR='none'
EMAIL_SUBJECT_FIELD=''
if [[ $CPU_USAGE -ge $CPU_LIMIT ]]; then
    CPU_BCK_COLOR="red"
    EMAIL_SUBJECT_FIELD+='CPU '
fi

if [[ $RAM_USAGE -ge $RAM_LIMIT ]]; then
    RAM_BCK_COLOR="red"
    EMAIL_SUBJECT_FIELD+='RAM '
fi

if [[ $DISK_USAGE -ge $DISK_LIMIT ]]; then
    DISK_BCK_COLOR="red"
    EMAIL_SUBJECT_FIELD+='DISK '
fi

LOAD_BCK_COLOR='none'
if $LOAD_ALERT; then
    LOAD_BCK_COLOR="red"
    EMAIL_SUBJECT_FIELD+='LOAD'
fi

EMAIL_BODY="<?xml version=\"1.0\" encoding=\"UTF-8\" ?>"
EMAIL_BODY+="<!DOCTYPE html>"
EMAIL_BODY+="<html xmlns=\"http://www.w3.org/1999/xhtml\" xml:lang=\"en\" lang=\"en\" dir=\"ltr\">"
EMAIL_BODY+="<head>"
EMAIL_BODY+="<meta name=\"description\" content=\"application/xhtml+xml; charset=UTF-8\" />"
EMAIL_BODY+="</head>"
EMAIL_BODY+="<body>"
EMAIL_BODY+="<h2>System Monitor</h2>"
EMAIL_BODY+="<p>System Monitoring Report - $(date)</p>"
EMAIL_BODY+="<table border='1' cellpadding='5' cellspacing='0'>"
EMAIL_BODY+="<tr><th>Date</th><th>CPU % (quota sopra soglia)</th><th>RAM %</th><th>DISK %</th></tr>"
EMAIL_BODY+="<tr><td>$DATE_NOW</td><td style=\"background-color:$CPU_BCK_COLOR\">$CPU_USAGE"
if [[ -n "$CPU_OVER_THRESHOLD_STR" ]]; then
    EMAIL_BODY+=" ($CPU_OVER_THRESHOLD_STR)"
fi
EMAIL_BODY+="</td><td style=\"background-color:$RAM_BCK_COLOR\">$RAM_USAGE</td><td style=\"background-color:$DISK_BCK_COLOR\">$DISK_USAGE</td></tr>"
EMAIL_BODY+="</table>"
EMAIL_BODY+="<p>&nbsp;</p>"
EMAIL_BODY+="<table border='1' cellpadding='5' cellspacing='0'>"
EMAIL_BODY+="<tr><th>Uptime</th></tr>"
EMAIL_BODY+="<tr><td>"
EMAIL_BODY+=$UPTIME
EMAIL_BODY+="</td></tr>"
EMAIL_BODY+="<tr><th>Per-CPU usage</th></tr>"
EMAIL_BODY+="<tr><td>"
EMAIL_BODY+="$CPU_PER_CORE_STR"
EMAIL_BODY+="</td></tr>"
EMAIL_BODY+="<tr><th>Load average</th></tr>"
EMAIL_BODY+="<tr><td style=\"background-color:$LOAD_BCK_COLOR\">"
EMAIL_BODY+="$LOAD_USAGE (limit $LOAD_LIMIT)"
EMAIL_BODY+="</td></tr>"
EMAIL_BODY+="<tr><th>Top 15 processes by CPU usage</th></tr>"
EMAIL_BODY+="<tr><td>"
EMAIL_BODY+="<div style=\"overflow:auto; max-height:360px;\">"
TOP_PROCESSES_HTML=$(< "$TOP_PROCESSES_LOG")
EMAIL_BODY+="$TOP_PROCESSES_HTML"
EMAIL_BODY+="</div>"
EMAIL_BODY+="</td></tr>"
EMAIL_BODY+="</table>"
EMAIL_BODY+="</body>"
EMAIL_BODY+="</html>"
printf '%s' "$EMAIL_BODY" > /tmp/email_body.html
# =============================
# Make graph
# =============================
if command -v gnuplot >/dev/null 2>&1; then
    gnuplot <<EOF
set terminal png size 800,400
set output "$GRAPH_FILE"
set title "Storico utilizzo risorse"
set xlabel "Tempo"
set xdata time
set timefmt "%Y-%m-%d %H:%M:%S"
set format x "%H:%M"
set ylabel "%"
set grid
set datafile separator ","
plot "$HIST_FILE" using 1:2 with lines title "CPU", \
     "$HIST_FILE" using 1:3 with lines title "RAM", \
     "$HIST_FILE" using 1:4 with lines title "DISCO"
EOF
else
    echo "Warning: gnuplot not installed, skipping graph generation." >&2
fi

# =============================
# Send email
# =============================
EMAIL_SUBJECT="[$SERVERNAME] - ⚠️ $EMAIL_SUBJECT_FIELD alarm "
printf '%s' "$EMAIL_BODY" > /tmp/email_body.html

if [ "$STATUS" == "ALERT" ]; then
  if [[ -z "$EMAIL_TO" ]]; then
    echo "Warning: EMAIL_TO is not set; skipping email notification." >&2
  elif command -v mutt >/dev/null 2>&1; then
    mutt -e 'set content_type=text/html' -s "$EMAIL_SUBJECT" -a "$GRAPH_FILE" -a "$HIST_FILE" -a "$TOP_PROCESSES_LOG" -- "$EMAIL_TO" < /tmp/email_body.html
  elif command -v sendmail >/dev/null 2>&1; then
    {
      echo "To: $EMAIL_TO"
      echo "Subject: $EMAIL_SUBJECT"
      echo "MIME-Version: 1.0"
      echo "Content-Type: text/html; charset=UTF-8"
      echo
      printf '%s' "$EMAIL_BODY"
    } | sendmail -t
    echo "Warning: mutt not installed, sent fallback HTML email via sendmail." >&2
  else
    echo "Warning: neither mutt nor sendmail is installed; skipping email notification." >&2
  fi
fi
