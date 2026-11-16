# 🚀 Reusable GitHub Workflows

This repository contains centralized, reusable GitHub Actions workflows for various project types and technologies. These workflows promote consistency, maintainability, and efficiency across all our projects.

## 🔒 Security and supply chain

| Workflow / file | What it does | Docs |
| --- | --- | --- |
| `security-scan.yml` | Secrets, dependencies, IaC, image and SAST scans; dated risk acceptances; lifecycle checks; nightly Jira triage | [adopting](docs/security/adopting.md#1-security-scan), [CVE policy](docs/security/cve-policy.md) |
| `release-provenance.yml` | SBOM, provenance and signed attestations for each release; final-image gate before the system-lock bump | [adopting](docs/security/adopting.md#2-release-provenance), [SBOM and provenance](docs/security/sbom-provenance.md) |
| `default.json` | Shared Renovate preset: Actions pinned by SHA, base images by digest | [renovate](docs/renovate.md), [lifecycle](docs/security/lifecycle.md) |
| `SECURITY.md` | Org-wide vulnerability reporting policy | |

## 📁 Repository Structure

```
.github/
├── workflows/
│   ├── frontend/           # Frontend project workflows
│   │   ├── frontend-ci-cd.yml
│   │   └── frontend-release.yml
│   ├── backend/            # Backend project workflows (future)
│   │   └── [coming soon]
│   └── shared/             # Shared utility workflows (future)
│       └── [coming soon]
└── README.md
```

## 🎯 Available Workflows

### 🌐 Frontend Workflows

#### **`frontend-ci-cd.yml`**
Comprehensive CI/CD pipeline for frontend applications (React, Vue, Angular, etc.)

**Features:**
- ✅ Build and lint validation
- ✅ Optional testing
- ✅ Docker image building and publishing
- ✅ Artifact uploads
- ✅ Multi-platform Docker builds (AMD64 + ARM64)
- ✅ Configurable ESLint warning limits
- ✅ Rich build summaries

**Usage:**
```yaml
name: CI/CD
on:
  push:
    branches: [ main, develop ]
  pull_request:
    branches: [ main, develop ]

jobs:
  ci-cd:
    uses: gardentalkz/.github/.github/workflows/frontend/frontend-ci-cd.yml@main
    with:
      node-version: '20.x'
      lint-command: 'npm run lint:ci'
      build-command: 'npm run build'
      docker-registry: 'ghcr.io'
      project-name: 'my-frontend-app'
      docker-enabled: true
      run-tests: false
      max-warnings: 600
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
      NPM_TOKEN: ${{ secrets.NPM_TOKEN }}
```

#### **`frontend-release.yml`**
Automated release management for frontend applications

**Features:**
- ✅ Version bumping and tagging
- ✅ Docker image publishing with proper versioning
- ✅ GitHub release creation with assets
- ✅ Archive generation (tar.gz, zip)
- ✅ Next snapshot version preparation
- ✅ Prerelease support

**Usage:**
```yaml
name: Release
on:
  workflow_dispatch:
    inputs:
      version:
        description: 'Release version (e.g., 1.0.0)'
        required: true
        type: string
      prerelease:
        description: 'Mark as pre-release'
        required: false
        type: boolean
        default: false

jobs:
  release:
    uses: gardentalkz/.github/.github/workflows/frontend/frontend-release.yml@main
    with:
      version: ${{ github.event.inputs.version }}
      prerelease: ${{ github.event.inputs.prerelease }}
      docker-registry: 'ghcr.io'
      project-name: 'my-frontend-app'
      docker-enabled: true
      create-archives: true
    secrets:
      GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

## 🔧 Configuration Options

### Frontend CI/CD Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `node-version` | Node.js version to use | `20.x` | ❌ |
| `lint-command` | Command to run linting | `npm run lint:ci` | ❌ |
| `build-command` | Command to build the project | `npm run build` | ❌ |
| `test-command` | Command to run tests | `npm test` | ❌ |
| `docker-registry` | Docker registry to publish to | `ghcr.io` | ❌ |
| `project-name` | Name of the project for Docker image | - | ✅ |
| `docker-enabled` | Whether to build and publish Docker images | `true` | ❌ |
| `run-tests` | Whether to run tests | `false` | ❌ |
| `max-warnings` | Maximum ESLint warnings allowed | `600` | ❌ |

### Frontend Release Inputs

| Input | Description | Default | Required |
|-------|-------------|---------|----------|
| `version` | Release version (e.g., 1.0.0) | - | ✅ |
| `prerelease` | Mark as pre-release | `false` | ❌ |
| `node-version` | Node.js version to use | `20.x` | ❌ |
| `lint-command` | Command to run linting | `npm run lint:ci` | ❌ |
| `build-command` | Command to build the project | `npm run build` | ❌ |
| `docker-registry` | Docker registry to publish to | `ghcr.io` | ❌ |
| `project-name` | Name of the project for Docker image | - | ✅ |
| `docker-enabled` | Whether to build and publish Docker images | `true` | ❌ |
| `create-archives` | Whether to create archive files | `true` | ❌ |
| `max-warnings` | Maximum ESLint warnings allowed | `600` | ❌ |

## 🔐 Required Secrets

### For All Workflows
- `GITHUB_TOKEN` - GitHub token for authentication ✅ (auto-provided)

### For NPM Private Packages (Optional)
- `NPM_TOKEN` - NPM token for private package access

## 📦 Docker Image Versioning

Docker images are automatically tagged with:
- **Version from package.json** (e.g., `1.0.0`, `1.0.0-SNAPSHOT`)
- **`latest`** for stable releases (non-prerelease)
- **Git commit SHA** for traceability (e.g., `main-abc1234`)

## 🚀 Getting Started

### 1. For Frontend Projects

1. **Create CI/CD workflow** in your project:
   ```bash
   # In your project repository
   mkdir -p .github/workflows
   ```

2. **Create `.github/workflows/ci-cd.yml`**:
   ```yaml
   name: CI/CD
   on:
     push:
       branches: [ main, develop ]
     pull_request:
       branches: [ main, develop ]
   
   jobs:
     ci-cd:
       uses: gardentalkz/.github/.github/workflows/frontend/frontend-ci-cd.yml@main
       with:
         project-name: 'your-project-name'
       secrets:
         GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```

3. **Create `.github/workflows/release.yml`**:
   ```yaml
   name: Release
   on:
     workflow_dispatch:
       inputs:
         version:
           description: 'Release version'
           required: true
           type: string
         prerelease:
           description: 'Mark as pre-release'
           required: false
           type: boolean
           default: false
   
   jobs:
     release:
       uses: gardentalkz/.github/.github/workflows/frontend/frontend-release.yml@main
       with:
         version: ${{ github.event.inputs.version }}
         prerelease: ${{ github.event.inputs.prerelease }}
         project-name: 'your-project-name'
       secrets:
         GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
   ```

4. **Ensure your project has**:
   - `package.json` with proper version
   - `npm run build` command
   - `npm run lint:ci` command
   - `Dockerfile` (if Docker is enabled)

## 🛠️ Future Enhancements

### 📋 TODO List

- [x] **Security Scanning**: `security-scan.yml` and `release-provenance.yml` (see above)
- [ ] **Backend Workflows**: Spring Boot, Node.js API, Python, etc.
- [ ] **OpenAPI Generator**: Centralized model generation workflows
- [ ] **Mobile Workflows**: React Native, Flutter support
- [ ] **Infrastructure**: Terraform, Helm chart deployment workflows
- [ ] **Shared Utilities**: Docker build, security scan, notification workflows
- [ ] **Multi-language Support**: Java, Python, Go, Rust workflows
- [ ] **Database Migrations**: Automated database migration workflows
- [ ] **Performance Testing**: Load testing integration
- [ ] **Monitoring**: Automated monitoring setup

### 🔮 Planned Backend Support

```
backend/
├── spring-boot-ci-cd.yml      # Spring Boot applications
├── spring-boot-release.yml    # Spring Boot releases with JAR artifacts
├── nodejs-api-ci-cd.yml       # Node.js API applications
├── python-api-ci-cd.yml       # Python API applications
└── openapi-generator.yml      # OpenAPI model generation
```

### 🔧 Planned Shared Utilities

```
shared/
├── docker-build.yml           # Reusable Docker building
├── security-scan.yml          # Security scanning
├── notification.yml           # Slack/Teams notifications
├── sonar-analysis.yml         # SonarQube analysis
└── performance-test.yml       # Performance testing
```

## 🤝 Contributing

1. **Fork** this repository
2. **Create** a feature branch (`git checkout -b feature/amazing-workflow`)
3. **Commit** your changes (`git commit -m 'Add amazing workflow'`)
4. **Push** to the branch (`git push origin feature/amazing-workflow`)
5. **Open** a Pull Request

## 📚 Best Practices

### ✅ Do's
- Use semantic versioning for releases
- Always test workflows in a fork first
- Use descriptive commit messages
- Keep workflows modular and reusable
- Document all inputs and outputs

### ❌ Don'ts
- Don't hardcode values that should be configurable
- Don't skip security considerations
- Don't create overly complex workflows
- Don't forget to handle error cases

## 🔄 Versioning Strategy

- **`@main`** - Latest stable version (recommended for most use cases)
- **`@v1.0.0`** - Specific version tags (coming soon)
- **`@develop`** - Development version (use at your own risk)

## 📞 Support

For questions or support:
1. **Create an issue** in this repository
2. **Check existing issues** for similar problems
3. **Review the documentation** thoroughly before asking

## 📜 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Made with ❤️ by the GardenTalkz Team**
