# tuxbashsysmonitor
Linux Bash System Monitor

## Description

This script checks the system status concerning the CPU, RAM and Disk space levels.
The usual way to usw this script is to configure a crontab job with a minute frequency; for example
```bash
* * * * * bash /tmp/system_monitor.sh
```

The script
- launch a top command
- grep date from it
- it compares the CPU, RAM and DISK values with the corresponding value limits
- if the current value is greater or equal the limit values the sript sends an email with the alert and a report like this

```bash    
    System Monitoring Report - Fri 01 Aug 2025 08:39:31 PM CEST
    ------------------------------------------------------------
    CPU Usage: 0%
    Memory Usage: 29.95%
    Disk Usage: 45%
    Uptime: up 2 days, 10 hours, 41 minutes
    
    Top 15 Processes by CPU Usage:
        PID USER     COMMAND         %MEM %CPU
         95 root     kswapd0          0.0  0.9
       1151 mysql    mysqld          11.8  0.6
     948375 web3     php-cgi8.1       4.1  0.6
     953194 root     systemd          0.2  0.6
       1059 redis    redis-server     1.1  0.4
     948377 web3     php-cgi8.1       3.6  0.4
     951763 web15    php-cgi8.1       4.0  0.4
     953532 root     bash             0.1  0.4
     953176 root     sshd             0.2  0.3
        882 root     f2b/server       0.4  0.2
         10 root     rcu_sched        0.0  0.1
     953202 root     sshd             0.2  0.1
     953533 root     bash             0.0  0.1
          1 root     systemd          0.2  0.0
          2 root     kthreadd         0.0  0.0
    ------------------------------------------------------------
```

  
It's possible to configure many parameters that I specify below:
- to: email recipient destination
- from: email recipient sender
- subject: email subject
- CPU limit value
- RAM lmit value
- DISK limit value
