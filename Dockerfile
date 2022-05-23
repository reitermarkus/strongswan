FROM alpine:3.16.0

RUN apk add --no-cache bash~=5.1 strongswan~=5.9.1 openssl~=1.1 util-linux~=2.37

COPY generate-ipsec-config.sh /generate-ipsec-config.sh
COPY entrypoint.sh /entrypoint.sh

VOLUME /etc/ipsec.d

EXPOSE 500/udp
EXPOSE 4500/udp

CMD ["/usr/sbin/ipsec", "start", "--nofork"]
ENTRYPOINT ["/entrypoint.sh"]
