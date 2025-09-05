#!/bin/bash
cd /root/scripts/dkim/
rm -rf /root/scripts/dkim/private_keys
rm -rf /root/scripts/dkim/public_keys
rm -rf /root/scripts/dkim/pub_dkim_key.txt

mkdir /root/scripts/dkim/private_keys
mkdir /root/scripts/dkim/public_keys

########################################################################################################################
## How to do extra long DKIM keys, less than 256 characters. Take into account the extra characters (parens and apostrophes)
########################################################################################################################

# key1._domainkey    IN    TXT ("v=DKIM1; k=rsa; s=email; p=FIBIjANBgkqhkiG9w0BAQEFAIDOJJFDEIBCgKCAQEA75yHQfuVRf9S2+OY/aA9Oe1cgic7nsOatmw4F8DK64eTkLGPhWJXTuq2qdw1ZOBNGyhXAFy/9oksN01rndsI99j3/L3rZIlSFySUaB5v10i+Y5Wi1wWOIlFbZuLM4sf7GPdEY+6w5nwrUE+3psff2y0wpZvwszgXfX4JPN+LfBvM6KgMUnuM7B"
# key1._domainkey    IN    TXT "qSyzmXlnOz4ipVS4bk9t2Ic7dG7FUVgoJhnRz1dcYdHZ6DAM/ege1KkfWxALZtEi7xBIv3kvM4EqNwg1limc/VksPbABz61MR0T+HxD4ypMl6lb+I8pfrZuMj/R2TPrgWQytJEp5MQxlNObi6k4mioQzu2LqGiQwIDAQAB")

domain="$(cat /root/scripts/dkim/domain.txt)"

while read -r domain <&3 ; 
do 

openssl genrsa -out /root/scripts/dkim/private_keys/key1_dkim.$domain.pem 1024
openssl rsa -in /root/scripts/dkim/private_keys/key1_dkim.$domain.pem -pubout -out /root/scripts/dkim/public_keys/public_key1_dkim.$domain.pem

cat /root/scripts/dkim/public_keys/public_key1_dkim."$domain".pem > /root/scripts/dkim/$domain.aa

#Strip the Header 
sed -i -r 's/^-----BEGIN PUBLIC KEY-----//' /root/scripts/dkim/*.aa

#Stript the Footer
sed -i -r 's/^-----END PUBLIC KEY-----//' /root/scripts/dkim/*.aa

#Strip all line breaks
sed -i ':a;N;$!ba;s/\n//g' /root/scripts/dkim/*.aa

echo "Done Generating and Copying keys"

done 3</root/scripts/dkim/domain.txt

cd /root/scripts/dkim/

cat *.aa > pub_dkim_key.txt
rm -rf *.aa

cd /root/scripts/dkim/private_keys/
cp *.pem /etc/pmta/domainkeys/
chown pmta:pmta /etc/pmta/domainkeys/

cd /root/scripts/dkim/public_keys/
cp *.pem /etc/publickeys/
chown pmta:pmta /etc/publickeys/

echo "Done"
