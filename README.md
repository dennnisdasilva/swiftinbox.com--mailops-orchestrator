# MailOps Orchestrator

Enterprise-grade email infrastructure automation system for MailWizz and PowerMTA

## Project Architecture

### Complete Processing Pipeline
```
new.csv → IP distributor (config.sh) → enhanced-generator → zone_parser → 
powermta_config → DKIM generator → DNS updates → Mailbox creation → MailWizz DB
```

### System Components

1. **CSV Input Parser** - Reads domain and IP allocations
2. **IP Distribution Engine** - Configurable allocation strategies
3. **Enhanced Hostname Generator** - 15+ naming patterns, non-enumerable
4. **Zone File Parser** - Synchronized line file generation
5. **PowerMTA Configuration** - Virtual MTA and pool management
6. **DKIM Key Generator** - Configurable key sizes
7. **DNS Management** - Cloudflare API integration
8. **Mailbox Provisioning** - Exim/Dovecot virtual mailboxes
9. **Database Synchronization** - MailWizz 2.7.1 integration

## Quick Start

### 1. Prerequisites
```bash
# Required tools
sudo apt-get install git curl jq openssl
```

### 2. Configuration
```bash
# Copy and edit configuration
cp config.sh.template config.sh
vim config.sh

# Add Cloudflare accounts
cp cloudflare_accounts.json.sample cloudflare_accounts.json
vim cloudflare_accounts.json
```

### 3. Add Existing Scripts
Place your existing scripts in `existing_scripts/`:
- `enhanced-generator.sh`
- `powermta--vmta_configs.sh`
- `powermta--generate_dkim_add_to_configs.sh`
- `cloudflare--dns_management.sh`

### 4. Input Data
Edit `input/new.csv` with your domains and IP ranges

### 5. Run Orchestration
```bash
cd modules
./orchestrator.sh
```

## Repository

- **GitHub**: https://github.com/dennnisdasilva/swiftinbox.com--mailops-orchestrator
- **Author**: dennnisdasilva <dennnisdasilva@gmail.com>
