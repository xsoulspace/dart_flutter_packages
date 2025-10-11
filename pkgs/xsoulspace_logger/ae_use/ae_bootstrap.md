<!--
version: 1.0.0
library: xsoulspace_logger
repository: https://github.com/xsoulspace/xsoulspace_packages
license: MIT
-->

# AE Bootstrap Context for xsoulspace_logger

This document guides AI agents in analyzing, creating, and maintaining Agentic Executable (AE) files for xsoulspace_logger. Refer to `ae_context.md` for common terms, principles, and working principles.

## Bootstrap Workflow

### 1. Locate AE Files

Search for existing AE files in `ae_use/`:

- `ae_context.md` - Domain knowledge and definitions
- `ae_bootstrap.md` - This file (bootstrap instructions)
- `ae_install.md` - Installation and integration guide
- `ae_uninstall.md` - Uninstallation and cleanup guide
- `ae_update.md` - Update and migration guide
- `ae_use.md` - Usage patterns and best practices

### 2. Analyze Codespace

Review xsoulspace_logger structure:

- **Core Files**: `lib/src/logger.dart`, `logger_config.dart`, `log_level.dart`, `file_writer.dart`
- **Main Export**: `lib/xsoulspace_logger.dart`
- **Dependencies**: Pure Dart (no external deps beyond dev tools)
- **Architecture**: Singleton logger with configuration presets
- **Key Features**: Console/file output, log rotation, structured logging

### 3. Conditional Action

**If AE Files Exist** (current state):

- Compare library code with AE documentation
- Check for new features (e.g., new presets, config options)
- Verify log levels and methods are up-to-date
- Update integration patterns if architecture changed
- Ensure uninstallation steps reverse new integrations
- Update usage patterns for new capabilities

**If AE Files Do Not Exist**:

- Generate all six AE files from scratch
- Analyze library API from source code
- Extract integration points from README and code
- Create configuration patterns from LoggerConfig presets
- Document lifecycle: initialization → usage → disposal

### 4. Generate/Update Content

#### ae_context.md (Domain Knowledge)

- **Library Overview**: Core functionality and purpose
- **Domain Knowledge**: Logger lifecycle, components, integration points
- **Configuration Parameters**: Config options and presets
- **Best Practices**: Logging patterns specific to xsoulspace_logger
- **Anti-Patterns**: Common mistakes to avoid
- **Guidelines**: Context-specific guidance for each AE operation

**Content Structure**:

```markdown
# Definitions

# Library Overview

# Core Principles

# Domain Knowledge

- Logger Lifecycle
- Key Components
- Integration Points
- Configuration Parameters

# Working Principles

# Logger-Specific Guidelines

# Best Practices

# Anti-Patterns
```

#### ae_install.md (Installation & Integration)

- **Installation**: Add dependency, run pub get
- **Configuration**: Choose preset or create custom config
- **Integration**: Initialize in main(), integrate in layers
  - Service layer logging
  - State management logging
  - Error boundary integration
  - Lifecycle cleanup
- **Validation**: Verify installation, output, levels, rotation
- **Troubleshooting**: Common issues and solutions
- **Best Practices**: Setup recommendations
- **Checklist**: Verification items

**Key Integration Patterns**:

1. Early initialization in `main()`
2. Singleton access throughout app
3. Service layer wrapping
4. Error boundary logging
5. Cleanup on dispose/exit

#### ae_uninstall.md (Removal & Cleanup)

- **Pre-Uninstallation**: Backup logs, identify usage
- **Uninstallation Steps**:
  - Remove integrations (initialization, calls, cleanup)
  - Remove imports
  - Remove configuration
  - Remove dependency
  - Clean build artifacts
- **Post-Uninstallation**: Verify removal, clean logs, update docs
- **Replacement**: Alternative logging options
- **Validation**: Build and runtime verification
- **Troubleshooting**: Common removal issues
- **Rollback**: Restore procedure
- **Checklist**: Comprehensive removal checklist

**Reversibility Ensures**:

- All logger calls removed
- No orphaned imports or variables
- Dependency completely removed
- Clean compilation
- Optional log file cleanup

#### ae_update.md (Version Migration)

- **Pre-Update**: Backup, check version, review changelog
- **Update Process**: Update version, fetch package, verify
- **Migration by Version**: Version-specific breaking changes
- **Re-Integration**: Update imports, config, initialization, methods
- **Validation**: Static analysis, compilation, runtime, file output
- **Troubleshooting**: Breaking changes, config errors, runtime issues
- **Rollback**: Restore previous version
- **Post-Update**: Documentation, team communication, monitoring
- **Checklist**: Update verification items

**Update Patterns**:

1. Incremental version updates
2. Backup before migration
3. Test in development first
4. Monitor production after deploy

#### ae_use.md (Daily Usage Patterns)

- **Core Concepts**: Levels, configs, lifecycle
- **Common Patterns**:
  - Application initialization
  - Service layer logging
  - Error boundary logging
  - State management logging
  - Network request logging
  - Business logic tracing
  - Environment-based config
  - Performance monitoring
- **Best Practices**: Categories, structured data, levels, error context
- **Anti-Patterns**: Over-logging, sensitive data, wrong levels
- **Performance**: Level filtering, lazy evaluation, rotation
- **Testing**: Test configurations
- **Troubleshooting**: Common usage issues

**Usage Focuses**:

- Practical code examples
- Real-world patterns
- Do's and don'ts
- Performance optimization

### 5. Validate and Test

Simulate agent execution:

- **Installation Test**: Can agent install from scratch?
- **Configuration Test**: Can agent choose appropriate config?
- **Integration Test**: Can agent integrate at key points?
- **Uninstallation Test**: Can agent cleanly remove all traces?
- **Update Test**: Can agent migrate between versions?
- **Usage Test**: Can agent apply patterns correctly?

## Agent Guidelines for Bootstrap

### Analysis and Adaptation

- Follow workflow sequentially
- Analyze library code structure and API
- Extract integration points from source
- Identify configuration options and presets
- Document lifecycle and cleanup procedures
- Align with AE principles (modularity, reversibility, validation)

### Creation/Update Priority

1. Update `ae_context.md` if domain knowledge changed
2. Update `ae_install.md` for new integration points
3. Update `ae_uninstall.md` to reverse new integrations
4. Update `ae_update.md` for breaking changes
5. Update `ae_use.md` for new patterns or features
6. Update `ae_bootstrap.md` (this file) for workflow changes

### Error Handling

- Verify file paths and structure
- Check for breaking changes in library API
- Ensure uninstall reverses all install steps
- Validate code examples compile
- Test configuration patterns

### Optimization

- Keep instructions concise (target <500 LOC per file)
- Focus on agent-executable patterns, not explanations
- Use abstract patterns over specific code when possible
- Cross-reference `ae_context.md` for definitions
- Provide practical examples for complex integrations
- Maintain checklist format for validation

## Library-Specific Bootstrap Notes

### Logger Analysis Points

- **API Surface**: Check Logger class methods (verbose, debug, info, warning, error)
- **Configuration**: Review LoggerConfig presets and options
- **Lifecycle**: Document initialization, usage, disposal pattern
- **File Output**: Verify FileWriter integration and rotation
- **Performance**: Document filtering and async patterns

### Integration Detection

- Search for common patterns:
  - `Logger()` factory calls
  - `LoggerConfig.*` preset usage
  - `.verbose()`, `.debug()`, `.info()`, `.warning()`, `.error()` calls
  - `dispose()` cleanup

### Version Tracking

- Monitor `pubspec.yaml` version field
- Track breaking changes in CHANGELOG.md
- Document API changes affecting integrations
- Update migration guides for version transitions

## Maintenance Workflow

When maintaining AE files:

1. **Code Change Detection**:

   - Monitor library source for API changes
   - Check for new configuration options
   - Identify new features or capabilities
   - Track deprecations

2. **Documentation Sync**:

   - Update `ae_context.md` for new domain knowledge
   - Update integration patterns in `ae_install.md`
   - Add new uninstall steps in `ae_uninstall.md`
   - Document version changes in `ae_update.md`
   - Add new usage patterns in `ae_use.md`

3. **Validation**:

   - Verify examples compile
   - Test integration patterns
   - Ensure reversibility maintained
   - Check file LOC (keep <500 where possible)

4. **Consistency Check**:
   - Cross-reference between files
   - Ensure terminology consistency
   - Maintain pattern coherence
   - Verify checklist completeness

This enables agents to autonomously analyze and maintain AE files for xsoulspace_logger, facilitating seamless library management.
