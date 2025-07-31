#!/bin/bash

#====================
#Email configurations
#====================
to=""
from=""
subject="Alert from "

#============
#Usage limits
#============
cpu_limit=90
memory_limit=90
disk_limit=90

#========
#Get data
#========
CPU=$(top -bn1 | grep "Cpu(s)" | awk '{print $2 + $4}') # Sum of user and system CPU usage
MEMORY=$(free -m | awk 'NR==2{printf "%.2f", $3*100/$2 }') # Memory usage as a percentage
DISK=$(df -h / | awk 'NR==2 {print $5}') # Root filesystem usage as a percentage
UPTIME=$(uptime -p) # Human-readable uptime
TOP_PROCESSES=$(ps -eo pid,comm,%mem,%cpu --sort=-%cpu | head -n 16) # Top 15 processes

#======
#Report
#======
#Empty log file
cat /dev/null > "system_monitor.log"

OUTPUT_FILE="system_monitor.log"
{
    echo "System Monitoring Report - $(date)"
    echo "---------------------------------"
    echo "CPU Usage: $CPU%"
    echo "Memory Usage: $MEMORY%"
    echo "Disk Usage: $DISK"
    echo "Uptime: $UPTIME"
    echo ""
    echo "Top 15 Processes by CPU Usage:"
    echo "$TOP_PROCESSES"
    echo "---------------------------------"
} >> $OUTPUT_FILE

cat $OUTPUT_FILE

#================
#Data preparation
#================
cpu_usage_int=$(printf "%.0f" "$CPU")
memory_usage_int=$(printf "%.0f" "$MEMORY")
disk_usage_int=$(printf "%.0f" "$DISK")
#echo "$disk_usage_int"
#disk_usage_int="${disk_usage//%/}"

#============
#Email alerts
#============
#CPU alert
if [ $cpu_usage_int -gt $cpu_limit ]
then
   msg="CPU usage is greater or equal than $CPU%"
   echo "$msg"
   mail -s "$msg" "$to" "$from" < $OUTPUT_FILE
fi

#MEMORY alert
if [ $memory_usage_int -gt $memory_limit ]
then
   msg="MEMORY usage is greater or equal than $MEMORY%"
   echo "$msg"
   mail -s "$subject" "$to" "$from" < $OUTPUT_FILE
fi

#DISK alert
if [ $disk_usage_int -gt $disk_limit ]
then
   msg="DISK usage is greater or equal than $DISK"
   echo "$msg"
   #echo "$msg \r\n " |
   mail -s "$msg" "$to" "$from" < $OUTPUT_FILE
fi
