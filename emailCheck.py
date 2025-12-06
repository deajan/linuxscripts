#!/usr/bin/env python3

"""
emailCheck.py
(L) 2014-2025 by Orsiris de Jong
http://www.netpower.fr/ - ozy@netpower.fr

Email correction script
- Lowers all characters of email
- Checks if email format is valid against RFC822
- Checks if there are any known domain typos
- Checks if email domain has valid MX records (with caching)
- Checks if email address is ambiguous
"""

import re
import sys
import csv
import subprocess
from pathlib import Path
from functools import lru_cache

PROGRAM_VERSION = "0.7.0"
PROGRAM_BUILD = "2025120501"

###################################################################################################### 
# Configuration
######################################################################################################

INPUT_FILE_HAS_HEADER = True

# CSV configuration
CSV_EMAIL_IS_FIRST_COLUMN = True
CSV_INPUT_DELIMITER = ','
# We add a "state" column at the start of the file with the email check results
# When multiple email columns exist, we need to fill the state column with multiple states, one per column
STATE_COLUMN_SEPARATOR = '+' # Separator for multiple email states from different email columns
MULTI_EMAIL_SEPARATOR = ';' # Separator for multiple emails in one column
CSV_COLUMNS = ['CT_Num', 'CT_EMail', 'CT_EMail2', 'CT_Fonction', 'CT_Sommeil']
EMAIL_COLUMNS = ['CT_EMail', 'CT_EMail2']

# Internet connectivity check
INET_ADDR_TO_TEST = "www.google.com"

DNS_CACHE_SIZE = 10000  # Size of the LRU cache for DNS lookups

######################################################################################################
# Output codes
######################################################################################################

EM_VALID = "OK"
EM_MISSING = "VIDE"
EM_NON_RFC = "INVALIDE"
EM_FIXED = "CORRIGE"
EM_NO_MX = "DOMAINE INVALIDE"
EM_AMBIGUOUS = "AMBIGU"

######################################################################################################
# Domain mappings - now using dictionary for O(1) lookup instead of O(n) loop
######################################################################################################

INVALID_TO_VALID_DOMAINS = {
    # neuf.fr variants
    'neuf.com': 'neuf.fr', 'neuf.fre': 'neuf.fr', 'neuf.frr': 'neuf.fr',
    'neuf': 'neuf.fr', 'neuf.fe': 'neuf.fr', 'neuf.ff': 'neuf.fr',
    
    # wanadoo.fr variants
    'wanado.fr': 'wanadoo.fr', 'wanado.com': 'wanadoo.fr', 'wanadoo.fre': 'wanadoo.fr',
    'anadoo.fr': 'wanadoo.fr', 'wanaoo.fr': 'wanadoo.fr', 'wanadoo': 'wanadoo.fr',
    'wanadoo.com': 'wanadoo.fr', 'wanadoo.frr': 'wanadoo.fr', 'wanadoo.fe': 'wanadoo.fr',
    'wanadoo.ff': 'wanadoo.fr',
    
    # orange.fr variants
    'ornge.fr': 'orange.fr', 'orage.fr': 'orange.fr', 'orage.com': 'orange.fr',
    'orange.com': 'orange.fr', 'orange.frr': 'orange.fr', 'orange': 'orange.fr',
    'orange.fe': 'orange.fr', 'orange.ff': 'orange.fr', 'orange:fr': 'orange.fr',
    
    # free.fr variants
    'fre.fr': 'free.fr', 'fre.com': 'free.fr', 'free.com': 'free.fr',
    'free.frr': 'free.fr', 'free.fe': 'free.fr', 'free.ff': 'free.fr', 'free:frr': 'free.fr',
    'free.f': 'free.fr',
    
    # club-internet.fr variants
    'clubinternet.fr': 'club-internet.fr', 'clubinternet.com': 'club-internet.fr',
    'club-internet.com': 'club-internet.fr', 'club-internet': 'club-internet.fr',
    'clubinternet': 'club-internet.fr', 'club_internet.fr': 'club-internet.fr',
    'club-internet.fe': 'club-internet.fr', 'club-internet.ff': 'club-internet.fr',
    
    # laposte.net variants
    'laposte.com': 'laposte.net', 'laposte': 'laposte.net',
    
    # yahoo variants
    'yaho.fr': 'yahoo.fr', 'yaho.com': 'yahoo.com', 'yaho.co.uk': 'yahoo.co.uk',
    'yahoo.frr': 'yahoo.fr', 'yahoo.ciom': 'yahoo.com', 'yahoo.vom': 'yahoo.com',
    'yahoo.c': 'yahoo.com', 'yahoo.cim': 'yahoo.com', 'yahoo.co': 'yahoo.com',
    'yaoo.col': 'yahoo.com', 'yahoo.colm': 'yahoo.com', 'yahoo.con': 'yahoo.com',
    
    # sfr.fr variants
    'sfr.fre': 'sfr.fr', 'sfr.frr': 'sfr.fr', 'sfr': 'sfr.fr',
    'sfr.fe': 'sfr.fr', 'sfr.ff': 'sfr.fr',
    
    # hotmail variants
    'homail.fr': 'hotmail.fr', 'hotail.fr': 'hotmail.fr', 'hotmail.fe': 'hotmail.fr',
    'hotmail.ff': 'hotmail.fr', 'homail.com': 'hotmail.com', 'hotail.com': 'hotmail.com',
    'hotmail.ciom': 'hotmail.com', 'hotmail.vom': 'hotmail.com', 'hotmail.c': 'hotmail.com',
    'hotmail.cim': 'hotmail.com', 'hotmail.co': 'hotmail.com', 'hotmail.col': 'hotmail.com',
    'hotmail.colm': 'hotmail.com', 'hotmail.con': 'hotmail.com',
    
    # live.com variants
    'life.fr': 'live.fr', 'live.frr': 'live.fr', 'live.fe': 'live.fr',
    'live.ff': 'live.fr', 'life.com': 'live.com', 'live.ciom': 'live.com',
    'live.vom': 'live.com', 'live.c': 'live.com', 'live.cim': 'live.com',
    'live.co': 'live.com', 'live.col': 'live.com', 'live.colm': 'live.com',
    'live.con': 'live.com',
    
    # outlook variants
    'outlok.fr': 'outlook.fr', 'outlok.com': 'outlook.com', 'outlook.ciom': 'outlook.com',
    'outlook.vom': 'outlook.com', 'outlook.c': 'outlook.com', 'outlook.cim': 'outlook.com',
    'outlook.co': 'outlook.com', 'outlook.col': 'outlook.com', 'outlook.colm': 'outlook.com',
    'outlook.con': 'outlook.com', 'outhlook.fr': 'outlook.fr', 'outhlook.com': 'outlook.com',
    
    # gmail.com variants
    'gmail.fr': 'gmail.com', 'gmal.fr': 'gmail.com', 'gmail.frr': 'gmail.com',
    'gmail': 'gmail.com', 'gmail.ciom': 'gmail.com', 'g.mail': 'gmail.com',
    'gemail.com': 'gmail.com', 'galml.com': 'gmail.com', 'gmail.c': 'gmail.com',
    'gmail.': 'gmail.com', 'gmail.cim': 'gmail.com', 'gmail.clm': 'gmail.com',
    'gmail.co': 'gmail.com', 'gmail.col': 'gmail.com', 'gmail.comp': 'gmail.com',
    'gmail.con': 'gmail.com', 'gmail.cpm': 'gmail.com', 'gmail.de': 'gmail.com',
    'gmail.dk': 'gmail.com', 'gmail.es': 'gmail.com', 'gmail.org': 'gmail.com',
    'gmail.vom': 'gmail.com', 'gmaill.com': 'gmail.com', 'gmal.com': 'gmail.com',
    'gmeil.com': 'gmail.com', 'gmail.colm': 'gmail.com',
    
    # googlemail.com variants
    'googlemail.con': 'googlemail.com', 'googlemail.cpm': 'googlemail.com',
    'googlemail.de': 'googlemail.com', 'googlemail.fr': 'googlemail.com',
    'googlemail.co.uk': 'googlemail.com', 'googlemail.es': 'googlemail.com',
    'googlemail.dk': 'googlemail.com', 'googlemail.vom': 'googlemail.com',
    'googlemail.c': 'googlemail.com', 'googlemail.cim': 'googlemail.com',
    'googlemail.co': 'googlemail.com', 'googlemail.col': 'googlemail.com',
    'googlemail.colm': 'googlemail.com',
    
    # aliceadsl.fr variants
    'alice.fr': 'aliceadsl.fr', 'aliseadsl.fr': 'aliceadsl.fr', 'aliceadsl.com': 'aliceadsl.fr',
    'aliceadsl.frr': 'aliceadsl.fr', 'aliceadsl': 'aliceadsl.fr', 'aliceadsl.fe': 'aliceadsl.fr',
    'aliceadsl.ff': 'aliceadsl.fr',
    
    # voila.fr variants
    'voila.com': 'voila.fr', 'voila.frr': 'voila.fr', 'voila': 'voila.fr',
    'voila.fe': 'voila.fr', 'voila.ff': 'voila.fr',
    
    # skynet.be variants
    'skynet.bee': 'skynet.be', 'skynet': 'skynet.be',
    
    # aol variants
    'aol.ciom': 'aol.com', 'aol.vom': 'aol.com', 'aol.c': 'aol.com',
    'aol.cim': 'aol.com', 'aol.co': 'aol.com', 'aol.col': 'aol.com',
    'aol.colm': 'aol.com', 'aol.con': 'aol.com',
    
    # icloud variants
    'iclou.com': 'icloud.com', 'icloud.con': 'icloud.com', 'icloud.cim': 'icloud.com',
    'icloud.co': 'icloud.com', 'icloud.vom': 'icloud.com', 'iclod.com': 'icloud.com',
    
    # protonmail variants
    'protonmail.ch': 'protonmail.com', 'protonmai.com': 'protonmail.com',
    'protonmail.con': 'protonmail.com', 'protonmail.co': 'protonmail.com',
    
    # msn variants
    'msn.con': 'msn.com', 'msn.co': 'msn.com', 'msn.vom': 'msn.com',
    
    # numericable/bouygues variants
    'numericable.com': 'numericable.fr', 'bouygues.com': 'bbox.fr',
    'bouyguestel.fr': 'bbox.fr', 'bouygtel.fr': 'bbox.fr',
    
    # Common TLD typos (.cmo, .cpm, .con, .net instead of .com, .co.uk, etc.)
    'yahoo.cmo': 'yahoo.com', 'hotmail.cmo': 'hotmail.com', 'gmail.cmo': 'gmail.com',
    
    # Common reversed/transposed letters
    'gail.com': 'gmail.com', 'gamil.com': 'gmail.com', 'gmial.com': 'gmail.com',
    
    # Missing dots
    'hotmailcom': 'hotmail.com', 'gmailcom': 'gmail.com', 'yahoocom': 'yahoo.com',
    'outlookcom': 'outlook.com', 'livecom': 'live.com',
    
    # Common .uk typos
    'yahoo.uk': 'yahoo.co.uk', 'hotmail.uk': 'hotmail.co.uk',
    'gmail.uk': 'gmail.com',  # gmail.co.uk doesn't exist
    'outlook.uk': 'outlook.com',  # outlook.co.uk redirects to .com
    
    # Common .ca/.au typos for US services
    'gmail.ca': 'gmail.com', 'gmail.au': 'gmail.com',
    'hotmail.ca': 'hotmail.com', 'hotmail.au': 'hotmail.com',
    
    # Spaces in domain (will be caught by RFC but good to have)
    'hot mail.com': 'hotmail.com', 'g mail.com': 'gmail.com',
    
    # Missing hyphen or underscore
    'club internet.fr': 'club-internet.fr',
    
    # ISP variants (France)
    'nordnet.com': 'nordnet.fr', 'nordnet.net': 'nordnet.fr',
    'cegetel.com': 'cegetel.net', 'cegetel.fr': 'cegetel.net',
    'bbox.com': 'bbox.fr',
    
    # Common international providers
    'mail.ru': 'mail.ru',  # Valid but include for completeness
    'ya.ru': 'yandex.ru', 'yandex.com': 'yandex.ru',
    'web.de': 'web.de',  # Valid German provider
    'gmx.com': 'gmx.com',  # Valid
    'gmx.de': 'gmx.de',  # Valid

    # Gouvermement fr
    'gouv.frr': 'gouv.fr', 'gouv.fe': 'gouv.fr', 'gouv.ff': 'gouv.fr',
    'gouv.f': 'gouv.fr',
}

# Ambiguous email patterns
AMBIGUOUS_PATTERNS = re.compile(
    r'(^|@)(test|example|exemple|spam|noreply|no-reply)(@|\.|$)',
    re.IGNORECASE
)

# RFC822 email regex (simplified but practical)
RFC822_PATTERN = re.compile(
    r"^[a-z0-9!#$%&'*+/=?^_`{|}~-]+(\.[a-z0-9!#$%&'*+/=?^_`{|}~-]+)*"
    r"@([a-z0-9]([a-z0-9-]*[a-z0-9])?\.)+[a-z0-9]([a-z0-9-]*[a-z0-9])?$"
)

SPLIT_PATTERN = re.compile(r'[;,]')
EXTRACT_PATTERN = re.compile(r'[\w.+-]+@[\w-]+\.[\w.-]+')

######################################################################################################
# Functions
######################################################################################################

class EmailStats:
    """Track email processing statistics"""
    def __init__(self):
        self.missing = 0
        self.incorrect_mails = 0
        self.incorrect_domains = 0
        self.incorrect_mx = 0
        self.ambiguous = 0
        self.valid = 0
        
    def print_stats(self):
        print(f"\n{self.missing} missing emails found.")
        print(f"{self.incorrect_mails} non RFC822 compliant emails found.")
        print(f"{self.incorrect_domains} emails had incorrect domains and have been corrected.")
        print(f"{self.incorrect_mx} emails are missing MX records in their domain.")
        print(f"{self.ambiguous} ambiguous emails found.")
        print(f"{self.valid} emails seem valid.")


def lowercase(s):
    """Convert string to lowercase"""
    return s.lower() if s else s


def check_rfc822(email):
    """Check if email is RFC822 compliant"""
    if not email:
        return False
    return RFC822_PATTERN.match(email.lower()) is not None


def check_domain(email):
    """
    Check and fix known domain typos using dictionary lookup (O(1) instead of O(n))
    Returns: (corrected_email, was_corrected)
    """
    if not email or '@' not in email:
        return email, False
    
    username, domain = email.rsplit('@', 1)
    domain_lower = domain.lower()
    
    if domain_lower in INVALID_TO_VALID_DOMAINS:
        corrected_domain = INVALID_TO_VALID_DOMAINS[domain_lower]
        return f"{username}@{corrected_domain}", True
    
    return email, False


@lru_cache(maxsize=DNS_CACHE_SIZE)
def check_mx_domains(domain):
    """
    Check if domain has valid MX records
    Uses LRU cache to avoid repeated DNS lookups for the same domain
    We also need to make sure we only use root domain for MX checks
    """

    try:
        result = subprocess.run(
            ['dig', domain, 'mx', '+short'],
            capture_output=True,
            text=True,
            timeout=5
        )
        # Check if we got any MX records
        return len(result.stdout.strip()) > 0
    except (subprocess.TimeoutExpired, FileNotFoundError):
        # If dig fails or times out, assume valid to avoid false positives
        return True


def check_ambiguous(email):
    """Check if email appears to be ambiguous/test email"""
    if not email:
        return False
    return AMBIGUOUS_PATTERNS.search(email.lower()) is not None


def check_environment():
    """Verify required tools and internet connectivity"""
    # Check for dig
    try:
        subprocess.run(['dig', '-v'], capture_output=True, timeout=2)
    except FileNotFoundError:
        print("ERROR: This script needs 'dig' to resolve MX records.")
        print("Install it using: apt install dnsutils (Debian/Ubuntu) or dnf install bind-utils (RHEL/Fedora)")
        sys.exit(1)
    
    # Check internet connectivity
    print("Checking for internet access...")
    try:
        result = subprocess.run(
            ['ping', '-c', '3', INET_ADDR_TO_TEST] if sys.platform != 'win32' 
            else ['ping', '-n', '3', INET_ADDR_TO_TEST],
            capture_output=True,
            timeout=10
        )
        if result.returncode != 0:
            print("ERROR: This script needs internet to resolve MX records.")
            sys.exit(1)
    except subprocess.TimeoutExpired:
        print("ERROR: Internet connectivity check timed out.")
        sys.exit(1)


def add_to_text(text, addition, separator=STATE_COLUMN_SEPARATOR):
    """Helper to add text with newline"""
    if text:
        return f"{text}{separator}{addition}"
    return addition


def process_emails(input_file, output_file):
    """Process email file and validate/correct emails"""
    stats = EmailStats()
    
    input_path = Path(input_file)
    if not input_path.exists():
        print(f"ERROR: No such file: {input_file}")
        sys.exit(1)
    
    print("Checking emails...")
    
    count = 0
    with open(input_file, 'r', encoding='utf-8') as infile, \
         open(output_file, 'w', encoding='utf-8', newline='') as outfile:
        
        # Read first line to determine if it's a header or data
        first_line = infile.readline()
        # Remove BOM if present
        if first_line.startswith('\ufeff'):
            first_line = first_line.lstrip('\ufeff')
        
        if INPUT_FILE_HAS_HEADER:
            # First line is header - use it for fieldnames
            fieldnames = first_line.strip().split(CSV_INPUT_DELIMITER)
            reader = csv.DictReader(infile, fieldnames=fieldnames, delimiter=CSV_INPUT_DELIMITER)
        else:
            # First line is data - use configured columns and rewind
            infile.seek(0)
            reader = csv.DictReader(infile, fieldnames=CSV_COLUMNS, delimiter=CSV_INPUT_DELIMITER)
        
        # Prepare writer with STATE column
        output_columns = ['STATE'] + list(reader.fieldnames)
        writer = csv.DictWriter(outfile, fieldnames=output_columns, delimiter=CSV_INPUT_DELIMITER, extrasaction='ignore')
        writer.writeheader()

        # Verify EMAIL_COLUMN exists
        for column in EMAIL_COLUMNS:
            if column not in reader.fieldnames:
                print(f"ERROR: Email column '{column}' not found in CSV.")
                print(f"Available columns: {', '.join(reader.fieldnames)}")
                sys.exit(1)

        for row in reader:
            count += 1
            row_state = ""

            # we might have multiple email columns to check in a single row
            col_state = ""
            for email_column in EMAIL_COLUMNS:
                # Strip surrounding quotes and spaces
                email = row.get(email_column, '').strip("\"' ")

                # Check for missing email
                if not email:
                    stats.missing += 1
                    col_state = add_to_text(col_state, EM_MISSING)
                    continue

                # We might have an email column with multiple entries separated by MULTI_EMAIL_SEPARATOR
                em_state = ""
                new_email_col = ""
                continue_checks = True
                for em in re.findall(EXTRACT_PATTERN, email):
                    
                    # Lowercase the email
                    em = lowercase(em)
                    
                    # Check and fix domain typos
                    corrected_email, was_corrected = check_domain(em)
                    if was_corrected:
                        stats.incorrect_domains += 1
                        em = corrected_email
                        em_state = add_to_text(em_state, EM_FIXED, MULTI_EMAIL_SEPARATOR)
                    
                    # Check RFC822 compliance
                    if not check_rfc822(em):
                        stats.incorrect_mails += 1
                        em_state = add_to_text(em_state, EM_NON_RFC, MULTI_EMAIL_SEPARATOR)
                        continue_checks = False
                    
                    if continue_checks:
                        # Check MX records
                        domain = em.split('@')[1]
                        if not check_mx_domains(domain):
                            stats.incorrect_mx += 1
                            em_state = add_to_text(em_state, EM_NO_MX, MULTI_EMAIL_SEPARATOR)
                            continue_checks = False

                    if continue_checks:
                        # Check for ambiguous emails
                        if check_ambiguous(em):
                            stats.ambiguous += 1
                            em_state = add_to_text(em_state, EM_AMBIGUOUS, MULTI_EMAIL_SEPARATOR)
                            continue_checks = False
                    
                    # Email is valid
                    stats.valid += 1
                    # Set final state for this email addr
                    if continue_checks:
                        em_state = add_to_text(em_state, EM_VALID, MULTI_EMAIL_SEPARATOR)
                    new_email_col = add_to_text(new_email_col, em , MULTI_EMAIL_SEPARATOR)

                col_state = add_to_text(col_state, em_state)
                row[email_column] = new_email_col
              
            row_state = add_to_text(row_state, col_state, STATE_COLUMN_SEPARATOR)
                
            row['STATE'] = row_state
            writer.writerow(row)
            # Progress update
            if count % 50 == 0:
                print(f".", end='', flush=True)
    
    stats.print_stats()
    print(f"\nCurated file saved to: {output_file}")
    
    # Print cache statistics
    cache_info = check_mx_domains.cache_info()
    print(f"\nDNS Cache Statistics:")
    print(f"  Hits: {cache_info.hits}")
    print(f"  Misses: {cache_info.misses}")
    print(f"  Cache size: {cache_info.currsize}/{cache_info.maxsize}")
    if cache_info.hits + cache_info.misses > 0:
        hit_rate = cache_info.hits / (cache_info.hits + cache_info.misses) * 100
        print(f"  Hit rate: {hit_rate:.1f}%")


def usage():
    """Print usage information"""
    print(f"emailCheck.py v{PROGRAM_VERSION} (build {PROGRAM_BUILD})")
    print("(L) 2014-2025 by Orsiris de Jong")
    print("http://www.netpower.fr/ - ozy@netpower.fr")
    print()
    print("Usage: python emailCheck.py /path/to/emailList")
    print("Email list needs to be a CSV file encoded in UTF-8.")
    print("Checks if emails are RFC822 valid, corrects known typos in domain names,")
    print("checks for valid MX records (with caching), and checks against known ambiguous mail addresses.")
    print()
    print("Outputs one curated file with a STATE column indicating the validation result.")
    sys.exit(1)


def main():
    """Main entry point"""
    if len(sys.argv) != 2:
        usage()
    
    input_file = sys.argv[1]
    
    # Check environment
    check_environment()
    
    # Generate output filename
    input_path = Path(input_file)
    output_file = input_path.parent / f"curated-{input_path.name}"
    
    # Process emails
    print(f"Processing file: {input_file}")
    process_emails(input_file, output_file)


if __name__ == "__main__":
    main()
