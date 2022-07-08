FROM alpine:3.16.0

ARG STRONGSWAN_VERSION=5.9.6

RUN apk add --no-cache \
      bash~=5.1 \
      iptables~=1.8 \
      nmap=~7.92 \
      util-linux~=2.38 \
      gmp~=6.2 \
      openssl~=1.1 \
      libcurl~=7.83 \
      sqlite-libs~=3.38 \
 && apk add --no-cache --virtual .build-deps \
      build-base~=0.5 \
      linux-headers~=5.16 \
      gmp-dev~=6.2 \
      curl-dev~=7.83 \
      sqlite-dev~=3.38 \
 && wget --quiet "https://download.strongswan.org/strongswan-${STRONGSWAN_VERSION}.tar.bz2" \
 && tar -xjf "strongswan-${STRONGSWAN_VERSION}.tar.bz2" \
 && rm "strongswan-${STRONGSWAN_VERSION}.tar.bz2" \
 && cd "strongswan-${STRONGSWAN_VERSION}" \
 && ./configure --prefix=/usr/local --sysconfdir=/etc \
      --enable-ha \
      --enable-openssl \
      --enable-curl \
      --enable-sqlite \
      --enable-bypass-lan \
      --enable-farp \
      --enable-eap-identity \
      --enable-eap-sim \
      --enable-eap-aka \
      --enable-eap-aka-3gpp2 \
      --enable-eap-simaka-pseudonym \
      --enable-eap-simaka-reauth \
      --enable-eap-md5 \
      --enable-eap-mschapv2 \
      --enable-eap-radius \
      --enable-eap-tls \
      --enable-xauth-eap \
      --enable-dhcp \
      --enable-unity \
      --enable-counters \
 && make \
 && make install \
 && cd - \
 && rm -r "strongswan-${STRONGSWAN_VERSION}" \
 && apk del .build-deps

COPY common.sh /common.sh
COPY configure-ipsec.sh /configure-ipsec.sh
COPY configure-strongswan.sh /configure-strongswan.sh
COPY entrypoint.sh /entrypoint.sh

VOLUME /etc/ipsec.d

EXPOSE 500/udp
EXPOSE 4500/udp

CMD ["/usr/sbin/ipsec", "start", "--nofork"]
ENTRYPOINT ["/entrypoint.sh"]
