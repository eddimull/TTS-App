---
name: Do not modify shared models or scopes
description: Never alter raw Eloquent models/scopes that the web application also uses — reuse existing services instead
type: feedback
---

Do not modify raw Eloquent models (e.g., Bookings scopes like `scopeUnpaid`, `scopePaid`) or the Band model methods when adding mobile API features. These are shared with the web application and other services.

**Why:** The web application depends on the same models and scopes. Changing them for mobile API needs risks breaking the web side. The user explicitly corrected this approach.

**How to apply:** When the mobile API needs behavior that differs from what models provide (e.g., adding filters), add the logic in `FinanceServices` (or the relevant service class) or in the mobile controller itself. Reuse existing service classes rather than duplicating or modifying model-level logic.
