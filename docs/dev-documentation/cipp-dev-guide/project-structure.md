# Project Structure

CIPP is a mono-repository with three top-level directories: `frontend/` for the web interface, `backend/` for the API, and `build/` for Docker and dev tooling.

## Frontend

### Root files

| Item                | Description                                                       |
| ------------------- | ----------------------------------------------------------------- |
| `src/`              | Application source code, where most frontend development happens. |
| `public/`           | Static assets served as-is (images, favicons).                    |
| `tests/`            | Vitest unit tests and Storybook interaction tests.                |
| `package.json`      | Dependencies and scripts.                                         |
| `yarn.lock`         | Locked dependency versions for repeatable installs.               |
| `next.config.js`    | Next.js configuration.                                            |
| `eslint.config.mjs` | ESLint flat config (extends `eslint-config-next` + Prettier).     |
| `vitest.config.mjs` | Vitest test runner configuration.                                 |

### The `src/` directory

| Item          | Description                                                                        |
| ------------- | ---------------------------------------------------------------------------------- |
| `pages/`      | Next.js pages router. Each file or directory maps to a URL route.                  |
| `components/` | Reusable React components, with CIPP-specific components under `components/Cipp*`. |
| `sections/`   | Page-specific sections and layouts used by pages.                                  |
| `layouts/`    | Application layout wrappers (sidebar, header, navigation).                         |
| `api/`        | API call layer (`ApiCall.jsx`), wrapping React Query around axios.                 |
| `store/`      | Redux Toolkit slices for cross-cutting application state.                          |
| `contexts/`   | React context providers.                                                           |
| `hooks/`      | Custom React hooks.                                                                |
| `theme/`      | MUI theme configuration (palette, typography, component overrides).                |
| `styles/`     | Global and utility styles.                                                         |
| `data/`       | Static data files (for example, `countryList.json`).                               |
| `icons/`      | Custom icon components.                                                            |
| `libs/`       | Third-party library wrappers and configuration.                                    |
| `utils/`      | Shared utility functions.                                                          |

## Backend

Source code lives under `backend/Modules/`, split into purpose-specific modules:

| Module                 | What it holds                                                       |
| ---------------------- | ------------------------------------------------------------------- |
| `CIPPCore`             | Shared helpers, Graph/Exchange wrappers, auth, and the HTTP router. |
| `CIPPHTTP`             | Every `Invoke-*` HTTP endpoint handler, organised by area.          |
| `CIPPStandards`        | Classic tenant standards (`Invoke-CIPPStandard*.ps1`), bugfixes only. |
| `CIPPBaselines`        | Baselines engine, prepare hooks and executors. New standards go here. |
| `CIPPTests`            | In-app compliance tests (`Invoke-CippTest*.ps1`).                   |
| `CIPPAlerts`           | Alert definitions (`Get-CIPPAlert*.ps1`).                           |
| `CIPPDB`               | Reporting database cache refresh jobs (`Set-CIPPDBCache*.ps1`).     |
| `CIPPActivityTriggers` | Durable activity, queue, and timer entrypoints.                     |
| `CippExtensions`       | Third-party integrations (Hudu, NinjaOne, and others).              |

Tests live under `backend/Tests/`, organised by area (Alerts, Baselines, CippTests, Endpoint, Standards, Static, Private, Security, Build and others).

## Build

The `build/` directory contains Docker Compose files, Dockerfiles, the vendored ModuleBuilder, and the dev tooling scripts that compile backend modules and watch for changes. See [setting-up-for-local-development.md](setting-up-for-local-development.md "mention") for how to use them.
