FROM alpine:3.21.3

ARG VERSION=3.3.5
ARG ZIPNAME=shadowsocks-libev-${VERSION}
ARG ZIPURL=https://github.com/shadowsocks/shadowsocks-libev/releases/download/v${VERSION}/${ZIPNAME}.tar.gz

RUN <<EOF
apk add --no-cache cmake curl c-ares-dev libev-dev libsodium-dev linux-headers mbedtls-dev pcre-dev
mkdir /root/src
curl -L -o /root/download.tgz ${ZIPURL}
tar -xzvf /root/download.tgz -C /root
mkdir /root/build
cmake -S /root/${ZIPNAME} -B /root/build
cmake --build /root/build
EOF
