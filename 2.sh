#!/bin/bash
set -euo pipefail

##############################################################################
# Implementation Script 122.sh
# Final cleanup, test enhanced generator, and sync both branches
##############################################################################

echo "=============================================="
echo "Final Cleanup and Branch Synchronization"
echo "=============================================="
echo ""

echo "=== Final Cleanup ==="

# Remove remaining old scripts
rm -f 1.sh 7.sh 10.sh 11.sh tatus 122.sh
echo "Removed remaining old scripts"

# Stage the deletions
git rm -f 10.sh 11.sh 7.sh 2>/dev/null || true
git rm -f modules/cidr_generator.sh modules/csv_processor.sh 2>/dev/null || true

echo ""
echo "=== Committing Cleanup to Main ==="
git add -A
git commit -m "chore: Final cleanup of old scripts

- Remove remaining numbered scripts (7,10,11)
- Remove old module attempts (cidr_generator, csv_processor)
- Clean working state with Module 1 complete"

echo "✓ Committed to main"

echo ""
echo "=== Testing Enhanced Generator ==="

# Test the enhanced generator
GENERATOR="existing_scripts/generate-enhanced/generate-enhanced.sh"
if [[ -f "$GENERATOR" ]]; then
    echo "Found enhanced generator, testing..."
    
    if $GENERATOR generated/cidrs.txt > generated/hostnames.zone 2>generated/generator.log; then
        RECORDS=$(grep -c "IN A" generated/hostnames.zone || echo "0")
        echo "✓ Generated $RECORDS A records"
        
        echo ""
        echo "Sample hostnames (should be non-enumerable):"
        echo "---------------------------------------------"
        grep "IN A" generated/hostnames.zone | head -5
        echo "---------------------------------------------"
    else
        echo "✗ Generator failed - check generated/generator.log"
    fi
fi

echo ""
echo "=== Syncing to Develop Branch ==="

# Push main first
echo "Pushing main to origin..."
git push origin main

# Now sync to develop
echo ""
echo "Switching to develop branch..."
git checkout develop

echo ""
echo "Merging main into develop..."
git merge main -m "merge: Sync Module 1 completion from main

- Module 1 (CSV processing) complete and tested
- All old scripts cleaned up
- Ready for Module 2 development"

echo ""
echo "Pushing develop to origin..."
git push origin develop

echo ""
echo "=== Branch Status ==="
echo "Current branch:"
git branch --show-current

echo ""
echo "Comparison with main:"
git log --oneline -5

echo ""
echo "=============================================="
echo "✓ Both branches synchronized"
echo "✓ Module 1 complete" 
echo "✓ Ready for Module 2"
echo "=============================================="
echo ""
echo "You are now on DEVELOP branch"
echo "Module 2 can begin: Enhanced Generator Integration"
