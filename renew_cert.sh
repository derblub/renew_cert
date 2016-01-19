#!/bin/sh

TESTING=false
DOMAIN=$1
WEBROOT=${2:-"/var/www/vhosts/$DOMAIN/httpdocs"}  # optional parameter 
ADMIN_CERT=${3:-false}  # optional parameter


####################################################################
# Remaining days to expire before try renew.
# Let's Encrypt certificates expire in 90 days (on 1/2016).
# Currently, Let's Encrypt recommends renewal after 60 days.
DAYS_REMAINING=30

# Path to letsencrypt-auto script
LE_BIN="/root/letsencrypt/letsencrypt-auto"

# Path to letsencrypt certificates
LE_DIR="/etc/letsencrypt"

# Path to certificates and key
CERT="$LE_DIR/live/$DOMAIN/cert.pem"
CHAIN="$LE_DIR/live/$DOMAIN/chain.pem"
FULLCHAIN="$LE_DIR/live/$DOMAIN/fullchain.pem"
PRIVKEY="$LE_DIR/live/$DOMAIN/privkey.pem"

# Path to Plesk certificate binary
P_BIN="/opt/psa/bin/certificate"

if [[ -z ${DOMAIN} ]]; then
    echo "ERROR:  domain parameter missing"
    echo
    exit 1
fi

echo
echo " Let's Encrypt ${DOMAIN}! "
echo "+---------------------------------+"
echo

# get test cert only?
TEST_CERT=""
if [ "$TESTING" = true ]; then
    echo "TEST-CERTIFICATE-MODE ACTIVE"
    echo
    TEST_CERT="--test-cert"
fi


# cert missing?
if [ ! -f ${CERT} ]; then
    echo "ERROR:   Certificate \"$CERT\" not found."
    echo
    exit 1
fi

# chain missing?
if [ ! -f ${FULLCHAIN} ]; then
    echo "ERROR:   Certificate CHAIN \"$FULLCHAIN\" not found."
    echo
    exit 1
fi

# key missing?
if [ ! -f ${PRIVKEY} ]; then
    echo "ERROR:   Privatekey \"$PRIVKEY\" not found."
    echo
    exit 1
fi


# -----------------------------------------------------------------------------
# examines cert.pem certificate file and returns in how many days expire.
# Result value is placed in $DAYS_EXP global variable.
get_days_exp(){
    local d1=$(date -d "`openssl x509 -in $1 -text -noout|grep "Not After"|cut -c 25-`" +%s)
    local d2=$(date -d "now" +%s)
    # Return result in global variable
    DAYS_EXP=$(echo \( $d1 - $d2 \) / 86400 |bc)
}
# -----------------------------------------------------------------------------

get_days_exp "${CERT}"
echo -n "Certificate will expire in ${DAYS_EXP} days. "
# Save $DAYS_EXP value for later use
OLD_DAYS_EXP=$DAYS_EXP


# renew needed?
if [ "$DAYS_EXP" -gt "$DAYS_REMAINING" ]; then
    echo "($DAYS_EXP >= $DAYS_REMAINING) Renewal not necessary."
    echo
    exit 1
else
    echo "($DAYS_EXP < $DAYS_REMAINING) Trying to renew now..."
    echo

    ${LE_BIN} --text --agree-tos --renew-by-default --webroot -w "${WEBROOT}" --domain "${DOMAIN}" auth "${TEST_CERT}"
    echo
    
    # After renewal, try to determine when does the new certificate expire.
    # If renewal went OK, new value of $DAYS_EXP should be greater than $OLD_DAYS_EXP.
    get_days_exp "${CERT}"
    
    # Is $DAYS_EXP now less than or equal to $OLD_DAYS_EXP? If not, then renewal has failed.
    # If renewal went OK, then $DAYS_EXP must be greater than $OLD_DAYS_EXP.
    if [ "$DAYS_EXP" -le "$OLD_DAYS_EXP" ]; then
        echo "ERROR:   Certificate renewal failed."
        echo
        exit 1
    else
        echo "SUCCESS: Certificate was successfully renewed!"
        echo
        echo "Executing Plesk certificate-update..."

        # update certificate in plesk now
        if [ "$ADMIN_CERT" = true ]; then
             OUT=$($P_BIN --update $DOMAIN -admin -default -key-file $PRIVKEY -cert-file $CERT -csr-file $FULLCHAIN)
         else
             OUT=$($P_BIN --update $DOMAIN -domain $DOMAIN -default -key-file $PRIVKEY -cert-file $CERT -csr-file $FULLCHAIN)
         fi
        
        # check for success
        if [[ $OUT == *"certificate '${DOMAIN}' was successfully updated"* ]]; then
            # success!
            echo "$OUT"
            echo
        else
            echo "ERROR:"
            echo "$OUT"
            echo
            exit 1
        fi

        exit 0;
    fi


fi

