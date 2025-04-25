FROM debian:12.9

ARG VERSION=v0.5.0
ARG ARCH=x86_64-unknown-linux-gnu
ARG ZIPNAME=rathole-${ARCH}
ARG ZIPURL=https://github.com/rapiz1/rathole/releases/download/${VERSION}/${ZIPNAME}.zip

RUN <<EOF
apt update
apt install -y curl unzip
apt clean
curl -L -o /root/download.zip ${ZIPURL}
unzip /root/download.zip rathole -d /bin
rm -rf /root
EOF

CMD ["/bin/rathole", "/app/rathole.toml"]
