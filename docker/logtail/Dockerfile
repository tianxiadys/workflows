FROM debian:12.9

ARG VERSION=2.1.10
ARG SYSTEM=linux64
ARG ARCH=x86_64
ARG EXENAME=ilogtail_${VERSION}
ARG ZIPNAME=logtail-${SYSTEM}
ARG ZIPURL=https://logtail-release-cn-hangzhou.oss-cn-hangzhou.aliyuncs.com/${SYSTEM}/${VERSION}/${ARCH}/${ZIPNAME}.tar.gz
ENV REGION=cn-hangzhou
ENV USERID=userid

RUN <<EOF
apt update
apt install -y curl
apt clean
curl -L -o /root/download.tgz ${ZIPURL}
tar -zxvf /root/download.tgz -C /root
mv /root/${ZIPNAME} /app
ln -fs /app/bin/${EXENAME} /app/bin/ilogtail
rm -f /root/download.tgz
EOF

COPY "entry.sh" "/app/entry.sh"
CMD ["/bin/sh", "/app/entry.sh"]
