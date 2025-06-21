FROM alpine:3.21.3

ARG VERSION=v1.22.0
ARG ARCH=x86_64-unknown-linux-musl
ARG ZIPNAME=shadowsocks-${VERSION}.${ARCH}
ARG ZIPURL=https://github.com/shadowsocks/shadowsocks-rust/releases/download/${VERSION}/${ZIPNAME}.tar.xz

RUN <<EOF
apk add --no-cache curl
curl -L -o /root/download.txz ${ZIPURL}
tar -Jxvf /root/download.txz -C /bin
rm -rf /root
EOF
