# syntax=docker/dockerfile:1
# Build context is the REPO ROOT (needed for the DebridCore path dependency):
#   docker build -f Packages/SeretServer/Dockerfile -t seret-server:latest .
# For the NAS (amd64) from an Apple-Silicon Mac, add: --platform linux/amd64  (emulated, slow) —
# or build this same Dockerfile natively ON the DS920+ (amd64, fast). See README.

# ---------- build ----------
FROM swift:6.0-jammy AS build
WORKDIR /src
# Copy only what the build needs — never the host .build (wrong arch + huge).
COPY Packages/DebridCore/Package.swift    Packages/DebridCore/Package.swift
COPY Packages/DebridCore/Sources          Packages/DebridCore/Sources
COPY Packages/DebridCore/Tests            Packages/DebridCore/Tests
COPY Packages/SeretServer/Package.swift   Packages/SeretServer/Package.swift
COPY Packages/SeretServer/Package.resolved Packages/SeretServer/Package.resolved
COPY Packages/SeretServer/Sources         Packages/SeretServer/Sources
COPY Packages/SeretServer/Tests           Packages/SeretServer/Tests
WORKDIR /src/Packages/SeretServer
RUN swift build -c release
RUN cp "$(swift build -c release --show-bin-path)/SeretServer" /usr/local/bin/SeretServer

# ---------- runtime ----------
FROM swift:6.0-jammy-slim
RUN apt-get update && apt-get install -y --no-install-recommends \
      ffmpeg intel-media-va-driver-non-free libva2 libva-drm2 vainfo \
      ca-certificates tzdata \
    && rm -rf /var/lib/apt/lists/*
# iHD is the QuickSync driver for the DS920+'s J4125 (Gemini Lake).
ENV LIBVA_DRIVER_NAME=iHD
COPY --from=build /usr/local/bin/SeretServer /usr/local/bin/SeretServer
EXPOSE 8080
ENTRYPOINT ["SeretServer"]
