#!/usr/bin/env bash

set -euo pipefail

ETC="${ETC:-/etc}"
IPSEC_DIR="${IPSEC_DIR:-"${ETC}/ipsec.d"}"
IPSEC_CONF="${IPSEC_CONF:-"${ETC}/ipsec.conf"}"
IPSEC_SECRETS="${IPSEC_SECRETS:-"${ETC}/ipsec.secrets"}"

VPN_DOMAIN_REVERSED="$(tr '.' $'\n' <<< "${VPN_DOMAIN}" | tac | paste -s -d '.' -)"

mkdir -p "${IPSEC_DIR}"/{cacerts,certs,private}

CA_NAME="${VPN_NAME} Root CA"
CA_KEY="${IPSEC_DIR}/private/ca.pem"
CA_CERT_BASENAME='ca.cert.pem'
CA_CERT="${IPSEC_DIR}/cacerts/${CA_CERT_BASENAME}"

SERVER_KEY="${IPSEC_DIR}/private/server.pem"
SERVER_CERT_BASENAME='server.cert.pem'
SERVER_CERT="${IPSEC_DIR}/certs/${SERVER_CERT_BASENAME}"

CLIENT_KEY="${IPSEC_DIR}/private/client.pem"
CLIENT_CERT="${IPSEC_DIR}/certs/client.cert.pem"
CLIENT_CERT_P12_BASENAME='client.cert.p12'
CLIENT_CERT_P12="${IPSEC_DIR}/${CLIENT_CERT_P12_BASENAME}"
CLIENT_MOBILECONFIG="${IPSEC_DIR}/client.mobileconfig"

if ! [[ -f "${CA_KEY}" ]]; then
  ipsec pki --gen --type rsa --size 4096 --outform pem > "${CA_KEY}"
fi

if ! [[ -f "${CA_CERT}" ]]; then
  ipsec pki --self --ca --lifetime 3650 --in "${CA_KEY}" \
    --type rsa --dn "CN=${CA_NAME}" --outform pem > "${CA_CERT}"
fi

if ! [[ -f "${SERVER_KEY}" ]]; then
  ipsec pki --gen --type rsa --size 4096 --outform pem > "${SERVER_KEY}"
fi

if ! [[ -f "${SERVER_CERT}" ]]; then
  ipsec pki --pub --in "${SERVER_KEY}" --type rsa \
    | ipsec pki --issue --lifetime 3650 \
        --cacert "${CA_CERT}" --cakey "${CA_KEY}" \
        --dn "CN=${VPN_DOMAIN}" --san "${VPN_DOMAIN}" \
        --flag serverAuth --flag ikeIntermediate --outform pem \
        > "${SERVER_CERT}"
fi

if ! [[ -f "${CLIENT_KEY}" ]]; then
  ipsec pki --gen --type rsa --size 4096 --outform pem > "${CLIENT_KEY}"
fi

if ! [[ -f "${CLIENT_CERT}" ]]; then
  ipsec pki --pub --in "${CLIENT_KEY}" --type rsa \
    | ipsec pki --issue --lifetime 3650 \
      --cacert "${CA_CERT}" --cakey "${CA_KEY}" \
      --dn "CN=client@${VPN_DOMAIN}" --san "client@${VPN_DOMAIN}" \
      --outform pem > "${CLIENT_CERT}"
fi

if ! [[ -f "${CLIENT_CERT_P12}" ]]; then
  openssl pkcs12 -export \
    -in "${CLIENT_CERT}" -inkey "${CLIENT_KEY}" \
    -name "client@${VPN_DOMAIN}" \
    -certfile "${CA_CERT}" \
    -caname "${CA_NAME}" \
    -out "${CLIENT_CERT_P12}" \
    -passout "pass:${VPN_P12_PASSWORD}"
fi

cat > "${IPSEC_CONF}" <<EOF
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
  leftid="@${VPN_DOMAIN}"
  leftauth=pubkey
  leftca="${CA_CERT}"
  leftcert="${SERVER_CERT}"
  leftsendcert=always
  leftsubnet=0.0.0.0/0

  right=%any
  rightid="client@${VPN_DOMAIN}"
  rightauth=pubkey
  rightca=%same
  rightcert="${CLIENT_CERT}"
  rightsourceip=%dhcp

  eap_identity=%identity
EOF

cat > "${IPSEC_SECRETS}" <<EOF
: RSA "${SERVER_KEY}"
EOF

if uuidgen --sha1 --namespace @dns --name example.org &>/dev/null; then
  UUID_NAMESPACE="$(uuidgen --sha1 --namespace @dns --name "${VPN_DOMAIN}")"
  UUID_CA_CERT="$(uuidgen --sha1 --namespace "${UUID_NAMESPACE}" --name "${CA_CERT_BASENAME}")"
  UUID_SERVER_CERT="$(uuidgen --sha1 --namespace "${UUID_NAMESPACE}" --name "${SERVER_CERT_BASENAME}")"
  UUID_P12_CERT="$(uuidgen --sha1 --namespace "${UUID_NAMESPACE}" --name "${CLIENT_CERT_P12_BASENAME}")"
  UUID_VPN_SETTINGS="$(uuidgen --sha1 --namespace "${UUID_NAMESPACE}" --name 'com.apple.vpn.managed')"
  UUID_CONFIGURATION="$(uuidgen --sha1 --namespace "${UUID_NAMESPACE}" --name 'configuration')"
else
  UUID_NAMESPACE="$(uuidgen)"
  UUID_CA_CERT="$(uuidgen)"
  UUID_SERVER_CERT="$(uuidgen)"
  UUID_P12_CERT="$(uuidgen)"
  UUID_VPN_SETTINGS="$(uuidgen)"
  UUID_CONFIGURATION="$(uuidgen)"
fi

cat > "${CLIENT_MOBILECONFIG}" <<EOF
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
      <string>${UUID_CA_CERT}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.root.${UUID_CA_CERT}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadDisplayName</key>
      <string>${CA_NAME}</string>
      <key>PayloadDescription</key>
      <string>CA Certificate</string>
      <key>PayloadCertificateFileName</key>
      <string>${CA_CERT_BASENAME}</string>
      <key>PayloadContent</key>
      <data>$(base64 "${CA_CERT}")</data>
    </dict>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs1</string>
      <key>PayloadUUID</key>
      <string>${UUID_SERVER_CERT}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs1.${UUID_SERVER_CERT}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadDisplayName</key>
      <string>${VPN_NAME} Server Certificate</string>
      <key>PayloadDescription</key>
      <string>PKCS1 Certificate</string>
      <key>PayloadCertificateFileName</key>
      <string>${SERVER_CERT_BASENAME}</string>
      <key>PayloadContent</key>
      <data>$(base64 "${SERVER_CERT}")</data>
    </dict>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>${UUID_P12_CERT}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs12.${UUID_P12_CERT}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
      <key>PayloadDisplayName</key>
      <string>${VPN_NAME} Client Certificate</string>
      <key>PayloadDescription</key>
      <string>PKCS12 Certificate</string>
      <key>PayloadCertificateFileName</key>
      <string>${CLIENT_CERT_P12_BASENAME}</string>
      <key>PayloadContent</key>
      <data>$(base64 "${CLIENT_CERT_P12}")</data>
      <key>Password</key>
      <string>${VPN_P12_PASSWORD}</string>
    </dict>
    <dict>
      <key>PayloadType</key>
      <string>com.apple.vpn.managed</string>
      <key>PayloadUUID</key>
      <string>${UUID_VPN_SETTINGS}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.vpn.managed.${UUID_VPN_SETTINGS}</string>
      <key>PayloadVersion</key>
      <real>1</real>
      <key>PayloadDisplayName</key>
      <string>${VPN_NAME}</string>
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
        <array>
          <string>local</string>
        </array>
      </dict>
      <key>UserDefinedName</key>
      <string>${VPN_NAME} (IKEv2)</string>
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
        <string>client@${VPN_DOMAIN}</string>
        <key>PayloadCertificateUUID</key>
        <string>${UUID_P12_CERT}</string>
        <key>RemoteAddress</key>
        <string>${VPN_DOMAIN}</string>
        <key>RemoteIdentifier</key>
        <string>${VPN_DOMAIN}</string>
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
              <string>${WIFI_SSID}</string>
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
  <string>${UUID_CONFIGURATION}</string>
  <key>PayloadIdentifier</key>
  <string>${VPN_DOMAIN_REVERSED}</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
  <key>PayloadDisplayName</key>
  <string>${VPN_NAME}</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
</dict>
</plist>
EOF
