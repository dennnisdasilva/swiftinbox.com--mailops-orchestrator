#!/bin/bash
# git_deploy.sh - Deploy MailOps Orchestrator Updates
# Date: September 5, 2025
# Version: 3.0.0
set -euo pipefail

echo "========================================="
echo "MailOps Orchestrator - Git Deployment"
echo "========================================="

# Ensure we're in the project directory
cd /root/mailops-orchestrator

# Check git status
echo "Checking git status..."
git status

# Add all changes
echo ""
echo "Adding all changes..."
git add -A

# Create comprehensive commit message
COMMIT_MSG="Pipeline Complete: All Core Components Operational

MAJOR ACHIEVEMENTS:
- Fixed zone parser regex to correctly parse 254 records
- Implemented infrastructure.json generator as master data source
- Fixed DKIM public key extraction from nested JSON structure
- Removed duplicate PATCHED function restoring pattern diversity
- All 15 hostname generation patterns now working correctly

PIPELINE STATUS (Options 1-5 ALL WORKING):
✓ CSV to CIDRS: Intelligent domain duplication
✓ Enhanced Generator: 15 algorithmic patterns (NOT random)
✓ Zone Parser: Fixed - correctly parses 254 records
✓ Infrastructure Generator: Complete with DKIM integration
✓ DKIM Management: 2048-bit keys deployed and tracked

CRITICAL FIXES:
- Zone parser regex now matches 'hostname. IN A IP' format
- DKIM extraction uses correct path: .domains[domain].public_key
- Enhanced generator assigns different patterns per domain
- Infrastructure.json properly implements sequential IP distribution

DATA FLOW CORRECTED:
CSV → CIDRS → Hostnames → Zone File
             ↓                ↓
        DKIM Keys      Zone Parser
             ↓                ↓
      dkim_data.json → Infrastructure.json (MASTER)
                             ↓
                   Configuration Export

PENDING IMPLEMENTATION:
- Option 6: PowerMTA config generator
- Option 7: DNS records file for Cloudflare tool
- Option 8: Mailbox configuration
- Option 9: MailWizz SQL with foreign keys

FILES UPDATED:
- modules/zone_parser.sh: Fixed regex pattern
- modules/infrastructure_generator.sh: New module created
- orchestrator.sh: Integrated options 3 & 4 correctly
- generate-enhanced.sh: Removed duplicate process_cidr_block
- README.md: Complete rewrite with pattern details
- updates.md: Comprehensive handoff documentation

TEST RESULTS:
- 254 IPs distributed sequentially across 8 domains
- Each domain uses unique naming pattern
- All DKIM public keys extracted successfully
- Infrastructure.json validates as proper JSON

BREAKING CHANGES:
- Removed numbered build scripts (1.sh-13.sh)
- Infrastructure.json is now master data source
- Parsed files are exports, not inputs

Version: 3.0.0 - Production Ready Core Pipeline"

# Commit changes
echo ""
echo "Committing changes..."
git commit -m "$COMMIT_MSG"

# Push to develop
echo ""
echo "Pushing to develop branch..."
git push origin develop

# Ask about merging to main
echo ""
echo "========================================="
echo "Changes pushed to develop branch"
echo "========================================="
echo ""
read -p "Do you want to merge to main and deploy? (y/N): " MERGE_MAIN

if [[ "$MERGE_MAIN" == "y" ]]; then
   echo "Checking out main branch..."
   git checkout main
   
   echo "Merging develop..."
   git merge develop --no-ff -m "Merge develop: Complete Core Pipeline v3.0.0

Integrates fully operational core pipeline with all pattern generation,
zone parsing, DKIM management, and infrastructure generation working.

Key achievements:
- 15 distinct hostname patterns operational
- Zone parser correctly processing 254 records
- Infrastructure.json as master data source
- DKIM keys integrated throughout system

Ready for PowerMTA, DNS, and MailWizz module implementation."
   
   echo "Pushing to main..."
   git push origin main
   
   echo "Tagging release..."
   git tag -a "v3.0.0" -m "Release v3.0.0: Complete Core Pipeline

OPERATIONAL:
- CSV to CIDRS conversion
- 15-pattern hostname generation
- Zone file parsing (fixed)
- Infrastructure.json generation (new)
- DKIM key management

READY FOR:
- PowerMTA configuration
- DNS records generation
- MailWizz integration

All core components tested and verified with 254 IPs across 8 domains."
   
   git push origin --tags
   
   echo "Returning to develop..."
   git checkout develop
   
   echo ""
   echo "========================================="
   echo "✓ Successfully deployed to main"
   echo "✓ Tagged as v3.0.0"
   echo "========================================="
else
   echo "Deployment to main cancelled"
   echo "Changes remain in develop branch"
fi

echo ""
echo "Current Status:"
echo "- Core pipeline (Options 1-5): COMPLETE"
echo "- Pattern generation: WORKING (15 patterns)"
echo "- Infrastructure.json: GENERATED"
echo "- Next: Implement Options 6-9"
echo ""
echo "Deployment script complete"
