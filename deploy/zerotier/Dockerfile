FROM ubuntu:22.04 AS build

RUN apt-get update && apt-get install -y \
    build-essential \
    ca-certificates \
    curl \
    git \
    pkg-config \
    libssl-dev \
  && rm -rf /var/lib/apt/lists/*

# Rust toolchain required for zeroidc (ZeroTier >= 1.16)
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
ENV PATH="/root/.cargo/bin:${PATH}"

ARG ZEROTIER_REPO=https://github.com/AlterMundi/ZeroTierOne.git
ARG ZEROTIER_BRANCH=feature/ingress-node

WORKDIR /src
RUN git clone --branch "${ZEROTIER_BRANCH}" --depth 1 "${ZEROTIER_REPO}" .

RUN make -j"$(nproc)" ZT_NONFREE=1

FROM ubuntu:22.04

RUN apt-get update && apt-get install -y \
    ca-certificates \
  && rm -rf /var/lib/apt/lists/*

COPY --from=build /src/zerotier-one /usr/local/sbin/zerotier-one
COPY --from=build /src/zerotier-cli /usr/local/bin/zerotier-cli
COPY --from=build /src/zerotier-idtool /usr/local/bin/zerotier-idtool
COPY controller-entrypoint.sh /usr/local/bin/controller-entrypoint.sh
RUN chmod +x /usr/local/bin/controller-entrypoint.sh

VOLUME /var/lib/zerotier-one

EXPOSE 9993/udp
EXPOSE 9993/tcp

ENTRYPOINT ["/usr/local/bin/controller-entrypoint.sh"]
