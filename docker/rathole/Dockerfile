FROM debian:12.9

ARG VERSION=v0.5.0
ARG ARCH=x86_64-unknown-linux-gnu
ARG ZIPURL=https://github.com/rapiz1/rathole/releases/download/${VERSION}/rathole-${ARCH}.zip

RUN <<EOF
apt update
apt install -y curl unzip
apt clean
curl -L -o /root/download.zip ${ZIPURL}
unzip /root/download.zip -d /root
mv /root/rathole /bin/rathole
mkdir /app
EOF

CMD ["/bin/rathole", "/app/rathole.toml"]
