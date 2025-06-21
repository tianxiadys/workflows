FROM debian:12.9

ARG VERSION=2.1.10
ARG ARCH=x86_64
ARG SYSTEM=linux64
ARG ZIPNAME=logtail-${SYSTEM}
ARG ZIPURL=https://logtail-release-cn-hangzhou.oss-cn-hangzhou.aliyuncs.com/${SYSTEM}/${VERSION}/${ARCH}/${ZIPNAME}.tar.gz
ARG EXENAME=ilogtail_${VERSION}
ENV REGION=cn-hangzhou
ENV USERID=userid

RUN <<EOF
apt update
apt install -y curl
apt clean
curl -L -o /root/download.tgz ${ZIPURL}
tar -zxvf /root/download.tgz -C /root
mkdir /etc/ilogtail
mkdir /usr/local/ilogtail
mv /root/${ZIPNAME}/conf/* /etc/ilogtail
mv /root/${ZIPNAME}/bin/* /usr/local/ilogtail
mv /root/${ZIPNAME}/resources/* /usr/local/ilogtail
ln -fs /usr/local/ilogtail/${EXENAME} /bin/ilogtail
rm -rf /root
EOF

COPY "entry.sh" "/bin/entry.sh"
CMD ["/bin/sh", "/bin/entry.sh"]
