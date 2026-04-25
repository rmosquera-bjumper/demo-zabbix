FROM zabbix/zabbix-agent2:alpine-7.0-latest

USER root

RUN apk add --no-cache nginx

RUN mkdir -p /run/nginx /var/log/nginx /var/www/html

COPY nginx.conf /etc/nginx/nginx.conf
COPY html/ /var/www/html/
COPY docker-entrypoint.sh /my-entrypoint.sh
RUN chmod +x /my-entrypoint.sh

EXPOSE 80 10050

ENTRYPOINT ["/my-entrypoint.sh"]
