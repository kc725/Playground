#!/bin/bash

# Exit immediately if a command exits with a non-zero status.
# Treat unset variables as an error.
# Pipes fail if any command in the pipe fails.
set -euo pipefail

# Script to run aider with gemma4:e4b ollama model

# --- Configuration ---
MODEL_NAME="gemma4:e4b"
OLLAMA_MODEL_ID="ollama/gemma4:e4b"

# --- Dependency Checks ---

# Check if ollama is installed
if ! command -v ollama &> /dev/null; then
    echo "Error: 'ollama' command not found. Please install Ollama first."
    exit 1
fi

# Check if aider is installed
if ! command -v aider &> /dev/null; then
    echo "Error: 'aider' command not found. Please install Aider first."
    exit 1
fi

# --- Model Setup ---

# Pull the model if not already present
echo "--- Checking for ${MODEL_NAME} model ---"
if ! ollama pull "${MODEL_NAME}"; then
    echo "Error: Failed to pull model ${MODEL_NAME}. Please check your network connection or verify the model name."
    exit 1
fi
echo "Successfully ensured ${MODEL_NAME} is available."

# Set the model for aider
export OLLAMA_MODEL="${MODEL_NAME}"

# --- Execution ---

# Run aider with the specified model
echo "--- Starting aider with ${MODEL_NAME} model ---"
aider --model "${OLLAMA_MODEL_ID}"