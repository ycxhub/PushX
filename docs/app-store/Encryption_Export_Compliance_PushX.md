# Encryption Export Compliance — PushX

**App name:** PushX  
**Bundle identifier:** com.pushx.app  
**Developer / legal entity:** Chaitanya Yalakaturu (Apple Developer account holder)  
**Document date:** March 23, 2026  

---

## 1. Purpose

This document supports **App Store Connect** export compliance and describes how the PushX iOS application uses cryptography, if at all.

---

## 2. Summary (self-classification)

PushX **does not implement proprietary or non-standard encryption** and **does not use standard encryption algorithms outside of, or in addition to, encryption provided by Apple’s operating system** for purposes that would require separate export documentation under typical U.S. BIS / EAR mass-market software rules.

The application’s functionality (on-device camera processing, pose estimation, local data storage) **does not rely on custom cryptographic modules** controlled by the developer.

---

## 3. Encryption and cryptographic use in PushX

| Area | Use of encryption / crypto |
|------|----------------------------|
| **Networking** | The app does not perform custom TLS/SSL or implement its own encrypted protocols. Any incidental use of system-provided secure transport (e.g. if future updates use HTTPS via Apple frameworks) would use **encryption within Apple’s operating system** only. |
| **On-device processing** | Computer vision and machine learning (e.g. Apple frameworks, bundled on-device models) operate on local data. This is **not** classified here as separate “non-exempt” encryption for export purposes. |
| **Local storage** | Data may be stored using Apple-provided APIs (e.g. SwiftData / file system). The developer does **not** ship a separate encryption layer for export classification beyond what the OS provides. |
| **Proprietary algorithms** | **None.** |
| **Non-standard encryption** | **None** implemented by the developer. |

---

## 4. Info.plist declaration

The app is configured with:

- **`ITSAppUsesNonExemptEncryption`** = **NO** (`false`)

This indicates the app **does not** use encryption that is **non-exempt** under Apple’s upload / compliance flow for the standard consumer app case described above.

---

## 5. Certification

To the best of my knowledge, the statements in this document accurately describe PushX as of the date below.

**Name:** Chaitanya Yalakaturu  
**Role:** Developer / Account Holder  
**Date:** March 23, 2026  

---

## 6. Note

Regulatory classification can depend on future features. If PushX later adds custom cryptography, proprietary algorithms, or non-exempt encryption, this document and the App Store encryption answers must be updated before distribution.
