FROM ubuntu:22.04 AS build
RUN apt-get update && apt-get install -y build-essential ca-certificates git pkg-config
ARG ZEROTIER_BRANCH=feature/ingress-node
WORKDIR /src
RUN git clone --branch "${ZEROTIER_BRANCH}" --depth 1 \
    https://github.com/AlterMundi/ZeroTierOne.git .
RUN make -j"$(nproc)" ZT_SSO_SUPPORTED=0 MINIUPNPC_IS_NEW_ENOUGH=0

FROM ubuntu:22.04
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=build /src/zerotier-one /usr/local/sbin/zerotier-one
COPY --from=build /src/zerotier-cli /usr/local/bin/zerotier-cli
VOLUME /var/lib/zerotier-one
EXPOSE 9993/udp 9993/tcp
