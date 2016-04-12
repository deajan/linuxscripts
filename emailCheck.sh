#!/usr/bin/env bash

PROGRAM="emailCheck.sh"
AUTHOR="(L) 2014-2016 by Orsiris de Jong"
CONTACT="http://www.netpower.fr/ - ozy@netpower.fr"
PROGRAM_VERSION=0.6
PROGRAM_BUILD=2016041201

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
AMBIGUOUS_MAILS=0
VALID_MAILS=0

TMP_PREFIX="tmp"
VALID_PREFIX="valid"
NON_RFC_COMPLIANT_PREFIX="rfc_non_compliant"
MISSING_MX_PREFIX="missing_mx"
AMBIGUOUS_PREFIX="ambiguous"


# Lowers all characters
function lowercase {
	local string="${1}"

	echo "$(echo $string | tr '[:upper:]' '[:lower:]')"
}

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

function checkEnvironment {

	if ! type dig > /dev/null; then
		echo "This script needs dig to resolve MX records."
		exit 1
	fi

	if ! type tr > /dev/null; then
		echo "This script needs tr to transorm addresses to lowercase."
		exit 1
	fi

	echo "Checking for internet access."
	if [[ $(uname) == *"CYGWIN"* ]]; then
		ping $inet_addr_to_test 64 3 > /dev/null
	else
		ping -c 3 $inet_addr_to_test > /dev/null
	fi
	if [ $? != 0 ]; then
		echo "This script needs internet to resolve MX records."
		exit 1
	fi
}

function usage {
	echo "$PROGRAM $PROGRAM_VERSION $PROGRAM_BUILD"
	echo "$AUTHOR"
	echo "$CONTACT"
	echo ""
	echo "Usage: ./emailCheck.sh /path/to/emailList"
	echo "Email list needs to be a list of one email per line, encoded in UTF8 Unix format."
	echo "Checks if emails are RFC822 valid, corrects known typos in domain names, checks for valid MX records and checks against known ambiguous mail adresses."
	echo ""
	echo "Outputs 4 files with suffixes:"
	echo "$VALID_PREFIX: All emails that seem valid."
	echo "$RFC_NON_COMPLIANT_PREFIX: All emails that aren't RFC822 compliant."
	echo "$MISSING_MX_PREFIX: All emails of which domain doesn't have valid MX records."
	echo "$AMBIGUOUS_PREFIX: All emails which seem ambiguous."
	exit 1
}

function loop {
	local input="${1}"
	local output_rfc_non_compliant="${2}"
	local output_missing_mx="${3}"
	local output_tmp="${4}"

	echo "Checking emails."

	count=0
	#TIP while read email; do waits for a single email address per line
	#TIP while IFS=';' read col1 col2 email; do will read third column separated by semicolons as email
	#TIP keep in mind that sortAmbiguous cannot handle CSV files if email address is not the first column 

	# Example to read CSV where email is second column
	#while IFS=';' read land email; do
	# Example to read a file with one email per line
	while read email; do

		email=$(lowercase "$email")
		checkRFC822 "$email"
		if [ $? -eq 1 ]; then
			INCORRECT_MAILS=$((INCORRECT_MAILS+1))
			echo "$email" >> "$output_rfc_non_compliant"
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
			echo "$email" >> "$output_missing_mx"
			continue
		fi

		# CSV file example output as 2nd column
		#echo "$land;$email" >> "$output_tmp"
		# One email per line example
		echo "$email" >> "$output_tmp"
		count=$((count+1))
		if [ $((count % 1000)) -eq 0 ]; then
			echo "Time: $SECONDS - $count email addresses processed so far."
		fi
	done <"$input"
}

function sortAmbiguous {
	local input="${1}"
	local output_ambiguous="${2}"
	local output_valid="${3}"

	# Test for username and domain
	egrep "^test@|^example@|^exemple@|^spam@|@test\.|@example\.|@exemple\.|@spam\." < "$input" > "$output_ambiguous"
	egrep -v "^test$|^example$|^exemple$|^spam$|@test\.|@example\.|@exemple\.|@spam\." < "$input" > "$output_valid"

	AMBIGUOUS_MAILS=$(wc -l < "$output_ambiguous")
	VALID_MAILS=$(wc -l < "$output_valid")
}

checkEnvironment

if ([ "$1" == "" ] || [ ! -f "$1" ]) ; then
	usage
fi

input="$1"
input_path="$(dirname $1)"
input_file="$(basename $1)"
output_tmp="$input_path/$TMP_PREFIX.$input_file"
output_valid="$input_path/$VALID_PREFIX.$input_file"
output_missing_mx="$input_path/$MISSING_MX_PREFIX.$input_file"
output_non_rfc_compliant="$input_path/$NON_RFC_COMPLIANT_PREFIX.$input_file"
output_ambiguous="$input_path/$AMBIGUOUS_PREFIX.$input_file"

if [ -f "$output_tmp" ]; then
	rm -f "$output_tmp"
fi
if [ -f "$output_valid" ]; then
	rm -f "$output_valid"
fi
if [ -f "$output_missing_mx" ]; then
	rm -f "$output_missing_mx"
fi
if [ -f "$output_non_rfc_compliant" ]; then
	rm -f "$output_non_rfc_compliant"
fi
if [ -f "$output_ambiguous" ]; then
	rm -f "$output_ambiguous"
fi

loop "$input" "$output_non_rfc_compliant" "$output_missing_mx" "$output_tmp"
if [ ! -f "$output_tmp" ]; then
	echo "No valid emails found. Check if your file has only email addresses, or correct the loop function accordingly to read multicolumn CSV files See #TIP in source."
	echo "Also, if your file comes from Windows, convert it using dos2unix first."
else
	sortAmbiguous "$output_tmp" "$output_ambiguous" "$output_valid"
fi

echo ""
echo "$INCORRECT_MAILS non rfc822 compliant emails are in [$output_non_rfc_compliant]."
echo "$INCORRECT_DOMAINS emails had incorrect domains and have been corrected."
echo "$INCORRECT_MX emails are missing mx records in their domain in [$output_missing_mx]."
echo "$AMBIGUOUS_MAILS are ambiguous emails in [$output_ambiguous]."
echo "$VALID_MAILS emails seem valid in [$output_valid]."
