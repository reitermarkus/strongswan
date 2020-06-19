# Strongswan Docker Image

Starts an IKEv2 VPN server and automatically generates a `.p12` certificate and a `.mobileconfig` configuration file.

## Docker Compose Usage

### `docker-compose.yml`

```yml
version: '3'
services:
  watchtower:
    container_name: watchtower
    image: containrrr/watchtower
    environment:
      - WATCHTOWER_CLEANUP=true
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
    restart: unless-stopped
  strongswan:
    container_name: strongswan
    image: reitermarkus/strongswan
    volumes:
      - /etc/ipsec.d:/etc/ipsec.d
    environment:
      - VPN_NAME=Example VPN
      - WIFI_SSID=Example WiFi
      - VPN_DOMAIN=vpn.example.com
      - VPN_P12_PASSWORD=password
    privileged: yes
    network_mode: host
    restart: unless-stopped
```

You can either find the certificate and configuartion files directly on the host in the mounted directory specified or alternatively you can copy them out of the running container using

```
docker cp strongswan:/etc/ipsec.d/client.mobileconfig .
docker cp strongswan:/etc/ipsec.d/client.cert.p12 .
```
