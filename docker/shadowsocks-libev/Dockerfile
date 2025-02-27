FROM alpine:3.21.3

ARG GITURL=https://github.com/shadowsocks/shadowsocks-libev.git

RUN <<EOF
apk add --no-cache cmake c-ares-dev git libev-dev libsodium-dev linux-headers mbedtls-dev pcre-dev
#克隆
git clone ${GITURL} /root/src
#编译
mkdir /root/build
cmake -S /root/src -B /root/build
cmake --build /root/build
EOF
