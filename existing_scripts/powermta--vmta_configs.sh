#!/bin/bash
# Required Files -- brand_replace.txt cpm_replace.txt domain.txt ip.txt mailer.txt mailer_replace.txt pool_replace.txt

# ^.*smtp-listener
# Regex to remove everything before a string, in this case smtp-listener

domain="$(cat domain.txt)"
ip="$(cat ip.txt)"
mailer="$(cat mailer.txt)"

# Create folder to store all files 
mkdir $(date +"%Y_%m_%d_%H-%M")
cd $(date +"%Y_%m_%d_%H-%M")
mkdir add_a_records
mkdir ptr
mkdir pmta
cd ..

touch third_octive.txt
touch last_octive.txt
touch last_digit_third_octive.txt

echo "Seperate the IP into the correct files"
cut -d '.' -f 3 ip.txt >> third_octive.txt
cut -d '.' -f 4 ip.txt >> last_octive.txt
cat third_octive.txt | grep -o '.$' >> last_digit_third_octive.txt

last_digit_third_octive="$(cat last_digit_third_octive.txt)"
third_octive="$(cat third_octive.txt)"
last_octive="$(cat last_octive.txt)"

echo "Adding Blank Lines to EOF(s)"
sed -i '' -e '$a\' domain.txt
sed -i '' -e '$a\' ip.txt
sed -i '' -e '$a\' last_digit_third_octive.txt
sed -i '' -e '$a\' third_octive.txt
sed -i '' -e '$a\' last_octive.txt

echo "" >> brand_replace.txt
echo "" >> cpm_replace.txt
echo "" >> domain.txt
echo "" >> ip.txt
echo "" >> mailer.txt
echo "" >> mailer_replace.txt
echo "" >> pool_replace.txt

# Create Needed File(s)
echo "# Create Needed File(s)"

while read -u 3 -r domain;
do

touch "$domain"_dkim.txt
touch "$domain"_domain_seperator.txt
touch "$domain"_smtp-listener_vmta_config.txt
touch "$domain"_virtual-mta-pool_vmta_config.txt
touch "$domain"_virtual-mta_vmta_config.txt

done 3<domain.txt

############################# -- ############################# -- #############################
############################# -- ############################# -- #############################
while read -u 3 -r domain &&
	  read -u 4 -r ip &&	  
	  read -u 5 -r last_digit_third_octive &&
	  read -u 6 -r third_octive &&
	  read -u 7 -r last_octive &&
	  read -u 8 -r mailer;
do

echo "Creating Domain Seperator for $domain"

echo "
##################################### $domain ######################################################
" >> "$domain"_domain_seperator.txt

done 3<domain.txt 4<ip.txt 5<last_digit_third_octive.txt 6<third_octive.txt 7<last_octive.txt 8<mailer.txt

############################# -- ############################# -- #############################
############################# -- ############################# -- #############################
while read -u 3 -r domain &&
	  read -u 4 -r ip &&	  
	  read -u 5 -r last_digit_third_octive &&
	  read -u 6 -r third_octive &&
	  read -u 7 -r last_octive &&
	  read -u 8 -r mailer;
do

echo "Creating smtp-listener for $domain"

echo "
$mailer_$domain smtp-listener $ip:10025
" >> "$domain"_smtp-listener_vmta_config.txt

done 3<domain.txt 4<ip.txt 5<last_digit_third_octive.txt 6<third_octive.txt 7<last_octive.txt 8<mailer.txt

############################# -- ############################# -- #############################
############################# -- ############################# -- #############################
while read -u 3 -r domain &&
	  read -u 4 -r ip &&	  
	  read -u 5 -r last_digit_third_octive &&
	  read -u 6 -r third_octive &&
	  read -u 7 -r last_octive &&
	  read -u 8 -r mailer;
do

echo "Creating virtual-mta host for $domain"

echo "
<virtual-mta $domain.c$last_digit_third_octive.$last_octive>
smtp-source-host $ip mailer$mailer-vmta-$third_octive-$last_octive.$domain
</virtual-mta>
" >> "$domain"_virtual-mta_vmta_config.txt

done 3<domain.txt 4<ip.txt 5<last_digit_third_octive.txt 6<third_octive.txt 7<last_octive.txt 8<mailer.txt

############################# -- ############################# -- #############################
############################# -- ############################# -- #############################
while read -u 3 -r domain &&
	  read -u 4 -r ip &&	  
	  read -u 5 -r last_digit_third_octive &&
	  read -u 6 -r third_octive &&
	  read -u 7 -r last_octive &&
	  read -u 8 -r mailer;
do

echo "Creating virtual-mta pools for $domain"

echo "
$domain virtual-mta $domain.c$last_digit_third_octive.$last_octive
" >> "$domain"_virtual-mta-pool_vmta_config.txt

done 3<domain.txt 4<ip.txt 5<last_digit_third_octive.txt 6<third_octive.txt 7<last_octive.txt 8<mailer.txt

touch ptr_records.txt
touch add_a_records_ip.txt
touch add_a_records_domain.txt
touch add_a_records_record.txt

############################# -- ############################# -- #############################
############################# -- ############################# -- #############################
while read -u 3 -r domain &&
	  read -u 4 -r ip &&	  
	  read -u 5 -r last_digit_third_octive &&
	  read -u 6 -r third_octive &&
	  read -u 7 -r last_octive &&
	  read -u 8 -r mailer;
do

echo "Creating PTRs & A records for $domain"

echo "
$ip.in-addr.arpa. IN PTR  mailer$mailer-vmta-$third_octive-$last_octive.$domain
" >> ptr_records.txt

echo "
$ip
" >> add_a_records_ip.txt

echo "
$domain
" >> add_a_records_domain.txt

echo "
mailer$mailer-vmta-$third_octive-$last_octive
" >> add_a_records_record.txt

done 3<domain.txt 4<ip.txt 5<last_digit_third_octive.txt 6<third_octive.txt 7<last_octive.txt 8<mailer.txt

# Remove blank lines
gsed -i '/^$/d' ptr_records.txt
gsed -i '/^$/d' add_a_records_ip.txt
gsed -i '/^$/d' add_a_records_domain.txt
gsed -i '/^$/d' add_a_records_record.txt

############################# -- ############################# -- #############################
############################# -- ############################# -- #############################
# Create a just unique domain(s) file
echo "# Create a just unique domain(s) file"

sort -u domain.txt > domain_unique.txt

domain="$(cat domain.txt)"
domain_unique="$(cat domain_unique.txt)"

# Sort and remove empty lines in Domain Seperator File(s)
echo "# Sort and remove empty lines in Domain Seperator File(s)"

while read -u 3 -r domain;
do
sort -uo "$domain"_domain_seperator.txt{,}
gsed -i '/^$/d' "$domain"_domain_seperator.txt

done 3<domain.txt

# Add DKIM to file
echo "# Add DKIM to file"

domain_unique="$(cat domain_unique.txt)"
while read -u 3 -r domain_unique;
do

touch "$domain_unique"_dkim.txt
echo "domain-key key1,DOMAINDKIM,/etc/pmta/domainkeys/key1_dkim.DOMAINDKIM.pem" > "$domain_unique"_dkim.txt
gsed -i "s|DOMAINDKIM|$domain_unique|g" "$domain_unique"_dkim.txt

done 3<domain_unique.txt

# Clean up SMTP Listener File(s)
echo "# Clean up SMTP Listener File(s)"

domain_unique="$(cat domain_unique.txt)"
while read -u 3 -r domain_unique;
do

sort -uo "$domain_unique"_smtp-listener_vmta_config.txt{,}
gsed -i '/^$/d' "$domain_unique"_smtp-listener_vmta_config.txt
gsed -i 's/^.*smtp-listener/smtp-listener/g' "$domain_unique"_smtp-listener_vmta_config.txt

done 3<domain_unique.txt

# Clean up Virtual MTA Config File(s)
echo "# Clean up Virtual MTA Config File(s)"

domain_unique="$(cat domain_unique.txt)"
while read -u 3 -r domain_unique;
do

# Remove Double Blank Lines, replace with 1
gsed -i '/^$/N;/^\n$/D' "$domain_unique"_virtual-mta_vmta_config.txt

done 3<domain_unique.txt

# Clean up Virtual MTA Pool File(s) 
echo "# Clean up Virtual MTA Pool File(s) "

domain_unique="$(cat domain_unique.txt)"
while read -u 3 -r domain_unique;
do

sort -uo "$domain_unique"_virtual-mta-pool_vmta_config.txt{,}
gsed -i '/^$/d' "$domain_unique"_virtual-mta-pool_vmta_config.txt
gsed -i 's/^.*virtual-mta/virtual-mta/g' "$domain_unique"_virtual-mta-pool_vmta_config.txt

# Add virtual-mta-pool open tag
gsed -i '1 i\<virtual-mta-pool CPM-CPMCHANGE__MAILER-MAILERCHANGE__POOL-POOLCHANGE__BRAND-BRANDCHANGE__DOMAIN-DOMAINCHANGE\.p>' "$domain_unique"_virtual-mta-pool_vmta_config.txt

# Add virtual-mta-pool close tag
gsed -i '$a<\/virtual-mta-pool>' "$domain_unique"_virtual-mta-pool_vmta_config.txt

done 3<domain_unique.txt

# Update TIER MAILER POOL BRAND & DOMAIN in virtual-mta-pool configuration(s)
echo "# Update TIER MAILER POOL BRAND & DOMAIN in virtual-mta-pool configuration(s)"

CPMREPLACE="$(cat cpm_replace.txt)"
MAILERREPLACE="$(cat mailer_replace.txt)"
POOLREPLACE="$(cat pool_replace.txt)"
BRANDREPLACE="$(cat brand_replace.txt)"
DOMAINREPLACE="$(cat domain_unique.txt)"

while read -u 3 -r CPMREPLACE &&
	  read -u 4 -r MAILERREPLACE &&	  
	  read -u 5 -r POOLREPLACE &&
	  read -u 6 -r BRANDREPLACE &&
	  read -u 7 -r DOMAINREPLACE;
do

gsed -i "s|CPM-CPMCHANGE|CPM-$CPMREPLACE|g" "$DOMAINREPLACE"_virtual-mta-pool_vmta_config.txt
gsed -i "s|MAILER-MAILERCHANGE|MAILER-$MAILERREPLACE|g" "$DOMAINREPLACE"_virtual-mta-pool_vmta_config.txt
gsed -i "s|POOL-POOLCHANGE|POOL-$POOLREPLACE|g" "$DOMAINREPLACE"_virtual-mta-pool_vmta_config.txt
gsed -i "s|BRAND-BRANDCHANGE|BRAND-$BRANDREPLACE|g" "$DOMAINREPLACE"_virtual-mta-pool_vmta_config.txt
gsed -i "s|DOMAIN-DOMAINCHANGE|DOMAIN-$DOMAINREPLACE|g" "$DOMAINREPLACE"_virtual-mta-pool_vmta_config.txt

done 3<cpm_replace.txt 4<mailer_replace.txt 5<pool_replace.txt 6<brand_replace.txt 7<domain_unique.txt

# Add Blank Lines to the end of each file
echo "# Add Blank Lines to the end of each file"

domain_unique="$(cat domain_unique.txt)"
while read -u 3 -r domain_unique;
do

echo "" >> "$domain_unique"_dkim.txt
echo "" >> "$domain_unique"_domain_seperator.txt
echo "" >> "$domain_unique"_smtp-listener_vmta_config.txt
echo "" >> "$domain_unique"_virtual-mta-pool_vmta_config.txt
echo "" >> "$domain_unique"_virtual-mta_vmta_config.txt

done 3<domain_unique.txt

# Concatanate File(s) in correct order
echo "# Concatanate File(s) in correct order"

domain_unique="$(cat domain_unique.txt)"
while read -u 3 -r domain_unique;
do

cat "$domain_unique"_domain_seperator.txt "$domain_unique"_dkim.txt "$domain_unique"_smtp-listener_vmta_config.txt "$domain_unique"_virtual-mta_vmta_config.txt "$domain_unique"_virtual-mta-pool_vmta_config.txt > "$domain_unique"_final.txt

done 3<domain_unique.txt

cat *_final.txt > final.aa
rm -rf *_final.txt
mv final.aa	$(date +"%Y_%m_%d_%H-%M")_config.txt

mv *.txt $(date +"%Y_%m_%d_%H-%M")/
cd  $(date +"%Y_%m_%d_%H-%M")/

# Copy files to correct directories 
mv $(date +"%Y_%m_%d_%H-%M")_config.txt pmta/
mv domain_unique.txt pmta/
cp last_octive.txt pmta/
cp last_digit_third_octive.txt pmta/
cp brand_replace.txt pmta/
cp cpm_replace.txt pmta/
cp mailer.txt pmta/
cp mailer_replace.txt pmta/
cp pool_replace.txt pmta/
cp *_dkim.txt pmta/
cp *_domain_seperator.txt pmta/
cp *_smtp-listener_vmta_config.txt pmta/
cp *_virtual-mta-pool_vmta_config.txt pmta/
cp *_virtual-mta_vmta_config.txt pmta/
cp domain.txt pmta/
cp ip.txt pmta/

cp domain.txt add_a_records/
cp add_a_records_ip.txt add_a_records/
cp ip.txt add_a_records/
mv add_a_records_ip.txt add_a_records/
mv add_a_records_domain.txt add_a_records/
mv add_a_records_record.txt add_a_records/

mv domain.txt ptr/
mv ip.txt ptr/
mv ptr_records.txt ptr/

rm -rf *.txt

echo "Done"
