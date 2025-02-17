FROM alpine:3.21.3

ENV VERSION 0.61.1
ENV ARCH linux_amd64
ENV ZIPNAME frp_${VERSION}_${ARCH}
ENV ZIPURL https://github.com/fatedier/frp/releases/download/v${VERSION}/${ZIPNAME}.tar.gz

RUN apk add --no-cache curl
RUN curl -o /root/download.tgz ${ZIPURL}
RUN tar -xzf /root/download.tgz -C /root
