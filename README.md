MailOps Orchestrator - README
Project Overview
MailOps Orchestrator is a comprehensive email infrastructure management system that automates the creation, configuration, and removal of mail server infrastructure at scale. The system generates non-enumerable hostnames, manages DNS records, configures PowerMTA, and maintains a complete infrastructure state in a single master JSON file.
System Architecture
Data Flow

Input: CSV file with CIDR ranges and domain assignments
Processing: Enhanced hostname generation with randomized prefixes
Configuration: DKIM key generation, DNS record creation, PowerMTA setup
State Management: Master infrastructure.json containing all configuration
Output: DNS updates, PowerMTA configs, PTR records, removal manifests

Key Principles

Clean Slate Operations: Every run starts fresh, clearing previous generated files
Historical Tracking: Previous runs archived for removal operations
Single Source of Truth: infrastructure.json contains ALL configuration data
No Orphaned Resources: Complete tracking enables full cleanup

Directory Structure
mailops-orchestrator/
|-- input/
|   |-- new.csv                     # Source data (CIDR ranges and domains)
|-- existing_scripts/
|   |-- generate-enhanced/           # Enhanced hostname generator
|   |-- powermta--*.sh              # PowerMTA and DKIM scripts
|-- generated/
|   |-- hostnames.zone              # Generated enhanced hostnames (cleared each run)
|-- output/                         # All outputs (cleared each run)
|   |-- infrastructure.json         # Master configuration file
|   |-- dns_updates.txt            # Cloudflare DNS import
|   |-- ptr_records.txt            # PTR records for reverse DNS
|   |-- pmta_configs/              # PowerMTA virtual-mta configs
|   |-- keys/                      # DKIM key backups
|   |-- parsed/                    # Backward compatibility files
|   |-- removals/                  # Deletion manifests
|-- previous_runs/                  # Historical archives (persists)
|   |-- YYYY-MM-DD_HHMMSS/         # Timestamped snapshots
|-- orchestrator.sh                 # Main orchestration script
CSV Format Specification
IP Allocation Rules

Never use: .0, .1, or .255 addresses
/24: 253 usable IPs (.2 through .254)
/25: 126 usable IPs
/26: 62 usable IPs
/27: 30 usable IPs
Max per domain: 30 IPs (enforced by enhanced generator)

Format Examples
Basic allocation (domains evenly split IPs):
192.168.1.0/24,domain1.com,domain2.com,domain3.com,domain4.com,domain5.com,domain6.com,domain7.com,domain8.com

253 usable IPs split across 8 domains
Each domain gets approximately 31 IPs (generator limits to 30 max)

Mixed operations:
192.168.1.0/27,shop1.com,shop2.com
10.0.0.0/26,mail1.net,mail2.net,mail3.net
REMOVE,olddomain.com
Removal directive:
REMOVE,domain.com

Domain will be skipped in generation
Removal data pulled from previous_runs/latest/infrastructure.json

Infrastructure.json Structure
The master JSON file contains complete infrastructure state:
Per-Domain Data

IP Mappings: Each IP with its enhanced hostname and configuration
DKIM Configuration: Public keys and file paths
DNS Records: All A, MX, TXT, CNAME records
PTR Records: Reverse DNS entries
PowerMTA Config: Virtual-mta blocks
Bounce/FBL Servers: Mailbox configurations
Management Data: Status, timestamps, change history

Global Data

Metadata: Generation timestamp, totals, versions
Parsed Compatibility: Backward compatibility lists
Audit Trail: Complete change log

DNS Record Structure
For each domain, the system generates:
Infrastructure Records (using placeholder IP 5.135.7.116)

mail.domain.com - A record
pop.domain.com - A record
imap.domain.com - A record
smtp.domain.com - A record

Email Configuration

MX record: domain.com to mail.domain.com (priority 10)
SPF: v=spf1 mx a ip4:CIDR include:amazonses.com ~all
DKIM: key1._domainkey.domain.com
DMARC: Standard policy with admin@domain.com

Per-IP Records

Enhanced hostname A record: random-prefix.subdomain.domain.com to IP
PTR record: IP reverse to enhanced hostname

Tracking

CNAME: tracking.domain.com to mailwizz.swiftiinbox.com

PowerMTA Configuration
Virtual-MTA Naming Convention
domain.com.c[third_octet].[fourth_octet]
Example: example.com.c168.1.5 for IP 192.168.1.5
Pool Naming Convention
MAILWIZZ-01-GI__[enhanced-hostname]-[domain].p
Example: MAILWIZZ-01-GI__xk9pw3mn-lon.mail1-example.com.p
Operation Workflows
Addition Workflow

Add CIDR and domains to new.csv
Run orchestrator
System generates enhanced hostnames
Creates DKIM keys (2048-bit)
Builds infrastructure.json
Generates all configuration files

Removal Workflow

Add "REMOVE,domain.com" to new.csv
Run orchestrator
System skips domain in generation
Looks up old data in previous_runs
Creates removal manifests with exact records to delete

Update Workflow

Modify entries in new.csv
Run orchestrator
Compare with previous_runs for changes
Generate update commands

Implementation Status
Completed Components

CSV to CIDRS converter
Enhanced hostname generator integration
Menu system with debug logging

Pending Implementation

DKIM generator integration (2048-bit keys)
Infrastructure.json generator
PowerMTA configuration adaptation
DNS update file generator
Removal processing logic


