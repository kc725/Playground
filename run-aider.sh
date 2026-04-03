#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Pipes fail if any command in the pipe fails.
set -euo pipefail

# Script to run aider with OpenRouter (default) or Ollama
# Usage: ./run-aider.sh           # uses OpenRouter (default)
#        ./run-aider.sh --ollama  # uses Ollama

# --- Configuration ---
OLLAMA_MODEL_NAME="gemma4:e4b"
OLLAMA_MODEL_ID="ollama/gemma4:e4b"
OPENROUTER_MODEL_ID="openrouter/qwen/qwen3.6-plus:free"

# --- Dependency Checks ---

# Check if aider is installed
if ! command -v aider &> /dev/null; then
    echo "Error: 'aider' command not found. Please install Aider first."
    exit 1
fi

# --- Argument Parsing ---
USE_OLLAMA=false
for arg in "$@"; do
    case $arg in
        --ollama)
            USE_OLLAMA=true
            ;;
    esac
done

# --- Ollama Mode ---
if [ "$USE_OLLAMA" = true ]; then
    if ! command -v ollama &> /dev/null; then
        echo "Error: 'ollama' command not found. Please install Ollama first."
        exit 1
    fi

    echo "--- Checking for ${OLLAMA_MODEL_NAME} model ---"
    if ! ollama pull "${OLLAMA_MODEL_NAME}"; then
        echo "Error: Failed to pull model ${OLLAMA_MODEL_NAME}. Please check your network connection or verify the model name."
        exit 1
    fi
    echo "Successfully ensured ${OLLAMA_MODEL_NAME} is available."

    export OLLAMA_MODEL="${OLLAMA_MODEL_NAME}"

    echo "--- Starting aider with ${OLLAMA_MODEL_NAME} model ---"
    aider --model "${OLLAMA_MODEL_ID}"
    exit 0
fi

# --- OpenRouter Mode (default) ---
if [ -z "${OPENROUTER_API_KEY:-}" ]; then
    echo "Error: OPENROUTER_API_KEY environment variable is not set."
    echo "Set it with: export OPENROUTER_API_KEY=your_key_here"
    exit 1
fi

echo "--- Starting aider with OpenRouter model ---"
aider --model "${OPENROUTER_MODEL_ID}"