# CI/CD Pipeline Documentation

## Overview

This project implements security-first CI/CD pipelines for the Email Assistant application using GitHub Actions with immutable action pinning, comprehensive security scanning, and least-privilege permissions.

## Security-First Principles

### 1. **Immutable Action Pinning** ✅

All GitHub Actions are pinned to **full commit SHAs** instead of mutable tags to prevent supply chain attacks.

### 2. **Least Privilege Permissions** ✅

Default permissions are read-only, with explicit grants only when needed.

### 3. **OIDC Authentication** ✅

The deploy workflow uses OpenID Connect (OIDC) for Azure authentication—no long-lived credentials.

### 4. **Comprehensive Security Scanning** ✅

- **pip-audit** - Python dependency vulnerabilities
- **Dependency Review** - PR-level vulnerable dependency detection  
- **Trivy** - Container image vulnerabilities (CRITICAL, HIGH)

## CI Pipeline (ci.yml)

### Jobs

1. **Python Quality Checks** - Lint, format, type check, test
2. **Dependency Review** - Scan PRs for vulnerable dependencies
3. **Docker Build & Scan** - Build and scan container with Trivy

## Deploy Pipeline (deploy.yml)

### Jobs

1. **Validate** - Pre-flight configuration checks
2. **Build & Push** - Build and push to ACR with security scan
3. **Deploy** - Deploy to Azure Container Apps with health check

### Required Secrets

- `AZURE_CLIENT_ID`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

### Required Variables

- `AZURE_RESOURCE_GROUP`
- `AZURE_CONTAINER_REGISTRY_NAME`
- `AZURE_CONTAINER_REGISTRY_LOGIN_SERVER`

## References

- [Deployment Guide](../infra/DEPLOYMENT_GUIDE.md)
- [README](../README.md)
