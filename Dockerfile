FROM alpine:latest

RUN apk update \
    && apk add --no-interactive --no-cache \
       bash \
       procps \
       gawk \
       grep \
       sed \
       gnuplot \
       mutt \
       msmtp \
       ca-certificates \
    && rm -rf /var/cache/apk/*

WORKDIR /app
COPY system_monitor.sh system_monitor.conf docker-entrypoint.sh /app/
RUN chmod +x /app/system_monitor.sh /app/docker-entrypoint.sh

ENTRYPOINT ["/app/docker-entrypoint.sh"]
