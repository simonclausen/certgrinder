#!/usr/local/bin/bash
####################################################
# This file is part of certgrinder.
# The latest version can be found on Github at
# https://github.com/tykling/certgrinder
# along with some documentation.
####################################################

###### CONFIG ########
# your certgrinder server hostname
CERTGRINDER_HOST="certgrinder.example.org"

# x509 info for the CSR
PRIMARY_DOMAIN="example.com"
ALL_DOMAINS="DNS:example.com,DNS:example.net"
COUNTRY="DK"
ORG="ExampleOrg"

# path to openssl config
OPENSSL_CONFIG="/etc/ssl/openssl.cnf"

# whatever command to run after cert renew, remember to add sudo permissions to run this
RENEW_HOOK="sudo pkill -HUP -F /var/run/charybdis/charybdis.pid"

# cert paths
PRIVKEY=~/${PRIMARY_DOMAIN}.key
CERT=~/${PRIMARY_DOMAIN}.crt
CSR=~/${PRIMARY_DOMAIN}.csr

######## CODE ############
# get path for temp cert
TEMPCERT=$(mktemp)

# check if we have a keypair, generate if not
if [ ! -f $PRIVKEY ]; then
        echo "private key $PRIVKEY not found, generating..."
        openssl genrsa -out $PRIVKEY 4096
        if [ $? -ne 0 ]; then
                echo "unable to generate RSA keypair, exiting"
                exit 1
        fi
fi

# do we already have a signed certificate?
if [ -s $CERT ]; then
        if openssl x509 -checkend 2592000 -noout -in $CERT; then
                echo "cert is good for at least another 30 days, exiting"
                exit 0
        else
            echo "cert expires in less than 30 days, rolling new CSR"
        fi
else
        echo "certificate not found, rolling new CSR"
fi

# generate a new CSR
openssl req -new -sha256 -key ${PRIVKEY} -subj "/C=${COUNTRY}/O=${ORG}/CN=${PRIMARY_DOMAIN}" -reqexts SAN -extensions SAN -config <(cat ${OPENSSL_CONFIG} <(printf "[SAN]\nsubjectAltName=${ALL_DOMAINS}")) -out $CSR
if [ $? -ne 0 ]; then
        echo "unable to generate CSR, exiting"
        exit 1
fi

# certificate time
echo "new CSR created, contacting certgrinder server to get certificate ...."
cat $CSR | ssh $CERTGRINDER_HOST /usr/local/bin/csrgrinder > $TEMPCERT
if [ $? -eq 0 ]; then
        # success, we have a new certificate
        cp $TEMPCERT $CERT
        echo "new certificate written to $CERT, running renew hook and exiting..."
        $RENEW_HOOK
else
        echo "unable to get new cert :("
        exit 1
fi

