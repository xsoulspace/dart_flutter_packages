<!--
version: 1.0.0
library: xsoulspace_logger
repository: https://github.com/xsoulspace/xsoulspace_packages
license: MIT
-->

# Agentic Executables (AE) Context for xsoulspace_logger

## Definitions

- **Agentic Executable (AE)**: A library or package treated as an executable program, managed by AI agents for installation, configuration, usage, and uninstallation.
- **Installation**: Process of adding the AE to a project via CLI or package manager.
- **Configuration**: Adjusting AE settings to fit project requirements.
- **Integration**: Incorporating AE code and logic into the existing codebase.
- **Usage**: Applying AE capabilities in the project as needed.
- **Uninstallation**: Removing the AE and reversing integrations safely.

## Library Overview

**xsoulspace_logger** is a pure Dart logging library providing:

- Configurable console and file output
- Multiple log levels (VERBOSE, DEBUG, INFO, WARNING, ERROR)
- Structured logging with data maps
- Log rotation (time and size-based)
- Configuration presets for common scenarios
- Singleton pattern for easy access
- Async file writing with buffering

## Core Principles

- **Agent Empowerment**: Equip AI agents with meta-rules to autonomously maintain, install, configure, integrate, use, and uninstall AEs based on project needs.
- **Modularity**: Structure AE instructions in clear, reusable steps: Installation → Configuration → Integration → Usage → Uninstallation.
- **Contextual Awareness**: Ensure AE documentation provides sufficient domain knowledge for agents to understand integration points without manual intervention.
- **Reversibility**: Design uninstallation to cleanly remove all traces of the AE, restoring the original state.
- **Validation**: Include checks for installation, configuration, and usage to ensure reliability and allow for corrections.
- **Documentation Focus**: Prioritize concise, agent-readable instructions over verbose human-oriented docs.

## Domain Knowledge

### Logger Lifecycle

1. **Creation**: Create Logger singleton with LoggerConfig
2. **Initialization**: Call `await logger.init()` for async setup
3. **Usage**: Log throughout application lifecycle
4. **Disposal**: Flush file buffer on exit (for file output)

**Important:** Explicit `await logger.init()` is required after Logger instantiation. This ensures proper async initialization and prevents race conditions, even for console-only configurations.

### Key Components

- **Logger**: Singleton class for logging operations
  - Methods: `verbose()`, `debug()`, `info()`, `warning()`, `error()`
  - Singleton access via `Logger()` factory
  - Initialization via `Logger(config)`
- **LoggerConfig**: Configuration with presets
  - `debug()` - Development mode (VERBOSE, console + file)
  - `production()` - Production mode (INFO, file only)
  - `verbose()` - Maximum logging (VERBOSE, large files)
  - `silent()` - Minimal logging (ERROR only)
  - `consoleOnly()` - Testing mode (no files)
- **LogLevel**: Enum for severity levels
  - Order: VERBOSE < DEBUG < INFO < WARNING < ERROR
  - Filtering based on minimum level
- **FileWriter**: Handles async file writes (internal)
  - Automatic buffering
  - Log rotation support
  - Cleanup on dispose

### Integration Points

1. **Application Entry**: Initialize logger in `main()` or app setup, always call `await logger.init()`
2. **Service Layer**: Log API calls, database operations, business logic
3. **State Management**: Log state changes, user actions
4. **UI Layer**: Log critical errors, user interactions
5. **Error Boundaries**: Catch and log unhandled exceptions
6. **Lifecycle Management**: Dispose logger on app exit/background

**Note:** The init() call must be awaited before using any logging methods to ensure file writers and other async components are properly initialized.

### Configuration Parameters

- `minLevel`: Minimum log level to output (filters lower levels)
- `enableConsole`: Toggle console output (stdout/stderr)
- `enableFile`: Toggle file output
- `logDirectory`: Custom path for log files (default: temp directory)
- `enableRotation`: Enable log file rotation
- `maxFileSizeMB`: Max file size before rotation
- `maxFileCount`: Max number of log files to retain

## Working Principles

1. **Maintain the library executables** (meta instructions)

   - 1.1 Basic terms & domain knowledge - `ae_context.md` (this file)
   - 1.2 Bootstrap file to maintain executables - `ae_bootstrap.md`
   - GOAL: Create and maintain AE file structure
   - USER: Library maintainer

2. **One-time operations** (install/uninstall/update)

   - 2.1 Installation, Configuration, Integration - `ae_install.md`
   - 2.2 Uninstallation - `ae_uninstall.md`
   - 2.3 Update/Migration - `ae_update.md`
   - GOAL: Manage library lifecycle in projects
   - USER: Developer using the library

3. **Frequent usage** (ongoing development)
   - 3.1 Usage patterns, best practices, anti-patterns - `ae_use.md`
   - GOAL: Provide guidance for daily library usage
   - USER: Developer using the library

## Logger-Specific Guidelines

### Installation Context

- Add dependency to pubspec.yaml
- Initialize Logger singleton early in app lifecycle
- **Always call `await logger.init()` after Logger creation**
- Choose appropriate configuration preset or create custom config
- Integrate logging at key application points
- Set up cleanup for file output

### Configuration Context

- Environment-based config selection (development vs production)
- Log level filtering strategy
- File output configuration (path, rotation)
- Performance considerations (console disable in production)

### Integration Context

- Service layer: Wrap external calls with logging
- State management: Log state transitions
- Error handling: Log errors with full context (error + stack)
- Performance monitoring: Log operation durations
- Request/response logging: Log API interactions

### Usage Context

- Use consistent category naming conventions
- Structure data with `data` parameter
- Apply appropriate log levels
- Include error object and stack trace for exceptions
- Avoid logging sensitive data (passwords, tokens, PII)
- Throttle high-frequency logs

### Uninstallation Context

- Remove all Logger instantiations
- Remove logging method calls
- Remove import statements
- Remove configuration
- Remove dependency from pubspec.yaml
- Clean up log files (optional)
- Verify no orphaned references

### Update Context

- Backup current state
- Review changelog for breaking changes
- Update dependency version
- Migrate configuration if API changed
- Update method calls if signatures changed
- Validate logging functionality
- Monitor for issues

## Best Practices

1. **Initialization**: Set up logger before any other operations and **always call `await logger.init()`**
2. **Presets**: Use built-in configs for common scenarios
3. **Categories**: Use consistent, hierarchical category names
4. **Structured Data**: Prefer data maps over string interpolation
5. **Error Context**: Always include error and stackTrace for exceptions
6. **Cleanup**: Call dispose() for graceful shutdown with file logging
7. **Level Discipline**: Use appropriate levels (debug for dev, info for prod)
8. **Performance**: Disable console in production, enable rotation

## Anti-Patterns

1. **Over-logging**: Logging in tight loops or excessive detail
2. **Sensitive Data**: Logging passwords, tokens, PII without redaction
3. **Wrong Levels**: Using error for info, or info for debug
4. **Missing Context**: Logging errors without error object or stack trace
5. **Multiple Instances**: Creating multiple Logger instances (defeats singleton)
6. **Expensive Operations**: Computing expensive data for filtered logs
7. **No Cleanup**: Not disposing logger with file output
8. **Inconsistent Categories**: Using different naming conventions

This context enables agents to understand xsoulspace_logger's architecture and integration patterns for autonomous AE management.
