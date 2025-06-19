# Refactoring Plan: `git_oauth_provider` & `universal_storage_sync`

## 1. Objective

The primary goal of this refactoring is to establish a clean, scalable, and maintainable architecture by enforcing a strict separation of concerns between authentication, storage, and application/UI logic. By decoupling these components, we will improve modularity, testability, and the overall developer experience.

## 2. Guiding Principles

- **Single Responsibility Principle (SRP)**: Each class and package should have one, and only one, reason to change. A storage provider should not handle authentication. An authentication library should not contain UI logic.
- **Dependency Inversion Principle (DIP)**: High-level modules should not depend on low-level modules. Both should depend on abstractions. This will be achieved by using abstract delegates and clearly defined interfaces.
- **Composition over Inheritance**: Functionality will be composed by combining independent packages (`provider` + `utils` + `app`) rather than creating monolithic classes that do everything.

## 3. Refactoring Plan by Package

---

### **Phase 1: `universal_storage_sync` Package**

The focus here is to strip the `GitHubApiStorageProvider` down to its essential function: performing file I/O against the GitHub API.

#### **Task 1.1: Remove All Authentication Flow Logic**

- **Why**: The storage provider's responsibility is data access, not user authentication. It should be a "dumb" client that operates with a credential it is given. Forcing it to know _how_ to get that credential (via OAuth) creates tight coupling and makes it impossible to use with other authentication methods.
- **What to Change**:
  - Remove the methods `_performOAuthFlow`, `_performWebOAuthFlow`, and `_performDeviceOAuthFlow` from `GitHubApiStorageProvider`.
  - Refactor the `initWithConfig` method to remove the "OAuth path." The provider must be initialized with a pre-acquired access token. It should throw an error if a token is not provided.
  - Delete any `OAuth` related configuration fields from `GitHubApiConfig`.

#### **Task 1.2: Remove High-Level Repository Management Logic**

- **Why**: Repository selection, creation, and naming strategies are application-level concerns, not storage concerns. This logic is often tied to a specific user interface and workflow, and embedding it in a generic storage provider makes the system rigid and violates SRP.
- **What to Change**:
  - Remove the `_handleRepositorySelection` method entirely from `GitHubApiStorageProvider`.
  - The provider's configuration (`GitHubApiConfig`) must be updated to require the exact repository `owner` and `name` to be provided upfront. The provider should no longer be responsible for discovering or creating them.

#### **Task 1.3: Expose Low-Level Repository Primitives**

- **Why**: While the provider should not contain high-level _logic_ for repository management, it is the correct place to expose the low-level _capabilities_. This empowers an external utility or the application to build user-facing features.
- **What to Change**:
  - Add new public methods to `GitHubApiStorageProvider`, such as:
    - `Future<List<Repository>> listRepositories()`
    - `Future<Repository> createRepository(CreateRepository details)`
  - These methods will use the provider's configured authentication token to perform the underlying API calls.

---

### **Phase 2: `git_oauth_provider` Package**

This package will become the single source of truth for handling Git provider authentication.

#### **Task 2.1: Implement the `OAuthFlowDelegate` Pattern**

- **Why**: The user-facing steps of an OAuth flow are platform-specific (e.g., opening a browser tab vs. handling a deep link). To keep the core package platform-agnostic, this UI-dependent logic must be handled by a delegate, a concept familiar to Flutter developers.
- **What to Change**:
  - Create a new abstract class: `abstract class OAuthFlowDelegate`.
  - This class should define the contract for platform-specific operations. For example, it might have a method like `Future<String> getAuthorizationCode(Uri authorizationUrl, Uri redirectUrl)` which the implementer is responsible for fulfilling.
  - The main `GitHubOauthProvider` class will accept an instance of this `OAuthFlowDelegate` via its constructor (Dependency Injection). It will call the delegate's methods at the appropriate point in the OAuth flow.

---

### **Phase 3: `universal_storage_sync_utils` Package (New)**

This new package will house the reusable, high-level logic that connects the UI to the storage backend.

#### **Task 3.1: Create the Utility Package**

- **Why**: A dedicated package is needed for the application-level logic that was removed from the storage provider. This promotes code reuse across different applications that might use `universal_storage_sync`.
- **What to Change**:
  - Initialize a new Dart package named `universal_storage_sync_utils`. It will depend on `universal_storage_sync`.

#### **Task 3.2: Implement Repository Management Helpers**

- **Why**: To provide developers with a clean, high-level API for common application workflows, abstracting away the multi-step process of listing, choosing, and creating repositories.
- **What to Change**:
  - Create helper functions or classes in this new package. For example, a function like `Future<Repository> selectOrCreateRepository(GitHubApiStorageProvider provider, RepositorySelectionUI uiBridge)` could orchestrate the entire flow.
  - This function would use the primitives exposed in Task 1.3 (`listRepositories`, `createRepository`) to interact with the provider. It would use the `uiBridge` (an interface or set of callbacks) to request input from the actual application UI.

---

### **Phase 4: Update Documentation, Examples, and Tests**

- **Why**: Code is only as good as its documentation and tests. A refactor of this magnitude is incomplete and potentially harmful if supporting materials are not updated. They must reflect the new, decoupled architecture to prevent confusion and ensure correctness.
- **What to Change**:
  - **Documentation**:
    - Update all public API documentation (`///`) in all affected packages to accurately describe the new roles, parameters, and responsibilities.
    - Modify `README.md` files to explain the new architectural pattern: how `git_oauth_provider` provides a token, `universal_storage_sync` uses it, and `universal_storage_sync_utils` helps orchestrate common workflows.
  - **Examples**:
    - Rewrite all examples from the ground up. The primary example should showcase the intended end-to-end flow:
      1.  Using `git_oauth_provider` with a `FlowDelegate` to get a token.
      2.  Passing that token to initialize `GitHubApiStorageProvider`.
      3.  Using a helper from `universal_storage_sync_utils` to select a repository.
      4.  Performing a file operation.
  - **Tests**:
    - Update all relevant unit and integration tests to align with the new class responsibilities.
    - Delete tests for logic that has been removed (e.g., testing the OAuth flow _inside_ the storage provider).
    - Write new tests for the added features (e.g., `listRepositories` in the provider, helpers in the `utils` package).
    - Ensure that tests for `GitHubApiStorageProvider` now mock the authentication by providing a fake token, not by mocking the OAuth flow itself.

## 5. Expected Outcome

Upon completion, the ecosystem will be composed of three distinct and decoupled modules with comprehensive and up-to-date documentation, examples, and tests.

1.  **`git_oauth_provider`**: Handles authentication and produces a token.
2.  **`universal_storage_sync`**: A low-level library for file operations on a pre-configured backend.
3.  **`universal_storage_sync_utils`**: High-level, reusable helpers for common application workflows.

This new architecture will be significantly more flexible, testable, and easier for developers to understand and extend.
