# Workflow Templates for Java Backend Projects

This directory contains reusable GitHub Actions workflow templates for Java backend projects using Gradle.

## Available Templates

### 1. CI Template (`ci.yml`)

A comprehensive CI workflow that includes:
- Build with Gradle
- Run tests
- Publish Docker images to GitHub Container Registry
- Multi-platform Docker builds (linux/amd64, linux/arm64)

**Usage:**
```yaml
name: CI

on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  ci:
    uses: ./.github/workflow-templates/ci.yml
```

### 2. Release Template (`release.yml`)

A release workflow that includes:
- Build and test the application
- Create Docker images with version tags
- Create Git tags
- Create GitHub releases
- Automatically bump version for next development iteration

**Usage:**
```yaml
name: Release

on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g., 1.0.0)'
        required: true
        default: '1.0.0'
        type: string

jobs:
  release:
    uses: ./.github/workflow-templates/release.yml
    with:
      version: ${{ github.event.inputs.version }}
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## Prerequisites

For these templates to work properly, your project should have:

1. **Gradle Wrapper**: The project should include `gradlew` and `gradlew.bat` files
2. **Dockerfile**: A Dockerfile in the root directory for containerization
3. **GitHub Secrets**: 
   - `GITHUB_TOKEN` (automatically provided)
   - `GH_PACKAGES_TOKEN` (optional, for GitHub Packages access)

## Project Structure

Your Java backend project should follow this structure:
```
your-project/
├── .github/
│   └── workflows/
│       ├── ci.yml
│       └── release.yml
├── src/
│   └── main/
│       └── java/
├── build.gradle
├── gradlew
├── gradlew.bat
└── Dockerfile
```

## Customization

These templates are designed to work with most Java backend projects, but you may need to customize:

1. **Docker Image Names**: The templates use `ghcr.io/${{ github.repository_owner }}/${{ github.event.repository.name }}` for Docker images
2. **Java Version**: Currently set to JDK 21, modify in the template if needed
3. **Branch Names**: Modify the trigger branches in your workflow files
4. **Build Arguments**: Add any specific build arguments your project needs

## For Other Java Backend Projects

To use these templates in other repositories:

1. **Quick Setup**: Use the provided script:
   ```bash
   .github/setup-workflow-templates.sh /path/to/other-project
   ```

2. **Manual Setup**: Copy the `.github/workflow-templates/` directory to your repository
3. Create workflow files in `.github/workflows/` that call these templates
4. Ensure your project has the required prerequisites (Gradle wrapper, Dockerfile)
5. Configure any necessary secrets in your repository settings

## Notes

- These templates assume Gradle is used as the build tool
- Docker images are published to GitHub Container Registry (ghcr.io)
- The release workflow automatically increments the patch version for the next development iteration
- Test results are uploaded as artifacts for inspection 