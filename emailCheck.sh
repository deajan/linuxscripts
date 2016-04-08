#!/usr/bin/env bash

PROGRAM="emailCheck.sh"
AUTHOR="(L) 2014-2016 by Orsiris de Jong"
CONTACT="http://www.netpower.fr/ - ozy@netpower.fr"
PROGRAM_VERSION=0.5
PROGRAM_BUILD=2016040801

## Email correction script
## Checks if email format is valid againts RFC822
## Checks if there are any known domain typos
## Checks if email domain has valid MX records

## Warning: when processing files command windows, use dos2unix first to convert carriage return chars

# Check if internet is working
inet_addr_to_test=www.google.com

INCORRECT_MAILS=0
INCORRECT_DOMAINS=0
INCORRECT_MX=0

# Function checks if argument is valid against RFC822
function checkRFC822 {
	local mail="${1}"
	local rfc822="^[a-z0-9!#\$%&'*+/=?^_\`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_\`{|}~-]+)*@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?\$"

	if [[ $mail =~ $rfc822 ]]; then
		return 0
	else
		return 1
	fi
}

# Function fixes some known typos in email domain parts
function checkDomains {
	local mail="${1}"

	declare -a invalid_domains=(	neuf.com neuf.fre neuf.frr neuf
					wanado.fr wanado.com wanadoo.fre anadoo.fr wanaoo.fr wanadoo ornge.fr orage.fr orage.com orange.com wanadoo.com wanadoo.frr orange.frr wanadoo orange
					fre.fr fre.com free.com free.frr
					clubinternet.fr clubinternet.com club-internet.com club-internet clubinternet
					laposte.com laposte
					yaho.fr yaho.com yaho.co.uk yahoo.frr
					sfr.fre sfr.frr sfr
					homail.fr hotail.fr homail.com hotail.com life.fr live.frr life.com
					gmail.fr google.fr gmal.fr gmail.frr gmail
					alice.fr aliseadsl.fr aliceadsl.com aliceadsl.frr aliceadsl
					voila.com voila.frr voila
					skynet.bee skynet
				)
	declare -a valid_domains=(  	neuf.fr neuf.fr neuf.fr neuf.fr
					wanadoo.fr wanadoo.fr wanadoo.fr wanadoo.fr wanaoo.fr wanadoo.fr orange.fr orange.fr orange.fr orange.fr wanadoo.fr wanadoo.fr orange.fr wanadoo.fr orange.fr
					free.fr free.fr free.fr free.fr
					club-internet.fr club-internet.fr club-internet.fr club-internet.fr club-internet.fr
					laposte.net laposte.net
					yahoo.fr yahoo.com yahoo.co.uk yahoo.fr
					sfr.fr sfr.fr sfr.fr
					hotmail.fr hotmail.fr hotmail.com hotmail.com live.fr live.fr live.com
					gmail.com gmail.com gmail.com gmail.fr gmail.com
					aliceadsl.fr aliceadsl.fr aliceadsl.fr aliceadsl.frr aliceadsl
					voila.fr voila.fr voila.fr
					skynet.be skynet.be
				)


	local count=0

	for i in "${invalid_domains[@]}"; do
		if [ "$i" == "${mail#*@}" ]; then
			mail="${mail%@*}@${valid_domains[$count]}"
		fi
		count=$((count + 1))
	done

	# Function return
	echo "$mail"
}

# Function checks if MX records exist for the domain of an email address
function checkMXDomains {
	local mail="${1}"

	if [ "$(dig "${mail#*@}" mx +short | wc -l)" -ne 0 ]; then
		return 0
	else
		return 1
	fi
}


if ([ "$1" == "" ] || [ ! -f "$1" ]) ; then
	echo "$PROGRAM $PROGRAM_VERSION $PROGRAM_BUILD"
	echo "$AUTHOR"
	echo "$CONTACT"
	echo ""
	echo "Usage: ./emailCheck.sh emailList"
	echo "Email list needs to be a list of one email per line, encoded in UTF8 Unix format"
	echo "New file emailList.corrected will be created"
	exit 1
fi

function checkEnvironment {

	if ! type dig > /dev/null; then
		echo "This script needs dig to resolve MX records."
		exit 1
	fi

	if [[ $(uname) == *"CYGWIN*" ]]; then
		ping $inet_addr_to_test 44 " > /dev/null
	else
		ping -c 3 $inet_addr_to_test > /dev/null
	fi
	if [ $? != 0 ]; then
		echo "This script needs internet to resolve MX records."
		exit 1
	fi
}

checkEnvironment

file="$1"
file_tmp="$file.tmp"
file_corrected="$file.corrected"
file_ambiguous="$file.ambiguous"

if [ -f "$file_tmp" ]; then
	rm -f "$file_tmp"
fi

if [ -f "$file_corrected" ]; then
	rm -f "$file_corrected"
fi

if [ -f "$file_ambiguous" ]; then
	rm -f "$file_ambiguous"
fi


count=0
# Example to read CSV where email is second column
#while IFS=';' read land email; do
# Example to read a file with one email per line
while read email; do
	checkRFC822 "$email"
	if [ $? -eq 1 ]; then
		INCORRECT_MAILS=$((INCORRECT_MAILS+1))
		continue
	fi

	newemail=$(checkDomains "$email")

	## Ugly hack because incorrect_domains can't be increased directly in function checkDomains
	if [ "$newemail" != "$email" ]; then
		INCORRECT_DOMAINS=$((INCORRECT_DOMAINS+1))
		email="$newemail"
	fi

	checkMXDomains "$email"
	if [ $? -eq 1 ]; then
		INCORRECT_MX=$((INCORRECT_MX+1))
		continue
	fi

	# CSV file example
	#echo "$land;$email" >> "$file_tmp"
	# One email per line example
	echo "$email" >> "$file_tmp"
	count=$((count+1))
	if [ $((count % 1000)) -eq 0 ]; then
		echo "Time: $SECONDS - $count email addresses processed so far."
	fi

done <"$file"

egrep "test|example|exemple|spam" < "$file_tmp" > "$file_ambiguous"
egrep -v "test|example|exemple|spam" < "$file_tmp" > "$file_corrected"
AMBIGUOUS_MAILS=$(wc -l < "$file_ambiguous")
VALID_MAILS=$(wc -l < "$file_corrected")

rm -f "$file_tmp"

echo "$INCORRECT_MAILS non rfc822 compliant emails deleted."
echo "$INCORRECT_DOMAINS emails had incorrect domains and have been corrected."
echo "$INCORRECT_MX emails where domain has no valid mx deleted."
echo "$AMBIGUOUS_MAILS are left in [$file_ambiguous]."
echo "$VALID_MAILS are left in [$file_corrected]."
