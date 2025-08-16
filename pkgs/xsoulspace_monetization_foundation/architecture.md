# XSoulspace Monetization Architecture

This document outlines the modular architecture of the XSoulspace monetization system. The system is designed to be extensible, maintainable, and easy to test by separating abstract interfaces from concrete implementations.

## Core Principles

1.  **Interface/Implementation Separation**: The core principle is the separation of abstract interfaces from concrete service provider implementations. This allows the application to depend on a consistent API contract, regardless of the underlying monetization or ad service.
2.  **Modularity**: Each monetization provider (e.g., Google/Apple IAP, RuStore, Yandex Ads) is encapsulated within its own independent package. This isolation makes it easy to add, remove, or update providers without affecting the rest of the application.
3.  **Dependency Inversion**: The high-level foundation packages depend on abstractions (interfaces), not on concrete implementations. The specific provider implementation is injected at runtime, inverting the traditional dependency flow.

## Package Structure

The monetization system is split into three main categories of packages:

### 1. Interface Packages

These packages define the abstract contracts (interfaces) and data models for a specific monetization type. They have minimal dependencies.

- `xsoulspace_monetization_interface`: Defines the `PurchaseProvider` interface and shared data models for In-App Purchases (IAP).
- `xsoulspace_monetization_ads_interface`: Defines the `AdProvider` interface for advertisements.

### 2. Provider Packages

Each provider package implements an interface from an interface package. It contains all the platform-specific code and dependencies for a single service.

- `xsoulspace_monetization_google_apple`: Implements `PurchaseProvider` using the `in_app_purchase` package for the App Store and Google Play.
- `xsoulspace_monetization_rustore`: Implements `PurchaseProvider` using the `flutter_rustore_billing` package.
- `xsoulspace_monetization_huawei`: Implements `PurchaseProvider` using the `huawei_iap` package.
- `xsoulspace_monetization_ads_yandex`: Implements `AdProvider` using the `yandex_mobileads` package.

### 3. Foundation Packages

These packages provide a high-level, convenient API for the application to use. They consume the interface packages and are injected with a concrete provider implementation at runtime.

- `xsoulspace_monetization_foundation`: Contains high-level business logic (`PurchaseManager`) that consumes the `PurchaseProvider` interface.
- `xsoulspace_monetization_ads_foundation`: Contains `AdManager` which consumes the `AdProvider` interface.

## Architectural Diagram

The following diagram illustrates the dependency flow between the packages:

```mermaid
graph TD
    subgraph App
        A[Application Code]
    end

    subgraph Foundation
        F_IAP[monetization_foundation<br>(PurchaseManager)]
        F_ADS[monetization_ads_foundation<br>(AdManager)]
    end

    subgraph Interfaces
        I_IAP[monetization_interface<br>(PurchaseProvider)]
        I_ADS[monetization_ads_interface<br>(AdProvider)]
    end

    subgraph Providers
        P_IAP_GA[monetization_google_apple]
        P_IAP_RS[monetization_rustore]
        P_IAP_HW[monetization_huawei]
        P_ADS_YA[monetization_ads_yandex]
    end

    A --> F_IAP
    A --> F_ADS

    F_IAP --> I_IAP
    F_ADS --> I_ADS

    P_IAP_GA -- Implements --> I_IAP
    P_IAP_RS -- Implements --> I_IAP
    P_IAP_HW -- Implements --> I_IAP

    P_ADS_YA -- Implements --> I_ADS

    style F_IAP fill:#cde4ff,stroke:#6699ff,stroke-width:2px
    style F_ADS fill:#cde4ff,stroke:#6699ff,stroke-width:2px
    style I_IAP fill:#d5e8d4,stroke:#82b366,stroke-width:2px
    style I_ADS fill:#d5e8d4,stroke:#82b366,stroke-width:2px
    style P_IAP_GA fill:#fff2cc,stroke:#d6b656,stroke-width:2px
    style P_IAP_RS fill:#fff2cc,stroke:#d6b656,stroke-width:2px
    style P_IAP_HW fill:#fff2cc,stroke:#d6b656,stroke-width:2px
    style P_ADS_YA fill:#fff2cc,stroke:#d6b656,stroke-width:2px
```
