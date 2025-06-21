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
rm -f /root/download.tgz
EOF

CMD [
  "/root/${ZIPNAME}/bin/${EXENAME}",
  "-https_ca_cert",
  "/root/${ZIPNAME}/resources/ca-bundle.crt",
  "-ilogtail_config",
  "/root/${ZIPNAME}/conf/${REGION}/ilogtail_config.json",
  "-ilogtail_daemon_flag",
  "false",
  "-ilogtail_user_defined_id_env_name",
  "${USERID}"
]
