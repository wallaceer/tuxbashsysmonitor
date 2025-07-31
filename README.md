# tuxbashsysmonitor
Linux Bash System Monitor

This script checks the system status concerning the CPU, RAM and Disk space levels.
The usual way to usw this script is to configure a crontab job with a minute frequency; for example
    ------------------------------------------
    * * * * * sh /tmp/system_monitor.sh
The script
- launch a top command
- grep date from it
- it compares the CPU, RAM and DISK values with the corresponding value limits
- if the current value is greater or equal the limit values the sript sends an email with the alert and a report like this

- System Monitoring Report - Thu 31 Jul 2025 01:39:01 PM CEST
    ------------------------------------------
      CPU Usage: 91.6%
      Memory Usage: 29.45%
      Disk Usage: 45%
      Uptime: up 1 day, 3 hours, 41 minutes
      
      Top 5 Processes by CPU Usage:
          PID COMMAND         %MEM %CPU
       422447 redis-server     1.0 13.0
           95 kswapd0          0.0  1.4
       419284 php-cgi8.1       3.9  0.8
         1151 mysqld           8.9  0.6
       414834 php-cgi8.1       3.6  0.6
    -----------------------------------------

  
It's possible to configure many parameters that I specify below:
- to: email recipient destination
- from: email recipient sender
- subject: email subject
- CPU limit value
- RAM lmit value
- DISK limit value
