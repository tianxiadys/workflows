FROM alpine:3.21.3

ARG VERSION=1.37.0
ARG ZIPNAME=aria2-${VERSION}
ARG ZIPURL=https://github.com/aria2/aria2/releases/download/release-${VERSION}/${ZIPNAME}.tar.gz

RUN <<EOF
apk add --no-cache curl gcc g++ make musl-dev
curl -L -o /root/download.tgz ${ZIPURL}
tar -xzvf /root/download.tgz -C /root
mkdir /root/build
cd /root/build
sh /root/${ZIPNAME}/configure
make
ls
rm -rf /root
EOF

CMD ["/bin/aria2c", "--conf-path=/app/aria2c.ini"]
