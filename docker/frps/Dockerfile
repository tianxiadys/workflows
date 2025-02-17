FROM alpine:3.21.3

ARG VERSION=0.61.1
ARG ARCH=linux_amd64
ARG ZIPNAME=frp_${VERSION}_${ARCH}
ARG ZIPURL=https://github.com/fatedier/frp/releases/download/v${VERSION}/${ZIPNAME}.tar.gz

RUN <<EOF
apk add --no-cache curl
curl -L -o /root/download.tgz ${ZIPURL}
tar -xzf /root/download.tgz -C /root
mv /root/${ZIPNAME} /root/frp
mkdir /etc/frp
EOF

CMD ["/root/frp/frps", "-c", "/etc/frp/frps.toml"]
