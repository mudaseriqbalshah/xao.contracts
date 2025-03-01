#!/bin/bash

# Check if repository URL is provided
if [ -z "$1" ]; then
    echo "Please provide your GitHub repository URL"
    echo "Usage: ./init_github.sh <repository-url>"
    exit 1
fi

# Initialize git repository
git init

# Add all files
git add .

# Initial commit
git commit -m "Initial commit: NFT Ticketing System"

# Add remote repository
git remote add origin $1

# Push to main branch
git branch -M main
git push -u origin main

echo "Repository has been initialized and pushed to GitHub!"
