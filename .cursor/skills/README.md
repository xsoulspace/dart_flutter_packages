# Monorepo Skills for Dart/Flutter Packages

This directory contains 8 specialized skills designed to help develop and maintain this Dart/Flutter monorepo with 30+ packages.

## Available Skills

### 1. Package Publishing & Versioning
**Location:** `package-publishing/`
**Use when:** Publishing packages, updating versions, preparing releases

**Key features:**
- Version validation and semver guidance
- Changelog management
- Dependency version checks
- Dry-run validation
- Multi-package publishing workflows

### 2. Monorepo Dependency Graph Analyzer
**Location:** `dependency-graph-analyzer/`
**Use when:** Analyzing dependencies, planning updates, checking conflicts

**Key features:**
- Build dependency graphs
- Detect circular dependencies
- Find version conflicts
- Determine update order
- Impact analysis for changes

### 3. Package Bootstrap & Setup
**Location:** `package-bootstrap/`
**Use when:** Creating new packages, setting up package structure

**Key features:**
- Scaffold new packages with conventions
- Generate standard files (pubspec.yaml, README, etc.)
- Create proper directory structure
- Initialize tests and documentation
- Support for Dart and Flutter packages

### 4. Cross-Package Test Runner
**Location:** `cross-package-test-runner/`
**Use when:** Running tests, checking coverage, validating changes

**Key features:**
- Run tests across multiple packages
- Execute tests in dependency order
- Generate coverage reports
- Smart test selection (changed packages only)
- Parallel test execution

### 5. Breaking Change Impact Analyzer
**Location:** `breaking-change-analyzer/`
**Use when:** Making API changes, planning breaking changes

**Key features:**
- Identify breaking changes
- Find affected packages
- Generate migration guides
- Plan update strategies
- Version bump recommendations

### 6. Documentation Generator & Validator
**Location:** `documentation-validator/`
**Use when:** Documenting code, checking documentation coverage

**Key features:**
- Validate dartdoc completeness
- Check README quality
- Generate API documentation
- Verify code examples
- Documentation templates

### 7. Platform-Specific Package Manager
**Location:** `platform-package-manager/`
**Use when:** Working with platform-specific code, managing store implementations

**Key features:**
- Manage platform-specific implementations
- Handle conditional imports
- Support multiple app stores (Google Play, App Store, Huawei, RuStore, etc.)
- Platform detection utilities
- Compatibility matrix generation

### 8. Makefile Command Orchestrator
**Location:** `makefile-orchestrator/`
**Use when:** Running make commands, managing build scripts

**Key features:**
- Execute Makefile commands across packages
- Validate Makefile consistency
- Add standard targets
- Orchestrate multi-package operations
- Generate comprehensive Makefiles

## How Skills Work

Skills are automatically discovered by Cursor AI based on:
1. **Trigger terms** in the description
2. **Context** of your current task
3. **Explicit mentions** by you

### Triggering Skills

Skills activate when you mention relevant terms:

- "publish package" → Package Publishing skill
- "analyze dependencies" → Dependency Graph Analyzer skill
- "create new package" → Package Bootstrap skill
- "run tests" → Cross-Package Test Runner skill
- "breaking change" → Breaking Change Analyzer skill
- "documentation" → Documentation Validator skill
- "platform-specific" → Platform Package Manager skill
- "makefile" → Makefile Orchestrator skill

### Using Skills Explicitly

You can also explicitly reference skills:
```
"Use the package-publishing skill to help me publish universal_storage_sync"
"Apply the dependency-graph-analyzer skill to check what depends on xsoulspace_foundation"
```

## Quick Start Examples

### Publishing a Package
```
"Help me publish universal_storage_interface to pub.dev"
```
→ Activates Package Publishing skill

### Creating a New Package
```
"Create a new package called universal_storage_cache"
```
→ Activates Package Bootstrap skill

### Analyzing Dependencies
```
"Show me what packages depend on xsoulspace_foundation"
```
→ Activates Dependency Graph Analyzer skill

### Running Tests
```
"Run tests for all packages that changed since last commit"
```
→ Activates Cross-Package Test Runner skill

### Checking Documentation
```
"Validate documentation for universal_storage_sync"
```
→ Activates Documentation Validator skill

## Skill Priority Order

For maximum impact, focus on these skills first:

1. **Package Publishing** - Most time-saving for releases
2. **Dependency Graph Analyzer** - Critical for understanding impact
3. **Cross-Package Test Runner** - Essential for quality
4. **Package Bootstrap** - Saves time on new packages
5. **Breaking Change Analyzer** - Prevents breaking dependents
6. **Documentation Validator** - Maintains quality standards
7. **Platform Package Manager** - Specific to multi-platform needs
8. **Makefile Orchestrator** - Nice to have for consistency

## Customization

Each skill can be customized by editing its `SKILL.md` file. The skills are designed to be:

- **Concise** - Under 500 lines for optimal performance
- **Actionable** - Step-by-step instructions
- **Contextual** - Specific to this monorepo's structure
- **Maintainable** - Easy to update as needs change

## Maintenance

To keep skills effective:

1. **Update when conventions change** - If you change package structure, update relevant skills
2. **Add new patterns** - When you discover new workflows, add them to skills
3. **Remove outdated info** - Keep skills current with latest practices
4. **Test regularly** - Ensure skills still work as expected

## Contributing to Skills

When improving skills:

1. Keep descriptions specific and include trigger terms
2. Maintain concise, actionable content
3. Include concrete examples
4. Follow the progressive disclosure pattern
5. Test that AI can follow the instructions

## Getting Help

If a skill isn't working as expected:

1. Check the skill's description matches your use case
2. Try using more specific trigger terms
3. Explicitly mention the skill name
4. Review the skill's SKILL.md for guidance

## Monorepo Structure Context

These skills are designed for this specific monorepo structure:

```
dart_flutter_packages/
├── pkgs/
│   ├── universal_storage_* (8 packages)
│   ├── xsoulspace_monetization_* (6 packages)
│   ├── xsoulspace_review_* (7 packages)
│   ├── xsoulspace_* (9 foundation packages)
│   └── rustore_billing_api
├── .cursor/
│   ├── rules/
│   └── skills/  ← You are here
└── ...
```

**Package families:**
- Universal Storage (8 packages)
- Monetization (6 packages)
- Review/Rating (7 packages)
- Foundation utilities (9 packages)

**Total:** 30+ packages with complex interdependencies

## Next Steps

1. Try using a skill by mentioning relevant terms in your requests
2. Explore individual skill files for detailed documentation
3. Customize skills to match your specific workflows
4. Add new skills as you discover new patterns

---

**Created:** 2026-01-16
**Last Updated:** 2026-01-16
**Skills Version:** 1.0.0
