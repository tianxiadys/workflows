FROM alpine:3.21.3

ARG VERSION=3.3.5
ARG ZIPURL=https://github.com/shadowsocks/shadowsocks-libev/releases/download/v${VERSION}/shadowsocks-libev-${VERSION}.tar.gz

RUN <<EOF
apk add --no-cache cmake curl c-ares-dev libev-dev libsodium-dev linux-headers mbedtls-dev pcre-dev
mkdir /root/src
mkdir /root/build
curl -L -o /root/download.tgz ${ZIPURL}
tar -xzvf /root/download.tgz -C /root/src
cmake -S /root/src -B /root/build
cmake --build /root/build
EOF
