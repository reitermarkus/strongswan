#!/command/with-contenv bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${0}")"
# shellcheck source=etc/s6-overlay/scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

etc="${ETC:-/etc}"
swanctl_dir="${SWANCTL_DIR:-"${etc}/swanctl"}"

vpn_name="${VPN_NAME?}"
vpn_domain="${VPN_DOMAIN?}"
vpn_domain_reversed="$(tr '.' $'\n' <<< "${vpn_domain}" | tac | paste -s -d '.' -)"
vpn_p12_password="${VPN_P12_PASSWORD?}"

wifi_ssid="${WIFI_SSID?}"

if [[ -z "${SEARCH_DOMAINS-}" ]]; then
  # Try getting domain.
  if search_domain="$(hostname -d 2>/dev/null)"; then
    SEARCH_DOMAINS="${search_domain}"
  else
    # shellcheck disable=SC2016
    echo 'Failed to get domain with `hostname -d`.' >&2
  fi
fi

search_domains=''
for domain in ${SEARCH_DOMAINS//,/ }; do
  search_domains+="$(printf "\n          <string>%s</string>" "${domain}")"
done

ca_name="${vpn_name} Root CA"
ca_key="${swanctl_dir}/private/ca.pem"
ca_cert_basename='ca.cert.pem'
ca_cert="${swanctl_dir}/x509ca/${ca_cert_basename}"

server_key="${swanctl_dir}/private/server.pem"
server_cert_basename='server.cert.pem'
server_cert="${swanctl_dir}/x509/${server_cert_basename}"

client_key="${swanctl_dir}/private/client.pem"
client_cert="${swanctl_dir}/x509/client.cert.pem"
client_cert_p12_basename='client.cert.p12'
client_cert_p12="${swanctl_dir}/${client_cert_p12_basename}"
client_mobileconfig="${swanctl_dir}/client.mobileconfig"

if ! [[ -f "${ca_key}" ]]; then
  tmp="$(mktemp)"
  pki --gen --type rsa --size 4096 --outform pem > "${tmp}"
  mv "${tmp}" "${ca_key}"
fi

if ! [[ -f "${ca_cert}" ]]; then
  tmp="$(mktemp)"
  pki --self --ca --lifetime 3650 --in "${ca_key}" \
    --type rsa --dn "CN=${ca_name}" --outform pem > "${tmp}"
  mv "${tmp}" "${ca_cert}"
fi

if ! [[ -f "${server_key}" ]]; then
  tmp="$(mktemp)"
  pki --gen --type rsa --size 4096 --outform pem > "${tmp}"
  mv "${tmp}" "${server_key}"
fi

if ! [[ -f "${server_cert}" ]]; then
  tmp="$(mktemp)"
  pki --pub --in "${server_key}" --type rsa \
    | pki --issue --lifetime 3650 \
        --cacert "${ca_cert}" --cakey "${ca_key}" \
        --dn "CN=${vpn_domain}" --san "${vpn_domain}" \
        --flag serverAuth --flag ikeIntermediate --outform pem \
        > "${tmp}"
  mv "${tmp}" "${server_cert}"
fi

if ! [[ -f "${client_key}" ]]; then
  tmp="$(mktemp)"
  pki --gen --type rsa --size 4096 --outform pem > "${tmp}"
  mv "${tmp}" "${client_key}"
fi

if ! [[ -f "${client_cert}" ]]; then
  tmp="$(mktemp)"
  pki --pub --in "${client_key}" --type rsa \
    | pki --issue --lifetime 3650 \
      --cacert "${ca_cert}" --cakey "${ca_key}" \
      --dn "CN=client@${vpn_domain}" --san "client@${vpn_domain}" \
      --outform pem > "${tmp}"
  mv "${tmp}" "${client_cert}"
fi

if ! [[ -f "${client_cert_p12}" ]]; then
  tmp="$(mktemp)"
  openssl pkcs12 -export \
    -legacy \
    -in "${client_cert}" -inkey "${client_key}" \
    -name "client@${vpn_domain}" \
    -certfile "${ca_cert}" \
    -caname "${ca_name}" \
    -out "${tmp}" \
    -passout "pass:${vpn_p12_password}"
  mv "${tmp}" "${client_cert_p12}"
fi

cat > "${etc}/strongswan.d/charon-load-all.conf" <<EOF
charon {
  start-scripts {
    all = swanctl --load-all
  }
}
EOF

cat > "${etc}/swanctl/conf.d/ikev2-vpn.conf" <<EOF
connections {
  ikev2-vpn {
    version = 2
    encap = yes
    dpd_delay = 300s
    rekey_time = 0
    local_addrs = %any
    remote_addrs = %any
    send_cert = always
    pools=dhcp
    proposals=chacha20poly1305-prfsha512-x448

    local {
      id = "@${vpn_domain}"
      auth = pubkey
      certs = "${server_cert}"
    }

    remote {
      id = "client@${vpn_domain}"
      auth = pubkey
      cacerts = "${ca_cert}"
      certs = "${client_cert}"
      eap_id = %any
    }

    children {
      ikev2-vpn {
        life_time = 0
        local_ts = 0.0.0.0/0
      }
    }
  }
}
EOF

uuid_namespace="$(uuidgen --sha1 --namespace @dns --name "${vpn_domain}")"
uuid_ca_cert="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name "${ca_cert_basename}")"
uuid_server_cert="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name "${server_cert_basename}")"
uuid_p12_cert="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name "${client_cert_p12_basename}")"
uuid_vpn_settings="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name 'com.apple.vpn.managed')"
uuid_configuration="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name 'configuration')"

cat > "${client_mobileconfig}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.security.root</string>
      <key>PayloadUUID</key>
      <string>${uuid_ca_cert}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.root.${uuid_ca_cert}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadDisplayName</key>
      <string>${ca_name}</string>
      <key>PayloadDescription</key>
      <string>CA Certificate</string>
      <key>PayloadCertificateFileName</key>
      <string>${ca_cert_basename}</string>
      <key>PayloadContent</key>
      <data>$(base64 -w 0 "${ca_cert}")</data>
    </dict>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs1</string>
      <key>PayloadUUID</key>
      <string>${uuid_server_cert}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs1.${uuid_server_cert}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadDisplayName</key>
      <string>${vpn_name} Server Certificate</string>
      <key>PayloadDescription</key>
      <string>PKCS1 Certificate</string>
      <key>PayloadCertificateFileName</key>
      <string>${server_cert_basename}</string>
      <key>PayloadContent</key>
      <data>$(base64 -w 0 "${server_cert}")</data>
    </dict>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>${uuid_p12_cert}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs12.${uuid_p12_cert}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadDisplayName</key>
      <string>${vpn_name} Client Certificate</string>
      <key>PayloadDescription</key>
      <string>PKCS12 Certificate</string>
      <key>PayloadCertificateFileName</key>
      <string>${client_cert_p12_basename}</string>
      <key>PayloadContent</key>
      <data>$(base64 -w 0 "${client_cert_p12}")</data>
      <key>Password</key>
      <string>${vpn_p12_password}</string>
    </dict>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.vpn.managed</string>
      <key>PayloadUUID</key>
      <string>${uuid_vpn_settings}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.vpn.managed.${uuid_vpn_settings}</string>
      <key>PayloadVersion</key>
      <real>1</real>
      <key>PayloadDisplayName</key>
      <string>${vpn_name}</string>
      <key>PayloadDescription</key>
      <string>VPN Settings</string>
      <key>Proxies</key>
      <dict>
        <key>HTTPEnable</key>
        <integer>0</integer>
        <key>HTTPSEnable</key>
        <integer>0</integer>
      </dict>
      <key>IPv4</key>
      <dict>
        <key>OverridePrimary</key>
        <integer>0</integer>
      </dict>
      <key>DNS</key>
      <dict>
        <key>SearchDomains</key>
        <array>${search_domains}
        </array>
      </dict>
      <key>UserDefinedName</key>
      <string>${vpn_name} (IKEv2)</string>
      <key>VPNType</key>
      <string>IKEv2</string>
      <key>IKEv2</key>
      <dict>
        <key>AuthenticationMethod</key>
        <string>Certificate</string>
        <key>ChildSecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>32</integer>
          <key>EncryptionAlgorithm</key>
          <string>ChaCha20Poly1305</string>
          <key>IntegrityAlgorithm</key>
          <string>SHA2-512</string>
          <key>LifeTimeInMinutes</key>
          <integer>1440</integer>
        </dict>
        <key>DeadPeerDetectionRate</key>
        <string>Medium</string>
        <key>DisableMOBIKE</key>
        <integer>0</integer>
        <key>DisableRedirect</key>
        <integer>0</integer>
        <key>EnableCertificateRevocationCheck</key>
        <integer>0</integer>
        <key>EnablePFS</key>
        <integer>1</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>32</integer>
          <key>EncryptionAlgorithm</key>
          <string>ChaCha20Poly1305</string>
          <key>IntegrityAlgorithm</key>
          <string>SHA2-512</string>
          <key>LifeTimeInMinutes</key>
          <integer>1440</integer>
        </dict>
        <key>LocalIdentifier</key>
        <string>client@${vpn_domain}</string>
        <key>PayloadCertificateUUID</key>
        <string>${uuid_p12_cert}</string>
        <key>RemoteAddress</key>
        <string>${vpn_domain}</string>
        <key>RemoteIdentifier</key>
        <string>${vpn_domain}</string>
        <key>UseConfigurationAttributeInternalIPSubnet</key>
        <integer>0</integer>
        <key>OnDemandEnabled</key>
        <integer>1</integer>
        <key>OnDemandRules</key>
        <array>
          <dict>
            <key>Action</key>
            <string>Disconnect</string>
            <key>InterfaceTypeMatch</key>
            <string>WiFi</string>
            <key>SSIDMatch</key>
            <array>
              <string>${wifi_ssid}</string>
            </array>
          </dict>
          <dict>
            <key>Action</key>
            <string>Connect</string>
            <key>InterfaceTypeMatch</key>
            <string>WiFi</string>
          </dict>
          <dict>
            <key>Action</key>
            <string>Connect</string>
            <key>InterfaceTypeMatch</key>
            <string>Cellular</string>
          </dict>
          <dict>
            <key>Action</key>
            <string>Ignore</string>
          </dict>
        </array>
      </dict>
    </dict>
  </array>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>${uuid_configuration}</string>
  <key>PayloadIdentifier</key>
  <string>${vpn_domain_reversed}</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadDisplayName</key>
  <string>${vpn_name}</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
</dict>
</plist>
EOF
