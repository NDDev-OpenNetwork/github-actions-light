# Security

Report vulnerabilities privately through GitHub's security advisory interface.
Do not open a public issue for a suspected credential leak, token handling
defect, or a path that would run untrusted workflow code on private hardware.

This repository must not contain host addresses, organization names, runner
tokens, or deploy credentials. A helper that logs `RUNNER_TOKEN` or writes it
to disk is a security defect.

Public workflows in this repository run on GitHub-hosted runners. A self-hosted
label here is a security defect.
