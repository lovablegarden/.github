#!/bin/bash

# Script to set up Java backend workflow templates in other projects
# Usage: ./setup-java-backend-workflows.sh <target-repo-path>

set -e

TARGET_REPO="$1"

if [ -z "$TARGET_REPO" ]; then
    echo "Usage: $0 <target-repo-path>"
    echo "Example: $0 ../my-other-java-project"
    exit 1
fi

if [ ! -d "$TARGET_REPO" ]; then
    echo "Error: Target repository directory '$TARGET_REPO' does not exist"
    exit 1
fi

echo "Setting up Java backend workflow templates in $TARGET_REPO..."

# Create .github directory structure
mkdir -p "$TARGET_REPO/.github/workflows"

# Create CI workflow
echo "Creating CI workflow..."
cat > "$TARGET_REPO/.github/workflows/ci.yml" << 'EOF'
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

permissions:
  contents: read
  packages: write

jobs:
  ci:
    uses: gardentalkz/.github/.github/workflows/java-21-gradle-ci.yml@main
    secrets:
      GH_PACKAGES_TOKEN: ${{ secrets.GH_PACKAGES_TOKEN }}
EOF

# Create Release workflow
echo "Creating Release workflow..."
cat > "$TARGET_REPO/.github/workflows/release.yml" << 'EOF'
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g., 1.0.0)'
        required: true
        default: '1.0.0'
        type: string

permissions:
  contents: write
  packages: write

jobs:
  release:
    uses: gardentalkz/.github/.github/workflows/java-21-gradle-release.yml@main
    with:
      version: ${{ github.event.inputs.version }}
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      GH_PACKAGES_TOKEN: ${{ secrets.GH_PACKAGES_TOKEN }}
EOF

echo "✅ Java backend workflow templates have been set up in $TARGET_REPO"
echo ""
echo "Next steps:"
echo "1. Review and customize the workflows if needed"
echo "2. Ensure your project has:"
echo "   - Gradle wrapper (gradlew, gradlew.bat)"
echo "   - Dockerfile in the root directory"
echo "   - build.gradle with proper version configuration"
echo "3. Configure any necessary GitHub secrets:"
echo "   - GH_PACKAGES_TOKEN (for GitHub Packages access)"
echo "4. Commit and push the changes"
echo ""
echo "The workflows will automatically:"
echo "- Build and test on push/PR to main/develop branches"
echo "- Publish Docker images on main branch"
echo "- Create releases when manually triggered" 