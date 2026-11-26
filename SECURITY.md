# Security

## Report a security problem

Please do not open a public issue for a security problem. Report it in private instead: open the
**Security** tab of this repo and click **Report a vulnerability**
([direct link](../../security/advisories/new)). Only the maintainer can read the report.

Say what you did, what happened, and which Luksfer version you use (Luksfer › About Luksfer).

## What counts

Anything that breaks one of the promises in [CONTRIBUTING.md](CONTRIBUTING.md), for example:

- Luksfer deletes, overwrites or moves a file without a way to undo it or a question first.
- A network drive password leaves the macOS Keychain: in the settings file, a log, a URL or a
  process argument.
- A file name, a folder or terminal output makes Luksfer run a command, or read or change the
  clipboard.
- Luksfer makes a network connection that the user did not ask for.
- Listing a cloud folder starts a download.

## Versions

Only the latest release gets fixes. Update to it before you report.
