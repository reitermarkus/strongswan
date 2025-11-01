# Strongswan Docker Image

Starts an IKEv2 VPN server and automatically generates a `.p12` certificate and a `.mobileconfig` configuration file.

## Variables

| Name | Description |
|------|-------------|
| `VPN_NAME` | Name of the VPN, e.g. `Example VPN`. |
| `VPN_DOMAIN` | Domain for accessing the VPN, e.g. `vpn.example.org`. |
| `VPN_P12_PASSWORD` | Password for the P12 certificate. |
| `WIFI_SSID` | Name of the WiFi network SSID, e.g. `Example WiFi`. |
| `SEARCH_DOMAINS` | Comma-separated list of search domains for your network, e.g. `local,example.org`. Defaults to the return value of `hostname -d`. |
| `WEBSERVER` | If set to `true`, a webserver is started which serves the `.mobileconfig` profile. |
| `WEBSERVER_PORT` | The webserver listening port. |

## Docker Compose Usage

### `docker-compose.yml`

```yml
version: '3'
services:
  strongswan:
    container_name: strongswan
    image: ghcr.io/reitermarkus/strongswan:latest
    volumes:
      - /etc/swanctl:/etc/swanctl
    environment:
      - VPN_NAME=Example VPN
      - WIFI_SSID=Example WiFi
      - VPN_DOMAIN=vpn.example.com
      - VPN_P12_PASSWORD=example123
    privileged: yes
    network_mode: host
    restart: unless-stopped
```

If `WEBSERVER` is `false`, you can copy the configuration file out of the running container using

```sh
docker cp strongswan:/var/www/localhost/htdocs/client.mobileconfig .
```
