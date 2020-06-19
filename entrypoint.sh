#!/usr/bin/env bash

set -euo pipefail

VPN_DOMAIN_REVERSED="$(tr '.' $'\n' <<< "${VPN_DOMAIN}" | tac | paste -s -d '.')"

mkdir -p /etc/ipsec.d/{cacerts,certs,private}

CA_NAME="${VPN_NAME} Root CA"
CA_KEY=/etc/ipsec.d/private/ca.pem
CA_CERT=/etc/ipsec.d/cacerts/ca.cert.pem

SERVER_KEY=/etc/ipsec.d/private/server.pem
SERVER_CERT=/etc/ipsec.d/certs/server.cert.pem

CLIENT_KEY=/etc/ipsec.d/private/client.pem
CLIENT_CERT=/etc/ipsec.d/certs/client.cert.pem
CLIENT_CERT_P12=/etc/ipsec.d/client.cert.p12
CLIENT_MOBILECONFIG=/etc/ipsec.d/client.mobileconfig

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

cat > /etc/ipsec.conf <<EOF
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
  leftca="$(basename "${CA_CERT}")"
  leftcert="$(basename "${SERVER_CERT}")"
  leftsendcert=always
  leftsubnet=0.0.0.0/0

  right=%any
  rightid="client@${VPN_DOMAIN}"
  rightauth=pubkey
  rightcert="$(basename "${CLIENT_CERT}")"
  rightsourceip=%dhcp

  eap_identity=%identity
EOF

cat > /etc/ipsec.secrets <<EOF
: RSA "$(basename "${SERVER_KEY}")"
EOF

UUID1="$(uuidgen)"
UUID2="$(uuidgen)"
UUID3="$(uuidgen)"
UUID4="$(uuidgen)"
UUID5="$(uuidgen)"

cat > "${CLIENT_MOBILECONFIG}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>PayloadContent</key>
  <array>
    <dict>
      <key>Password</key>
      <string>${VPN_P12_PASSWORD}</string>
      <key>PayloadCertificateFileName</key>
      <string>client.cert.p12</string>
      <key>PayloadContent</key>
      <data>$(base64 "${CLIENT_CERT_P12}")</data>
      <key>PayloadDescription</key>
      <string>PKCS12 Certificate</string>
      <key>PayloadDisplayName</key>
      <string>${VPN_NAME} Client Certificate</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs12.${UUID1}</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs12</string>
      <key>PayloadUUID</key>
      <string>${UUID1}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>ca.cer</string>
      <key>PayloadContent</key>
      <data>$(base64 "${CA_CERT}")</data>
      <key>PayloadDescription</key>
      <string>CA Certificate</string>
      <key>PayloadDisplayName</key>
      <string>${CA_NAME}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.root.${UUID2}</string>
      <key>PayloadType</key>
      <string>com.apple.security.root</string>
      <key>PayloadUUID</key>
      <string>${UUID2}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
    <dict>
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
        <string>${UUID1}</string>
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
      <key>IPv4</key>
      <dict>
        <key>OverridePrimary</key>
        <integer>0</integer>
      </dict>
      <key>PayloadDescription</key>
      <string>VPN Settings</string>
      <key>PayloadDisplayName</key>
      <string>${VPN_NAME}</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.vpn.managed.${UUID3}</string>
      <key>PayloadType</key>
      <string>com.apple.vpn.managed</string>
      <key>PayloadUUID</key>
      <string>${UUID3}</string>
      <key>PayloadVersion</key>
      <real>1</real>
      <key>Proxies</key>
      <dict>
        <key>HTTPEnable</key>
        <integer>0</integer>
        <key>HTTPSEnable</key>
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
    </dict>
    <dict>
      <key>PayloadCertificateFileName</key>
      <string>server.cer</string>
      <key>PayloadContent</key>
      <data>$(base64 "${SERVER_CERT}")</data>
      <key>PayloadDescription</key>
      <string>PKCS1 Certificate</string>
      <key>PayloadDisplayName</key>
      <string>${VPN_NAME} Server Certificate</string>
      <key>PayloadIdentifier</key>
      <string>com.apple.security.pkcs1.${UUID4}</string>
      <key>PayloadType</key>
      <string>com.apple.security.pkcs1</string>
      <key>PayloadUUID</key>
      <string>${UUID4}</string>
      <key>PayloadVersion</key>
      <integer>1</integer>
    </dict>
  </array>
  <key>PayloadDisplayName</key>
  <string>${VPN_NAME}</string>
  <key>PayloadIdentifier</key>
  <string>${VPN_DOMAIN_REVERSED}</string>
  <key>PayloadRemovalDisallowed</key>
  <false/>
  <key>PayloadType</key>
  <string>Configuration</string>
  <key>PayloadUUID</key>
  <string>${UUID5}</string>
  <key>PayloadVersion</key>
  <integer>1</integer>
</dict>
</plist>
EOF

exec "${@}"
