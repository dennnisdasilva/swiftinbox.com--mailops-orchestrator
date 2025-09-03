#!/bin/bash
set -euo pipefail

##############################################################################
# mailwizz_db.sh - Synchronize to MailWizz Database
# Part of MailOps Orchestrator
# Creates delivery servers, bounce servers, tracking domains, DKIM records
##############################################################################

source ../config.sh

echo "MailWizz database synchronization module"
echo "Database: $DB_NAME@$DB_HOST"

# Order of operations (critical for foreign keys):
# 1. mw_tracking_domain
# 2. mw_bounce_server
# 3. mw_feedback_loop_server
# 4. mw_sending_domain
# 5. mw_delivery_server
# 6. mw_enhanced_hostnames (custom table)
