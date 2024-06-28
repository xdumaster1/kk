# syntax=docker/dockerfile:1
ARG TARGETPLATFORM
ARG PYTHON_VERSION="3.12"

#####################################################################
# Build Wheels
#####################################################################
FROM python:${PYTHON_VERSION}-slim as wheels-builder
ARG TARGETPLATFORM

# Install build-time packages
RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        libffi-dev \
        cargo \
        git \
        curl

WORKDIR /wheels
COPY requirements_all.txt .

# Build python wheels for all dependencies
RUN set -x \
    && pip install --upgrade pip \
    && pip install build maturin \
    && pip wheel -r requirements_all.txt

#####################################################################
# Final Image
#####################################################################
FROM python:${PYTHON_VERSION}-slim AS final-build
WORKDIR /app

# Required to persist build arg
ARG MASS_VERSION
ARG TARGETPLATFORM

RUN set -x \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        ca-certificates \
        curl \
        git \
        wget \
        tzdata \
        libsox-fmt-all \
        libsox3 \
        sox \
        cifs-utils \
        libnfs-utils \
        libjemalloc2 \
    # Install snapcast server 0.27 from bookworm backports
    && sh -c 'echo "deb http://deb.debian.org/debian bookworm-backports main" >> /etc/apt/sources.list' \
    && apt-get update \
    && apt-get install -y --no-install-recommends -t bookworm-backports snapserver \
    # Install ffmpeg 6 from multimedia repo
    && sh -c 'echo "Types: deb\nURIs: https://www.deb-multimedia.org\nSuites: stable\nComponents: main non-free\nSigned-By: /etc/apt/trusted.gpg.d/deb-multimedia-keyring.gpg" >> /etc/apt/sources.list.d/deb-multimedia.sources' \
    && sh -c 'echo "Package: *\nPin: origin www.deb-multimedia.org\nPin-Priority: 1" >> /etc/apt/preferences.d/99deb-multimedia' \
    && cd /tmp && curl -sLO https://www.deb-multimedia.org/pool/main/d/deb-multimedia-keyring/deb-multimedia-keyring_2016.8.1_all.deb \
    && apt install -y /tmp/deb-multimedia-keyring_2016.8.1_all.deb \
    && apt-get update \
    && apt install -y -t 'o=Unofficial Multimedia Packages' ffmpeg \
    # Cleanup
    && rm -rf /tmp/* \
    && rm -rf /var/lib/apt/lists/*

# Copy widevine client files to container
RUN mkdir -p /usr/local/bin/widevine_cdm
COPY widevine_cdm/* /usr/local/bin/widevine_cdm/

# Install all built wheels
COPY --from=wheels-builder /wheels /tmp/wheels
RUN set -x \
    && pip install --upgrade pip \
    && pip install --no-cache-dir /tmp/wheels/*.whl

# Install Music Assistant from published wheel
ENV MASS_VERSION=2.1.1b15
RUN pip install \
        --no-cache-dir \
        musicxxdu[server]==${MASS_VERSION} \
    && python3 -m compileall music_assistant

# Enable jemalloc
RUN export LD_PRELOAD=$(find /usr/lib/ -name *libjemalloc.so.2) && echo "export LD_PRELOAD=$LD_PRELOAD" >> /etc/environment
ENV MALLOC_CONF="background_thread:true,metadata_thp:auto,dirty_decay_ms:20000,muzzy_decay_ms:20000"

# Set some labels
LABEL \
    org.opencontainers.image.title="Music Assistant" \
    org.opencontainers.image.description="Music Assistant Server/Core" \
    org.opencontainers.image.source="https://github.com/music-assistant/server" \
    org.opencontainers.image.authors="The Music Assistant Team" \
    org.opencontainers.image.documentation="https://github.com/orgs/music-assistant/discussions" \
    org.opencontainers.image.licenses="Apache License 2.0" \
    io.hass.version="${MASS_VERSION}" \
    io.hass.type="addon" \
    io.hass.name="Music Assistant" \
    io.hass.description="Music Assistant Server/Core" \
    io.hass.platform="${TARGETPLATFORM}" \
    io.hass.type="addon"

VOLUME [ "/data" ]

ENTRYPOINT ["mass", "--config", "/data"]
