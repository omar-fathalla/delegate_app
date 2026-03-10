# Delegate App - Agentic Workflows & Guidelines

This document outlines the agentic workflows, skills, and coding standards used in the **Delegate App** Flutter project. It is designed to be read by both human developers and AI agents (like Antigravity) to understand the project architecture, available tools, and best practices.

## 🤖 Available AI Agents & Workflows

This project utilizes AI agents to automate common tasks, ensure consistency, and accelerate development.

### 🛠️ Workflows (Slash Commands)

Workflows are pre-defined, multi-step processes that agents can execute. You can trigger these by asking the agent to run the corresponding slash command.

*   **/create-feature**: Generates a complete feature structure following our **Clean Architecture** conventions (Domain, Data, Presentation layers).
*   **/add-page**: Scaffolds a new UI page, complete with Material 3 design, `go_router` setup, and RTL (Arabic) localization support.
*   **/create-bloc**: Creates a new BLoC (Business Logic Component) with strictly typed Events and States, leveraging the `Equatable` package.
*   **/create-usecase**: Generates a Use Case class (Clean Architecture) with necessary parameters, repository injection, and `Either` return types for error handling.
*   **/create-firestore-model**: Creates a Dart data model annotated for Firestore compatibility, ensuring camelCase keys match the backend schema.
*   **/setup-di**: Registers new dependencies (BLoCs, UseCases, Repositories, DataSources) within the `GetIt` service locator framework.
*   **/run-codegen**: Executes `build_runner` to generate code for `freezed`, `json_serializable`, and `injectable`.
*   **/handle-errors**: Implements robust error handling by creating `Failure` classes and mapping Firebase exceptions to user-friendly Arabic messages.
*   **/add-firebase-service**: Sets up a new Firebase service (Auth, Storage, Functions, etc.) adhering to security-first and serverless best practices.
*   **/secure-app**: Implements production-grade security measures like biometric authentication, Firebase App Check, and SSL pinning.
*   **/attendance-checkin**: Implements or modifies the attendance tracking feature, incorporating geo-fencing, anti-fraud measures, and secure server timestamps.
*   **/verify-project**: Runs comprehensive checks including static analysis, schema validation, and anti-fraud compliance verification.
*   **/write-tests**: Scaffolds Unit and Widget tests using `mocktail` and `bloc_test`, adhering to Clean Architecture testing patterns.
*   **/build-ios**: Automates the iOS build process, including signing, exporting the IPA, and auto-incrementing the build number.
*   **/deploy-app**: Triggers the CI/CD pipeline (GitHub Actions/Codemagic) to build, sign, and deploy the app to production/testing tracks.

### 🧠 Skills

Skills are specialized capabilities the agent can use to gather information or interact with external systems.

*   **notebook_reader**: Fetches and extracts clean text content from web URLs. This is particularly useful for ingesting documentation or articles into tools like [NotebookLM](https://notebooklm.google.com/) for deeper analysis and context building.

---

## 🏗️ Project Architecture & Standards

### 1. Clean Architecture
We strictly follow Clean Architecture principles to separate concerns and maintain a testable, scalable codebase.
*   **Domain**: Contains enterprise and application business rules (Entities, Use Cases, Repository Interfaces). Must not depend on any outer layers.
*   **Data**: Implements data access (Models, Repositories implementations, Data Sources - Remote/Local).
*   **Presentation**: Handles UI and state management (Pages, Widgets, BLoCs/Cubits).

### 2. State Management
*   **BLoC / Cubit**: We use the `flutter_bloc` package for managing complex state. State should be predictable, immutable, and easily testable.

### 3. Dependency Injection
*   **GetIt & Injectable**: We rely on `get_it` and the `injectable` code generator for managing dependencies across the application.

### 4. Code Generation
*   We heavily utilize code generation to reduce boilerplate. This includes:
    *   `freezed` for immutable data classes and unions.
    *   `json_serializable` for JSON parsing.
    *   `injectable` for DI registration.
    *   *Always run `/run-codegen` after modifying models or DI setups.*

### 5. Localization (L10N)
*   **Primary Language:** Arabic (RTL).
*   **Secondary Language:** English (LTR).
*   All user-facing strings must be localized using `.arb` files and the `flutter_localizations` package.

### 6. Error Handling
*   We use the **Either pattern** from `fpdart` or `dartz` to explicitly handle success and failure cases at the Domain layer.
*   Errors from external sources (like Firebase) must be mapped to specific `Failure` classes before reaching the Presentation layer.

### 7. Security & Anti-Fraud
*   Security is a priority. Features dealing with sensitive data or core operations (like attendance) must incorporate necessary safeguards including server-side validation, App Check, and relevant native protections.

---

## 💡 Integrating with IDEs & AI

*(Insights derived from the project's NotebookLM resources)*

To maximize productivity, we encourage leveraging modern IDE features and AI assistants:

*   **IntelliJ IDEA Ultimate / Android Studio:** Recommended for deep Flutter/Dart integration.
*   **JetBrains AI (Junie):** Utilize integrated AI assistants for code completion, context understanding, and generating boilerplate. AI tools represent the "next evolution" in developer productivity, moving beyond simple autocomplete to semantic code understanding.
*   **Context is Key:** When interacting with AI agents (like Antigravity), provide as much context as possible. Point the agent to relevant files, workflows, or architectural guidelines to get the best results.

