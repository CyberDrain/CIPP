# ── CIPP-NG Dev Container ──────────────────────────────────
# Builds PS modules, frontend, and layers onto Craft release image.
# Each compiled module is built in its own stage for independent caching.
# With BuildKit, independent stages build in parallel automatically.

# Default the .NET base images to the GHCR mirror (CyberDrain/Containers) so
# builds survive an mcr.microsoft.com / Azure Container Registry outage.
# Override with --build-arg DOTNET_REGISTRY=mcr.microsoft.com to pull upstream.
ARG DOTNET_REGISTRY=ghcr.io/cyberdrain

# Craft runtime base for the final image — a distroless Azure Linux runtime
# (craft:dev = Debug, craft:latest = Release; both non-root, no shell).
ARG CRAFT_BASE=ghcr.io/cyberdrain/craft:latest

# ── Base: PowerShell SDK + ModuleBuilder (cached, rarely changes) ──
FROM ${DOTNET_REGISTRY}/dotnet/sdk:8.0-bookworm-slim AS ps-base
COPY build/Metadata/1.5.7 /usr/local/share/powershell/Modules/Metadata/1.5.7
COPY build/Configuration/1.6.0 /usr/local/share/powershell/Modules/Configuration/1.6.0
COPY build/ModuleBuilder/3.1.8 /usr/local/share/powershell/Modules/ModuleBuilder/3.1.8
WORKDIR /build
COPY build/tools/build-single-module.ps1 /build/build-single-module.ps1

# ── Per-module build stages ──
# Each stage only invalidates when its own module source changes.

FROM ps-base AS build-cippcore
COPY backend/Modules/CIPPCore /src/CIPPCore
RUN pwsh -File /build/build-single-module.ps1 -Module CIPPCore

FROM ps-base AS build-cipphttp
COPY backend/Modules/CIPPHTTP /src/CIPPHTTP
RUN pwsh -File /build/build-single-module.ps1 -Module CIPPHTTP

FROM ps-base AS build-cippstandards
COPY backend/Modules/CIPPStandards /src/CIPPStandards
RUN pwsh -File /build/build-single-module.ps1 -Module CIPPStandards

FROM ps-base AS build-cippdb
COPY backend/Modules/CIPPDB /src/CIPPDB
RUN pwsh -File /build/build-single-module.ps1 -Module CIPPDB

FROM ps-base AS build-cippalerts
COPY backend/Modules/CIPPAlerts /src/CIPPAlerts
RUN pwsh -File /build/build-single-module.ps1 -Module CIPPAlerts

FROM ps-base AS build-cippactivitytriggers
COPY backend/Modules/CIPPActivityTriggers /src/CIPPActivityTriggers
RUN pwsh -File /build/build-single-module.ps1 -Module CIPPActivityTriggers

FROM ps-base AS build-cippextensions
COPY backend/Modules/CippExtensions /src/CippExtensions
RUN pwsh -File /build/build-single-module.ps1 -Module CippExtensions

FROM ps-base AS build-cipptests
COPY backend/Modules/CIPPTests /src/CIPPTests
RUN pwsh -File /build/build-single-module.ps1 -Module CIPPTests -KeepPublic

# ── CIPPSharp build ──
# Always rebuilt from source against the runtime's framework — the committed
# binary in backend/Shared/CIPPSharp/bin/ is a developer convenience for local
# `func start` and is overwritten in the final image. This guarantees the DLL
# in the container matches the SDK pinned by this stage, regardless of which
# SDK the last committer happened to have installed.
FROM ${DOTNET_REGISTRY}/dotnet/sdk:8.0-bookworm-slim AS build-cippsharp
WORKDIR /src
COPY backend/Shared/CIPPSharp/CIPPSharp.csproj ./
RUN dotnet restore CIPPSharp.csproj
COPY backend/Shared/CIPPSharp/ ./
RUN dotnet build CIPPSharp.csproj -c Release --no-restore -o /out && \
    test -f /out/CIPPSharp.dll

# ── Function parameter cache ──
# Pregenerated help cache served by Invoke-ListFunctionParameters, extracted
# from the CIPPCore source via AST parse. Without it the endpoint runs
# Get-Help across every CIPPCore public function per request (minutes ->
# gateway timeout).
FROM ps-base AS build-functionparams
COPY build/tools/build-function-parameters.ps1 /build/build-function-parameters.ps1
COPY backend/Modules/CIPPCore /gen/CIPPCore
RUN pwsh -File /build/build-function-parameters.ps1 -ModulePath /gen/CIPPCore -OutputPath /gen/function-parameters.json

# ── Published docs page list ──
# Config/DocsPublishedPages.txt tells the SearchDocs MCP tool which pages are actually live on
# docs.cipp.app, so a result never carries a URL that 404s. A page can sit in docs/ unpublished,
# and only llms.txt knows which, so this is refreshed from the live site at build time — an image
# then reflects what was published when it was built rather than whenever someone last ran the
# script by hand. The committed copy is the fallback and is what ships if the fetch fails.
#
# ARG BUILD_DATE is here purely to bust the layer cache: the inputs are otherwise just the script
# and the committed list, so without it Docker would reuse a cached layer and ship a stale list
# from an earlier build despite this stage existing. It sits in its own tiny stage, so unlike the
# version args near the frontend build it invalidates nothing expensive.
FROM ps-base AS build-docspages
COPY build/tools/Update-DocsPublishedPages.ps1 /build/Update-DocsPublishedPages.ps1
COPY backend/Config/DocsPublishedPages.txt /gen/DocsPublishedPages.txt
ARG BUILD_DATE=unknown
RUN echo "Refreshing published docs list (build ${BUILD_DATE})" && \
    pwsh -File /build/Update-DocsPublishedPages.ps1 -OutputPath /gen/DocsPublishedPages.txt -AllowFallback

# ── OpenAPI spec ──
# Config/openapi.json, derived from the CIPPHTTP entrypoint sources via AST parse.
# Not documentation-only: Get-CippMcpSpec loads it at runtime and Get-CippMcpToolList
# projects every read-only operation in it into an MCP tool, so a stale spec ships a
# stale tool contract. Regenerated here so it can never drift from the source.
FROM ps-base AS build-openapi
COPY build/tools/build-openapi.ps1 /build/build-openapi.ps1
# CIPPCore and friends are needed, not just CIPPHTTP: entrypoints hand the request
# body to shared helpers and the generator follows those calls to recover the fields
# they read. Without them the image would ship a thinner spec than the committed one.
COPY backend/Modules/CIPPHTTP       /gen/Modules/CIPPHTTP
COPY backend/Modules/CIPPCore       /gen/Modules/CIPPCore
COPY backend/Modules/CIPPStandards  /gen/Modules/CIPPStandards
COPY backend/Modules/CippExtensions /gen/Modules/CippExtensions
COPY backend/Config/openapi-overrides /gen/openapi-overrides
# Vendored Graph CSDL. Endpoints that fetch a Graph collection and return it untouched
# name no field in their own source, so without this their responses ship undescribed.
COPY backend/Config/graph-metadata /gen/graph-metadata
# The UI's simpleColumns declarations are the only static description of a list
# response; without them every list endpoint documents an untyped object.
COPY frontend/src /gen/frontend/src
RUN pwsh -File /build/build-openapi.ps1 \
    -EntrypointPath "/gen/Modules/CIPPHTTP/Public/Entrypoints/HTTP Functions" \
    -ModulesPath /gen/Modules \
    -FrontendPath /gen/frontend/src \
    -OverridePath /gen/openapi-overrides \
    -GraphMetadataPath /gen/graph-metadata \
    -OutputPath /gen/openapi.json

# ── Frontend build ──
FROM node:22-slim AS frontend-deps
WORKDIR /build
COPY frontend/package.json frontend/yarn.lock frontend/.npmrc frontend/.yarnrc ./
RUN --mount=type=cache,target=/usr/local/share/.cache/yarn \
    yarn install --frozen-lockfile --network-timeout 100000

FROM frontend-deps AS frontend-build
COPY frontend/ ./

# Build performance: disable telemetry
ENV NEXT_TELEMETRY_DISABLED=1

# Cache .next/cache across builds so Next.js can reuse compiled chunks.
# IMPORTANT: nothing version-specific (APP_VERSION/COMMIT_SHA) appears before
# this layer on purpose. Those args change on every commit, so injecting them
# here would invalidate the expensive `yarn build` even on backend-only pushes.
RUN --mount=type=cache,target=/build/.next/cache \
    yarn build

# The OpenAPI spec, served as a static asset at /openapi.json. Injected after the
# compile for the same reason as version.json below: it is generated from backend
# sources, so copying it in before `yarn build` would invalidate the compile on every
# backend change. Landing it in out/ before the precompress step below gets it Brotli
# q11 + gzip 9 - the runtime compressor only manages ~460KB on this file against
# ~130KB for plain gzip -9, so precompressing is worth several hundred KB per fetch.
COPY --from=build-openapi /gen/openapi.json out/openapi.json

# Inject build metadata into version.json AFTER the compile. The frontend reads
# this only at runtime via fetch('/version.json') — it doesn't need to be present
# during `yarn build`. Writing it into the exported out/ dir (so precompress
# emits matching .br/.gz below) keeps the compile cached across commits that only
# touch backend code. NEXT_PUBLIC_* vars were unused by the app and removed.
ARG APP_VERSION=0.0.0-local
ARG COMMIT_SHA=unknown
ARG IMAGE_TAG=dev
ARG BUILD_DATE=unknown
RUN echo "{\"version\":\"${APP_VERSION}\",\"commit\":\"${COMMIT_SHA}\",\"tag\":\"${IMAGE_TAG}\",\"buildDate\":\"${BUILD_DATE}\"}" > out/version.json

# Pre-compress static assets (Brotli q11 + gzip 9) alongside originals, so CRAFT serves
# precompressed files with zero per-request compression CPU. Node 22 zlib has Brotli built in.
# Toggle with --build-arg PRECOMPRESS=0 to produce an uncompressed control image.
ARG PRECOMPRESS=1
COPY build/tools/precompress.mjs /build/precompress.mjs
RUN if [ "$PRECOMPRESS" = "1" ]; then node /build/precompress.mjs ./out; else echo "[precompress] skipped (PRECOMPRESS=$PRECOMPRESS)"; fi

# ── Final image — dev base ──
FROM ${CRAFT_BASE}
WORKDIR /app

ARG APP_VERSION=0.0.0-dev
ARG COMMIT_SHA=unknown
ARG IMAGE_TAG=dev
ARG BUILD_DATE=unknown
ENV APP_VERSION=$APP_VERSION
ENV COMMIT_SHA=$COMMIT_SHA
ENV IMAGE_TAG=$IMAGE_TAG
ENV BUILD_DATE=$BUILD_DATE

# Pre-built modules — rarely change, cached layers (ordered first)
COPY backend/Modules/AzBobbyTables  /app/API/Modules/AzBobbyTables/
COPY backend/Modules/DNSHealth      /app/API/Modules/DNSHealth/
COPY backend/Modules/HuduAPI        /app/API/Modules/HuduAPI/
COPY backend/Modules/PassPushPosh   /app/API/Modules/PassPushPosh/

# Backend support directories
# --chown: the app user owns Config/ so CRAFT can write Config/function-permissions.json
# at startup (non-root distroless) and CIPP modules read it back from the same path.
COPY --chown=app:app backend/Config /app/API/Config/
COPY backend/Shared                 /app/API/Shared/
# Overwrite the committed CIPPSharp.dll (and its OfficeIMO PDF dependencies) with freshly built ones
# targeting the runtime framework. Must run AFTER the Shared/ copy so they aren't clobbered. The
# OfficeIMO DLLs must sit beside CIPPSharp.dll - CIPPSharp is loaded via RequiredAssemblies and .NET
# resolves its dependencies from the same directory (there is no deps.json).
COPY --from=build-cippsharp /out/CIPPSharp.dll     /app/API/Shared/CIPPSharp/bin/CIPPSharp.dll
COPY --from=build-cippsharp /out/OfficeIMO.Pdf.dll  /app/API/Shared/CIPPSharp/bin/OfficeIMO.Pdf.dll
COPY --from=build-cippsharp /out/OfficeIMO.Core.dll /app/API/Shared/CIPPSharp/bin/OfficeIMO.Core.dll
# emoji-fallback.ttf (monochrome fallback font) and the twemoji/ colour-emoji PNG set the renderer places
# inline are committed assets, not build outputs, so they ship via the `COPY backend/Shared` above and need
# no rebuild here.
COPY backend/AddChocoApp            /app/API/AddChocoApp/
COPY backend/AddMSPApp              /app/API/AddMSPApp/
COPY backend/ExecMaintenanceScripts /app/API/ExecMaintenanceScripts/
# GitBook source for docs.cipp.app, indexed at runtime by the SearchDocs MCP tool
# (Get-CippDocsIndex reads $env:CIPPRootPath/Docs). Markdown only — Dockerfile.dockerignore
# keeps the .gitbook image tree out. ~2 MB, and it version-matches the docs to this build.
COPY docs                           /app/API/Docs/

# Compiled modules — ordered by change frequency (least → most)
COPY --from=build-cippextensions       /src/CippExtensions/       /app/API/Modules/CippExtensions/
COPY --from=build-cippactivitytriggers /src/CIPPActivityTriggers/ /app/API/Modules/CIPPActivityTriggers/
COPY --from=build-cippdb               /src/CIPPDB/               /app/API/Modules/CIPPDB/
COPY --from=build-cippalerts           /src/CIPPAlerts/           /app/API/Modules/CIPPAlerts/
COPY --from=build-cipptests            /src/CIPPTests/            /app/API/Modules/CIPPTests/
COPY --from=build-cippstandards        /src/CIPPStandards/        /app/API/Modules/CIPPStandards/
COPY --from=build-cipphttp             /src/CIPPHTTP/             /app/API/Modules/CIPPHTTP/
COPY --from=build-cippcore             /src/CIPPCore/             /app/API/Modules/CIPPCore/
# generated from CIPPCore, changes whenever it does — keep adjacent in the layer order
COPY --chown=app:app --from=build-functionparams /gen/function-parameters.json /app/API/Config/function-parameters.json
# generated from CIPPHTTP; overwrites the committed copy so the image always ships
# a spec that matches the entrypoints beside it
COPY --chown=app:app --from=build-openapi /gen/openapi.json /app/API/Config/openapi.json
# refreshed from docs.cipp.app at build time; overwrites the committed fallback so the
# SearchDocs tool links against what was actually published when this image was built
COPY --chown=app:app --from=build-docspages /gen/DocsPublishedPages.txt /app/API/Config/DocsPublishedPages.txt

# Frontend — changes most frequently, placed last
COPY --from=frontend-build /build/out/ /app/Frontend/

# Memory tuning 3GB
ENV DOTNET_GCHeapHardLimit=0xC0000000

# Runtime environment — CIPP-NG-specific only. .NET GC tuning, mimalloc preload
# and PowerShell telemetry opt-outs are inherited from the CRAFT base image.
ENV WEBSITES_ENABLE_APP_SERVICE_STORAGE=true
ENV CIPPNG=true

# Runtime config
COPY build/config/appsettings.Development.json /app/appsettings.Production.json
