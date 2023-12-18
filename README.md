# `schemamap`: Tenant Onboarding Simplified 🚀
Leverage the power of your Postgres schema for streamlined multi-tenant SaaS onboarding.

Brought to you by [schemamap.io](https://schemamap.io).

## Features 🌟
- **Database Migrations**: Easily manage and version your database schemas.
- **Permission Management**: Robust handling for application Postgres DB roles ensuring secure data access.
- **SSH Port-Forwarding**: Enhance developer experience with local Postgres connection forwarding.

## SDKs Supported 🛠️
Integrate `schemamap` seamlessly with our language-specific SDKs. Currently, we support:
- **Clojure**:
  [![Clojars Project](https://img.shields.io/clojars/v/io.schemamap/schemamap-clj.svg)](https://clojars.org/io.schemamap/schemamap-clj)
  Dive into the documentation [here](./clojure/README.md).

_Watch out for more languages coming soon! Have a request? [Open an issue](https://github.com/schemamap/schemamap/issues/new)._

## Developing

### First-time setup
1. Install direnv and hook into your shell: https://direnv.net/#basic-installation
2. Install the Nix package manager: https://github.com/DeterminateSystems/nix-installer#readme
3. Run `direnv allow` (will prompt you to install https://devenv.sh/getting-started/#2-install-cachix, from Step 2.)
4. To make sure the LFS files (db dumps) are present, run: `git lfs pull`

### Day-to-day operations
1. `devenv up` to bring up the development environment services
2. `ci-test` to run the integration test suite locally
3. `devenv info` to see what packages and scripts are available

## Feedback and Contributions 👥
We'd love to hear from you! Whether it's a bug report, feature request, or general feedback - feel free to [raise an issue](https://github.com/schemamap/schemamap/issues/new).

## License 📜
Copyright © 2023 Schemamap.io Kft.

This project is distributed under the MIT License. For more details, refer to the [LICENSE](./LICENSE) file.
