FROM alpine

RUN apk add --no-cache bash strongswan openssl util-linux

COPY generate-ipsec-config.sh /generate-ipsec-config.sh
COPY entrypoint.sh /entrypoint.sh

VOLUME /etc/ipsec.d

EXPOSE 500/udp
EXPOSE 4500/udp

CMD ["/usr/sbin/ipsec", "start", "--nofork"]
ENTRYPOINT ["/entrypoint.sh"]
