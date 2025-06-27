#!/bin/bash

##################################################

# Default configuration values


##################################################

# Check if cardano-cli is installed
if ! command -v cardano-cli >/dev/null 2>&1; then
  echo "Error: cardano-cli is not installed or not in your PATH." >&2
  exit 1
fi

# Usage message
usage() {
    echo "Usage: $0 <jsonld-file|directory> [--some-options]"
    echo "Options:"
    echo "  --some-options        Compare against CIP-108 schema (default: $DEFAULT_USE_CIP_108)"
    exit 1
}

# Initialize variables with defaults
input_file=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --some-options)
            use_cip_108="true"
            shift
            ;;
        --cip100)
            use_cip_100="true"
            shift
            ;;
        --cip136)
            use_cip_136="true"
            shift
            ;;
        --intersect-treasury)
            use_intersect_treasury="true"
            shift
            ;;
        --schema)
            user_schema_url="$2"
            user_schema="true"
            shift 2
            ;;
        -h|--help)
            usage
            ;;
        *)
            if [ -z "$input_file" ]; then
                input_file="$1"
            fi
            shift
            ;;
    esac
done

