# MailOps Orchestrator

Enterprise-grade email infrastructure automation system for managing PowerMTA, DNS, and MailWizz configurations at scale.

## Overview

MailOps Orchestrator automates the complete email infrastructure pipeline from CSV input to fully configured mail servers with non-enumerable hostnames, eliminating manual configuration and security vulnerabilities.

## Features

- **Non-Enumerable Hostname Generation**: 15+ naming patterns prevent server enumeration
- **Automated DNS Management**: Generates A, PTR, SPF, DKIM records for Cloudflare
- **PowerMTA Integration**: Creates virtual MTA configurations with enhanced hostnames
- **MailWizz Database Sync**: Automated delivery server provisioning
- **Comprehensive Logging**: Debug mode for troubleshooting

## Installation

```bash
git clone https://github.com/dennnisdasilva/swiftinbox.com--mailops-orchestrator.git
cd mailops-orchestrator
cp config.sh.template config.sh
# Edit config.sh with your settings
Usage
bash# Run in normal mode
./orchestrator.sh

# Run with debug logging
./orchestrator.sh --debug
Pipeline Flow

Input: CSV file with IP ranges and domains
CIDRS Generation: Converts CSV to enhanced generator format
Hostname Generation: Creates non-enumerable hostnames
DKIM Generation: Creates key pairs for all domains
Infrastructure Generation: Produces all configuration files
PowerMTA Config: Virtual MTA configurations per domain
DNS Updates: Cloudflare-compatible update file
Database Sync: MailWizz delivery server records

Configuration
Edit config.sh to set:

PowerMTA paths and settings
DKIM key size and locations
Database credentials (via .my.cnf)
DNS TTL values
Mailbox prefixes

Project Structure
mailops-orchestrator/
├── orchestrator.sh           # Main control script
├── config.sh                # Configuration settings
├── input/
│   └── new.csv             # Input data
├── existing_scripts/        # Legacy script integration
│   └── generate-enhanced/  # Hostname generator
├── generated/              # Intermediate files
├── output/                 # Final configurations
└── logs/                   # Debug and error logs
Requirements

Bash 4.2+
jq for JSON processing
OpenSSL for DKIM generation
MySQL client for database operations

Support
For issues or questions, please open an issue on GitHub.
License
Proprietary - All rights reserved
