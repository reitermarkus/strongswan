FROM alpine:3.22.2

ARG STRONGSWAN_VERSION=5.9.10
ARG S6_OVERLAY_VERSION=3.1.4.1

RUN apk add --no-cache \
      bash~=5.2 \
      iptables~=1.8 \
      nmap=~7.93 \
      util-linux~=2.41 \
      gmp~=6.2 \
      openssl~=3.5 \
      libcurl~=7.88 \
      python3~=3.12 \
      sqlite-libs~=3.49 \
 \
 && apk add --no-cache --virtual .build-deps \
      build-base~=0.5 \
      linux-headers~=5.19 \
      gmp-dev~=6.2 \
      curl-dev~=7.88 \
      sqlite-dev~=3.40 \
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
 && apk del .build-deps \
 \
 && ARCH="$(uname -m)" \
 && export ARCH \
 && wget --quiet "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" \
 && tar -C / -Jxpf s6-overlay-noarch.tar.xz \
 && rm s6-overlay-noarch.tar.xz \
 && wget --quiet "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${ARCH}.tar.xz" \
 && tar -C / -Jxpf "s6-overlay-${ARCH}.tar.xz" \
 && rm "s6-overlay-${ARCH}.tar.xz"

ENV PATH="/usr/local/bin:${PATH}"

COPY etc /etc
COPY www /var/www

# Generating keys takes longer than the default timeout of 5 seconds.
ENV S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0

ENTRYPOINT ["/init"]
