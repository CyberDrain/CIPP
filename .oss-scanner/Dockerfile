# Anthropic OSS Scanner image (github.com/anthropics/oss-scanner).
# Not the shipped image: build/Dockerfile ends on distroless Craft, which the scanner can't add its tools to.
# This one keeps the source at /src with every dependency installed, so tests run with no network.
FROM node:22-bookworm-slim AS node

FROM mcr.microsoft.com/dotnet/sdk:8.0-bookworm-slim
ENV DEBIAN_FRONTEND=noninteractive \
    NEXT_TELEMETRY_DISABLED=1 \
    DOTNET_CLI_TELEMETRY_OPTOUT=1 \
    POWERSHELL_TELEMETRY_OPTOUT=1
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates curl git \
    && rm -rf /var/lib/apt/lists/*
COPY --from=node /usr/local /usr/local
COPY --from=node /opt /opt

# Pester 5 for the backend suite (the sdk image already ships pwsh).
RUN pwsh -NoProfile -Command "Set-PSRepository PSGallery -InstallationPolicy Trusted; Install-Module Pester -MinimumVersion 5.0 -Force -Scope AllUsers -SkipPublisherCheck"

# scanner contract: the checkout lives at /src
COPY . /src
WORKDIR /src

RUN cd frontend && yarn install --frozen-lockfile --network-timeout 100000
RUN dotnet build backend/Shared/CIPPSharp/CIPPSharp.csproj -c Release -o /tmp/cippsharp

# Smoke-run the suites; failures warn rather than fail the build. The full Pester suite takes ~12 min,
# too much of the scanner's 45-min build budget, so only one folder runs here.
RUN cd frontend && (timeout 900 yarn test:unit || echo "WARNING: vitest reported failures")
RUN timeout 600 pwsh -NoProfile -File backend/Tests/Invoke-CippTests.ps1 -Path backend/Tests/Security -NoExitCode \
    || echo "WARNING: Pester did not finish cleanly"
