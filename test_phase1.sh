#!/bin/bash
set -euo pipefail

# Test script for Phase 1
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Phase 1 Test Runner"
echo "==================="
echo ""

# Check for config
if [[ ! -f "$PROJECT_ROOT/config.sh" ]]; then
    echo "Creating config.sh from template..."
    cp "$PROJECT_ROOT/config.sh.template" "$PROJECT_ROOT/config.sh"
fi

# Check for input file
if [[ ! -f "$PROJECT_ROOT/input/new.csv" ]]; then
    echo "ERROR: input/new.csv not found"
    echo ""
    echo "Creating sample new.csv for testing..."
    cat > "$PROJECT_ROOT/input/new.csv" << CSV
action,ip_range,domains
add,6.6.6.0/24,"domain1.net,domain2.net,domain3.net,domain4.net,domain5.net,domain6.net,domain7.net,domain8.net"
add,10.10.10.0/27,"priority.io"
CSV
    echo "Sample file created at input/new.csv"
fi

echo "Running Phase 1 orchestrator..."
echo ""

exec "$PROJECT_ROOT/modules/phase1_orchestrator.sh"
