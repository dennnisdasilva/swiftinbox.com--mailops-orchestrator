#!/bin/bash
set -euo pipefail

##############################################################################
# dkim_generator.sh - Generate DKIM Keys with Configurable Size
# Part of MailOps Orchestrator
# Creates RSA key pairs for all unique domains
##############################################################################

source ../config.sh

echo "DKIM key generator"
echo "Key size: $DKIM_KEY_SIZE"
echo "Selector: $DKIM_SELECTOR"
