#!/command/with-contenv bash
# shellcheck shell=bash

set -euo pipefail

SCRIPT_DIR="$(dirname "${0}")"
# shellcheck source=etc/s6-overlay/scripts/common.sh
source "${SCRIPT_DIR}/common.sh"

etc="${ETC:-/etc}"
ipsec_dir="${IPSEC_DIR:-"${etc}/ipsec.d"}"
ipsec_conf="${IPSEC_CONF:-"${etc}/ipsec.conf"}"
ipsec_secrets="${IPSEC_SECRETS:-"${etc}/ipsec.secrets"}"

vpn_name="${VPN_NAME?}"
vpn_domain="${VPN_DOMAIN?}"
vpn_domain_reversed="$(tr '.' $'\n' <<< "${vpn_domain}" | tac | paste -s -d '.' -)"
vpn_p12_password="${VPN_P12_PASSWORD?}"

wifi_ssid="${WIFI_SSID?}"

if [[ -z "${SEARCH_DOMAINS-}" ]]; then
  SEARCH_DOMAINS="$(hostname -d)"
fi

search_domains=''
for domain in ${SEARCH_DOMAINS//,/ }; do
  search_domains+="$(printf "\n          <string>%s</string>" "${domain}")"
done

ca_name="${vpn_name} Root CA"
ca_key="${ipsec_dir}/private/ca.pem"
ca_cert_basename='ca.cert.pem'
ca_cert="${ipsec_dir}/cacerts/${ca_cert_basename}"

server_key="${ipsec_dir}/private/server.pem"
server_cert_basename='server.cert.pem'
server_cert="${ipsec_dir}/certs/${server_cert_basename}"

client_key="${ipsec_dir}/private/client.pem"
client_cert="${ipsec_dir}/certs/client.cert.pem"
client_cert_p12_basename='client.cert.p12'
client_cert_p12="${ipsec_dir}/${client_cert_p12_basename}"
client_mobileconfig="${ipsec_dir}/client.mobileconfig"

mkdir -p "${ipsec_dir}"/{aacerts,acerts,cacerts,certs,crls,ocspcerts,private}

if ! [[ -f "${ca_key}" ]]; then
  tmp="$(mktemp)"
  ipsec pki --gen --type rsa --size 4096 --outform pem > "${tmp}"
  mv "${tmp}" "${ca_key}"
fi

if ! [[ -f "${ca_cert}" ]]; then
  tmp="$(mktemp)"
  ipsec pki --self --ca --lifetime 3650 --in "${ca_key}" \
    --type rsa --dn "CN=${ca_name}" --outform pem > "${tmp}"
  mv "${tmp}" "${ca_cert}"
fi

if ! [[ -f "${server_key}" ]]; then
  tmp="$(mktemp)"
  ipsec pki --gen --type rsa --size 4096 --outform pem > "${tmp}"
  mv "${tmp}" "${server_key}"
fi

if ! [[ -f "${server_cert}" ]]; then
  tmp="$(mktemp)"
  ipsec pki --pub --in "${server_key}" --type rsa \
    | ipsec pki --issue --lifetime 3650 \
        --cacert "${ca_cert}" --cakey "${ca_key}" \
        --dn "CN=${vpn_domain}" --san "${vpn_domain}" \
        --flag serverAuth --flag ikeIntermediate --outform pem \
        > "${tmp}"
  mv "${tmp}" "${server_cert}"
fi

if ! [[ -f "${client_key}" ]]; then
  tmp="$(mktemp)"
  ipsec pki --gen --type rsa --size 4096 --outform pem > "${tmp}"
  mv "${tmp}" "${client_key}"
fi

if ! [[ -f "${client_cert}" ]]; then
  tmp="$(mktemp)"
  ipsec pki --pub --in "${client_key}" --type rsa \
    | ipsec pki --issue --lifetime 3650 \
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

cat > "${ipsec_conf}" <<EOF
config setup
  charondebug="ike 1, knl 1, cfg 0"
  uniqueids=no

conn ikev2-vpn
  auto=add
  compress=no
  type=tunnel
  keyexchange=ikev2
  ike=aes256-sha256-modp1024,3des-sha1-modp1024,aes256-sha1-modp1024!
  esp=aes256-sha256,3des-sha1,aes256-sha1!
  fragmentation=yes
  forceencaps=yes

  dpdaction=clear
  dpddelay=300s
  rekey=no

  left=%any
  leftid="@${vpn_domain}"
  leftauth=pubkey
  leftca="${ca_cert}"
  leftcert="${server_cert}"
  leftsendcert=always
  leftsubnet=0.0.0.0/0

  right=%any
  rightid="client@${vpn_domain}"
  rightauth=pubkey
  rightca=%same
  rightcert="${client_cert}"
  rightsourceip=%dhcp

  eap_identity=%identity
EOF

cat > "${ipsec_secrets}" <<EOF
: RSA "${server_key}"
EOF

if uuidgen --sha1 --namespace @dns --name example.org &>/dev/null; then
  uuid_namespace="$(uuidgen --sha1 --namespace @dns --name "${vpn_domain}")"
  uuid_ca_cert="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name "${ca_cert_basename}")"
  uuid_server_cert="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name "${server_cert_basename}")"
  uuid_p12_cert="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name "${client_cert_p12_basename}")"
  uuid_vpn_settings="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name 'com.apple.vpn.managed')"
  uuid_configuration="$(uuidgen --sha1 --namespace "${uuid_namespace}" --name 'configuration')"
else
  uuid_namespace="$(uuidgen)"
  uuid_ca_cert="$(uuidgen)"
  uuid_server_cert="$(uuidgen)"
  uuid_p12_cert="$(uuidgen)"
  uuid_vpn_settings="$(uuidgen)"
  uuid_configuration="$(uuidgen)"
fi

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
          <integer>2</integer>
          <key>EncryptionAlgorithm</key>
          <string>3DES</string>
          <key>IntegrityAlgorithm</key>
          <string>SHA1-96</string>
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
        <integer>0</integer>
        <key>IKESecurityAssociationParameters</key>
        <dict>
          <key>DiffieHellmanGroup</key>
          <integer>2</integer>
          <key>EncryptionAlgorithm</key>
          <string>3DES</string>
          <key>IntegrityAlgorithm</key>
          <string>SHA1-96</string>
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
