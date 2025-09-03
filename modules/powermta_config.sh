#!/bin/bash
set -euo pipefail

##############################################################################
# powermta_config.sh - Generate PowerMTA Virtual MTA Configurations
# Part of MailOps Orchestrator
# Reads enhanced hostnames from zone parser output
##############################################################################

source ../config.sh

echo "PowerMTA configuration generator"
echo "Using port: $PMTA_PORT"
echo "This module reads enhanced hostnames from parsed/ directory"
