# Security Policy

## Supported versions

Security fixes land on the latest minor of the current major only. See the support matrix in the [README](./README.md) for which React Native and Nitro versions that covers.

## Reporting a vulnerability

Please **do not** open a public issue.

Report privately through [GitHub Security Advisories](https://github.com/MGasowski/rn-glass-reactions/security/advisories/new). If that is unavailable to you, email the address on the maintainer's GitHub profile.

Include the library version, React Native and Nitro versions, the platform and OS version, and enough detail to reproduce.

You can expect an acknowledgement within a week. If the report is accepted, we will agree a disclosure timeline with you before publishing a fix.

## Scope

This library renders a native view and reports which reaction a user selected. It performs no network access, writes nothing to disk, and stores no reaction data — persistence and scoring belong to the consuming app.

The most plausible security-relevant surface is therefore:

- Content passed through `emoji`, `symbol`, or `accessibilityLabel` reaching a native text or symbol rendering path.
- The host's window-level touch interception on Android and the overlay window on iOS, which sit above application UI.

Reports about consuming apps storing reaction data insecurely are out of scope here.
