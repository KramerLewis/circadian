# Security Policy

## Reporting a vulnerability

Please report security issues privately through GitHub's
[private vulnerability reporting](https://github.com/KramerLewis/circadian/security/advisories/new)
rather than in a public issue. You can expect an acknowledgement within a week.

## Scope

SunClock makes no network requests and stores data only on the device. Relevant
reports include anything that could expose a user's location or alarms to other apps
or parties, or cause alarms to silently fail.

The GitHub Actions workflows are also in scope (for example, anything that could
leak repository secrets used for App Store uploads).
