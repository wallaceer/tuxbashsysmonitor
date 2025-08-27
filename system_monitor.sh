#!/bin/bash

# =============================
# Configuration
# =============================
SERVERNAME=$(hostname -f)
EMAIL_TO=""
EMAIL_FROM=""
CPU_LIMIT=90
RAM_LIMIT=80
DISK_LIMIT=90
STATE_FILE="/tmp/monitor_sistema_html.state"
HIST_FILE="/tmp/monitor_sistema_storico.csv"
GRAPH_FILE="/tmp/monitor_sistema_grafico.png"
TOP_PROCESSES_LOG="/tmp/top_processes.log"

# =============================
# Test mode
# =============================
TEST_MODE=false
if [[ "$1" == "--test" ]]; then
    TEST_MODE=true
fi

# =============================
# Dati collection
# =============================
if $TEST_MODE; then
    CPU_USAGE=95
    RAM_USAGE=92
    DISK_USAGE=97
else
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | awk '{print 100 - $8}' | awk -F. '{print $1}')
    RAM_USAGE=$(free | awk '/Mem/ {printf("%.0f"), $3/$2 * 100}')
    DISK_USAGE=$(df / | awk 'NR==2 {print $5}' | sed 's/%//')
fi

cat /dev/null > $TOP_PROCESSES_LOG
UPTIME=$(uptime -p) # Human-readable uptime
TOP_PROCESSES=$(ps -eo pid,user,comm,%mem,%cpu --sort=-%cpu | head -n 16 | awk 'BEGIN {
    print "<table border=\"1\"><tr><th>PID</th><th>User</th><th>Command</th><th>% Memory</th><th>% CPU</th></tr>"
}
NR>1 {
    print "<tr><td>" $1 "</td><td>" $2 "</td><td>" $3 "</td><td>" $4 "</td><td>" $5 "</td></tr>"
}
END {
    print "</table>"
}') # Top 15 processes
{
    echo "<p>$TOP_PROCESSES</p>"
} >> $TOP_PROCESSES_LOG

# =============================
# Historical data generationn
# =============================
DATE_NOW=$(date "+%Y-%m-%d %H:%M:%S")
echo "$DATE_NOW,$CPU_USAGE,$RAM_USAGE,$DISK_USAGE,$UPTIME" >> "$HIST_FILE"

# =============================
# Status check
# =============================
STATUS="OK"
if [[ $CPU_USAGE -ge $CPU_LIMIT || $RAM_USAGE -ge $RAM_LIMIT || $DISK_USAGE -ge $DISK_LIMIT ]]; then
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
    EMAIL_SUBJECT_FIELD+='DISK'
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
EMAIL_BODY+="<tr><th>Date</th><th>CPU %</th><th>RAM %</th><th>DISK %</th></tr>"
EMAIL_BODY+="<tr><td>$DATE_NOW</td><td style="background-color:$CPU_BCK_COLOR">$CPU_USAGE</td><td style="background-color:$RAM_BCK_COLOR">$RAM_USAGE</td><td style="background-color:$DISK_BCK_COLOR">$DISK_USAGE</td></tr>"
EMAIL_BODY+="</table>"
EMAIL_BODY+="<p>&nbsp;</p>"
EMAIL_BODY+="<table border='1' cellpadding='5' cellspacing='0'>"
EMAIL_BODY+="<tr><th>Uptime</th></tr>"
EMAIL_BODY+="<tr><td>"
EMAIL_BODY+=$UPTIME
EMAIL_BODY+="</td></tr>"
EMAIL_BODY+="<tr><th>Load average</th></tr>"
EMAIL_BODY+="<tr><td>"
EMAIL_BODY+=$(cat /proc/loadavg)
EMAIL_BODY+="</td></tr>"
EMAIL_BODY+="<tr><th>Top 15 processes by CPU usage</th></tr>"
EMAIL_BODY+="<tr><td>"
EMAIL_BODY+=$(cat $TOP_PROCESSES_LOG)
EMAIL_BODY+="</td></tr>"
EMAIL_BODY+="</table>"
EMAIL_BODY+="</html>"
EMAIL_BODY+="</body>"
echo $EMAIL_BODY > /tmp/email_body.html
# =============================
# Make graph
# =============================
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

# =============================
# Send email
# =============================
EMAIL_SUBJECT="[$SERVERNAME] - ⚠️ $EMAIL_SUBJECT_FIELD alarm "
(
HEADER="To: $EMAIL_TO"
HEADER+="Subject: $EMAIL_SUBJECT"
HEADER+="MIME-Version: 1.0"
HEADER+="Content-Type: multipart/mixed; boundary=XYZ"
HEADER+=""
HEADER+="--XYZ"
HEADER+="Content-Type: text/html"
HEADER+=""
HEADER+="$EMAIL_BODY"
HEADER+="--XYZ"
HEADER+="Content-Type: image/png"
HEADER+="Content-Transfer-Encoding: base64"
HEADER+="Content-Disposition: attachment; filename=\"monitor_sistema_grafico.png\""
#base64 "$GRAPH_FILE"
HEADER+="--XYZ--"
)
#| echo $EMAIL_BODY |
if [ $STATUS == "ALERT" ]; then
  mutt -e "$HEADER" -s "$EMAIL_SUBJECT" $EMAIL_TO -a "$GRAPH_FILE" -a "$HIST_FILE" -a $TOP_PROCESSES_LOG -e 'set content_type="text/html"' < /tmp/email_body.html
fi
