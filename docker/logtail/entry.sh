#!/bin/sh

#https://logtail-release-cn-hangzhou.oss-cn-hangzhou.aliyuncs.com/linux64/2.1.10/x86_64/logtail-linux64.tar.gz
##下载最新版本转发器
#curl http://logtail-release-cn-beijing.oss-cn-beijing-internal.aliyuncs.com/linux64/0.16.62/logtail-linux64.tar.gz -o /tmp/log.tgz
##解压文件到临时目录
#tar -zxf /tmp/log.tgz -C /tmp
##现在停止进程
#systemctl stop ilogtaild
##创建程序目录
#mkdir /usr/local/ilogtail
#mkdir /etc/ilogtail
##复制程序文件
#cp -a /tmp/logtail-linux64/bin/. /usr/local/ilogtail
#cp -a /tmp/logtail-linux64/conf/cn-beijing-vpc/ilogtail_config.json /usr/local/ilogtail
#cp -a /tmp/logtail-linux64/resources/ca-bundle.crt /usr/local/ilogtail
##设置文件权限
#chown root:root /usr/local/ilogtail -R
##创建符号连接
#ln -fs /usr/local/ilogtail/ilogtail_0.16.62 /usr/local/ilogtail/ilogtail
#ln -fs /usr/local/ilogtail/ilogtaild /etc/init.d/ilogtaild
#ln -fs /srv/config/log.txt /etc/ilogtail/user_defined_id
##设置自启动
#systemctl enable ilogtaild
##现在启动程序
#systemctl start ilogtaild
##清理临时文件
#rm -fr /tmp/logtail-linux64
#rm -f /tmp/log.tgz
