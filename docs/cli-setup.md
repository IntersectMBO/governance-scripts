# CLI Setup

The governance scripts can be used as a unified CLI tool.

## Installation

### Option 1: Add to PATH (Recommended)

Add the repository directory to your PATH in your shell configuration file:

**For Zsh (macOS default):**
```bash
echo 'export PATH="$PATH:/Users/elenabardho/Cardano/governance-scripts"' >> ~/.zshrc
source ~/.zshrc
```

**For Bash:**
```bash
echo 'export PATH="$PATH:/Users/elenabardho/Cardano/governance-scripts"' >> ~/.bashrc
source ~/.bashrc
```

After this, you can use `governance` from anywhere.

### Option 2: Create a Symlink

Create a symlink in a directory that's already in your PATH:

```bash
sudo ln -s /Users/elenabardho/Cardano/governance-scripts/governance /usr/local/bin/governance
```

### Option 3: Use with Full Path

Run directly from the repository:

```bash
/Users/elenabardho/Cardano/governance-scripts/governance <command>
```

Or create an alias:

```bash
echo 'alias governance="/Users/elenabardho/Cardano/governance-scripts/governance"' >> ~/.zshrc
source ~/.zshrc
```

## Usage

Once installed, use the CLI like this:

```bash
# Show help
governance --help

# Create metadata from markdown
governance metadata-create input.md --governance-action-type info --deposit-return-addr stake1...

# Sign metadata with author
governance author-create metadata.jsonld signing-key.skey --author-name "Your Name"

# Validate metadata
governance metadata-validate metadata.jsonld

# Create info action
governance action-info metadata.jsonld

# Query live actions
governance query-actions

# Get help for a specific command
governance metadata-create --help
```

## Available Commands

- `author-create` - Sign metadata files with author witness
- `author-validate` - Validate author signatures in metadata
- `action-info` - Create an Info action from JSON-LD metadata
- `action-treasury` - Create a Treasury Withdrawal action
- `metadata-create` - Create JSON-LD metadata from Markdown
- `metadata-validate` - Validate JSON-LD metadata
- `metadata-canonize` - Canonize JSON-LD metadata
- `cip108-human` - Create human-readable CIP-108 format
- `hash` - Hash a file
- `ipfs-check` - Check IPFS pinning status
- `ipfs-pin` - Pin files to IPFS
- `pdf-remove-metadata` - Remove metadata from PDF files
- `query-actions` - Query live governance actions
