# tuxbashsysmonitor
Linux Bash System Monitor

## Description

This script checks the system status for CPU, RAM, Disk usage and load average.
When one of the configured thresholds is reached, the script generates an alert report and sends an email notification, plus optional Telegram and WhatsApp alerts.

> Version 3.1.2 - Fixed some cotainer configuration and functionalities

The usual installation method is a cron job with a minute frequency, for example:
```bash
* * * * * bash /path/to/system_monitor.sh
```

## Configuration

The script now supports an external configuration file named `system_monitor.conf` located next to `system_monitor.sh`.
The default configuration file is loaded automatically, but you can also specify a custom file.

### Default config file
Create or edit `system_monitor.conf` with values like:
```bash
EMAIL_TO="alerts@example.com"
EMAIL_FROM="monitor@example.com"

SMTP_HOST="smtp.example.com"
SMTP_PORT=587
SMTP_USER="your_smtp_user"
SMTP_PASSWORD="your_smtp_password"
SMTP_TLS=on
SMTP_STARTTLS=on

CPU_LIMIT=90
RAM_LIMIT=80
DISK_LIMIT=90
LOAD_LIMIT=4

# Optional Telegram notifications
TELEGRAM_BOT_TOKEN=""
TELEGRAM_CHAT_ID=""

# Optional WhatsApp notifications via Twilio
WHATSAPP_TWILIO_ACCOUNT_SID=""
WHATSAPP_TWILIO_AUTH_TOKEN=""
WHATSAPP_TWILIO_FROM=""
WHATSAPP_TWILIO_TO=""
# Optional Twilio WhatsApp template identifier
WHATSAPP_TWILIO_CONTENT_SID=""

STATE_FILE="/tmp/monitor_sistema_html.state"
HIST_FILE="/tmp/monitor_sistema_storico.csv"
GRAPH_FILE="/tmp/monitor_sistema_grafico.png"
TOP_PROCESSES_LOG="/tmp/top_processes.log"
```

### Available settings
- `EMAIL_TO`: destination email address for alerts
- `EMAIL_FROM`: sender address used in alerts
- `SMTP_HOST`: SMTP host to send the alert email
- `SMTP_PORT`: SMTP port to use
- `SMTP_USER`: SMTP username
- `SMTP_PASSWORD`: SMTP password
- `SMTP_TLS`: use TLS to connect to SMTP server (`on`/`off`)
- `SMTP_STARTTLS`: use STARTTLS when supported (`on`/`off`)
- `CPU_LIMIT`: per-CPU usage threshold (%) to include in the alert report
- `RAM_LIMIT`: RAM usage threshold (%)
- `DISK_LIMIT`: disk usage threshold (%)
- `LOAD_LIMIT`: load average threshold
- `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHAT_ID`: optional Telegram bot credentials
- `WHATSAPP_TWILIO_ACCOUNT_SID`, `WHATSAPP_TWILIO_AUTH_TOKEN`, `WHATSAPP_TWILIO_FROM`, `WHATSAPP_TWILIO_TO`: optional Twilio WhatsApp credentials
- `WHATSAPP_TWILIO_CONTENT_SID`: optional Twilio WhatsApp template identifier for approved template-based messages
- `STATE_FILE`, `HIST_FILE`, `GRAPH_FILE`, `TOP_PROCESSES_LOG`: optional path overrides

### Custom config path
Use a custom configuration path with:
```bash
bash system_monitor.sh --config /path/to/system_monitor.conf
```

Or use the `MONITOR_CONF` environment variable:
```bash
MONITOR_CONF=/path/to/system_monitor.conf bash system_monitor.sh
```

## Test mode

To run the script in test mode and force an alert without changing system state:
```bash
bash system_monitor.sh --test
```

## Notes

- On Linux the script reads `/proc/stat` and `/proc/loadavg` for CPU and load data.
- Telegram notifications require a bot token and a chat ID. WhatsApp notifications use Twilio credentials and support the WhatsApp Sandbox or a WhatsApp Business account.
- On macOS it uses platform-specific command fallbacks for process and uptime information.
- If `gnuplot` is not installed, graph generation is skipped with a warning.
- If `mutt` is unavailable, the script tries `sendmail` as a fallback.

## Docker support

A `Dockerfile` is included to run the monitor in a container.

Build the image:
```bash
docker build -t tuxbashsysmonitor .
```

Run the container with the mounted configuration file:
```bash
docker run --rm \
  -v "$PWD/system_monitor.conf:/app/system_monitor.conf:ro" \
  -v /tmp:/tmp \
  tuxbashsysmonitor --config /app/system_monitor.conf
```

All SMTP and alert settings are defined in `system_monitor.conf`; the container does not require SMTP environment variables.

If your SMTP server uses a self-signed certificate or a certificate that does not match the hostname, you can disable certificate validation for testing by adding this line to `system_monitor.conf`:
```bash
SMTP_TLS_CERTCHECK=off
```

Alternatively use `docker-compose`:
```bash
docker compose up --build
```

The container supports two execution modes:

- Manual execution (default): the script runs once when the container starts.
- Cron execution: start the container with `cron` as the command to run the monitor through a crontab entry. You can override the schedule with the `CRON_SCHEDULE` environment variable.

Examples:
```bash
# Manual run
docker run --rm \
  -v "$PWD/system_monitor.conf:/app/system_monitor.conf:ro" \
  -v /tmp:/tmp \
  tuxbashsysmonitor --config /app/system_monitor.conf

# Cron-based run (every minute by default)
docker run -d \
  -v "$PWD/system_monitor.conf:/app/system_monitor.conf:ro" \
  -v /tmp:/tmp \
  -e CRON_SCHEDULE='* * * * *' \
  tuxbashsysmonitor cron
```

The container runs `system_monitor.sh` and uses the mounted `system_monitor.conf` file.

## E-mail example
![Email example](https://github.com/wallaceer/tuxbashsysmonitor/blob/main/tuxbashsysmonitor-email-example.png "Email example")


## Telegram alerts example
![Telegram alerts example](https://github.com/wallaceer/tuxbashsysmonitor/blob/main/tuxbashsysmonitor-telegram-alerts.png "Telegram alerts example")

