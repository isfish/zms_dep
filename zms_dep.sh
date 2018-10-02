#! /bin/bash

PATH=/bin:/sbin:/usr/bin:/usr/sbin:/usr/local/bin:/usr/local/sbin:~/bin
export PATH

#Check root

if [ $(id -u) != "0" ]; then
	echo "Error: You must run the script as root!"
	exit 1
fi

# yum install dependency
yum install -y https://centos7.iuscommunity.org/ius-release.rpm
yum makecache
yum install -y python36u python36u-devel python36u-pip gcc* git2u  crontabs openssl openssl-devel zlib zlib-devel pcre pcre-devel gd gd-devel
if [ -s /usr/local/nginx ]; then
	echo "nginx installed"
else
# add nginx user
useradd -d /www -s /sbin/nologin www
cd /usr/src
wget -O nginx.tar.gz http://nginx.org/download/nginx-1.14.0.tar.gz 
tar -zxf nginx.tar.gz && cd nginx-1.14.0
./configure --user=www --group=www --prefix=/usr/local/nginx --with-http_stub_status_module --with-http_ssl_module --with-http_v2_module --with-http_gzip_static_module --with-http_sub_module --with-stream --with-stream_ssl_module
make && make install
cd ..
ngx_loc="/usr/local/nginx"
mv ${ngx_loc}/conf/nginx.conf ${ngx_loc}/conf/nginx_bak
cat>${ngx_loc}/conf/nginx.conf<<EOF
	user  www;
worker_processes  1;

#error_log  logs/error.log;
#error_log  logs/error.log  notice;
#error_log  logs/error.log  info;

pid        logs/nginx.pid;


events {
    worker_connections  1024;
}

http {
    include            mime.types;
    default_type       application/octet-stream;
    server_tokens      off;
    charset            UTF-8;

    sendfile           on;
    tcp_nopush         on;
    tcp_nodelay        on;

    keepalive_timeout  60;

    #... ...#

    gzip               on;
    gzip_vary          on;

    gzip_comp_level    6;
    gzip_buffers       16 8k;

    gzip_min_length    1000;
    gzip_proxied       any;
    gzip_disable       "msie6";

    gzip_http_version  1.0;

    gzip_types         text/plain text/css application/json application/x-javascript text/xml application/xml application/xml+rss text/javascript application/javascript image/svg+xml;

    #... ...#

    include            vhosts/*.conf;
}
EOF
mkdir ${ngx_loc}/conf/vhosts
${ngx_loc}/sbin/nginx -t
if [ $? -eq 0 ]; then
	echo "nginx has been installed successfully! You can go to next step!"
else
	echo "sorry, nginx has been failed to install! This work will be stoped!"
	exit 1
fi
cat>/lib/systemd/system/nginx.service<<EOF
[Unit]
Description=Nginx Process Manager
After=network.target
 
[Service]
Type=forking
ExecStart=/usr/local/nginx/sbin/nginx -c /usr/local/nginx/conf/nginx.conf
ExecReload=/usr/local/nginx/sbin/nginx -s reload
ExecStop=/usr/local/nginx/sbin/nginx -s quit
PrivateTmp=false
 
[Install]
WantedBy=multi-user.target
EOF
systemctl enable nginx.service
systemctl start nginx.service
fi
git clone https://github.com/Neilpang/acme.sh.git acme && cd acme
read -p "Please enter the home for acme.sh:" ac_home
read -p "The home for configuration of acme:" cfg_home
read -p "Well, enter the certshome for store issued certs:" cts_home
cd acme
if [[ "${ac_home}"="" && "${cfg_home}"="" && "${cts_home}"="" ]]; then
	./acme.sh --install --home /usr/local/acme --cert-home /usr/local/acme/certs --config-home /usr/local/acme/config
else
	./acme.sh --install --home ${ac_home} --cert-home ${cts_home} --config-home ${cfg_home}
fi
source ~/.bashrc ~/.bash_profile
clear 
read -p "Enter the domain you want to issue a certificate:" domain
if [[ -s /usr/local/acme/certs/${domain} ]]; then
	echo "The domain you input has a certificate, it'll will not be issued!"
	echo "If the certificate has been expired, please renew it manually after this process!!"
else
	read -p "Please enter your dns server and api in a special form:" api_id api_key dns_server
	export DP_Id="${api_id}" DP_Key="${api_key}"
	/usr/local/acme/acme.sh --issue --dns ${dns_server} -d ${domain}
fi
mkdir -p /www/ssl/${domain}
/usr/local/acme/acme.sh --install-cert -d ${domain} --fullchain-file /www/ssl/${domain}/pubkey.pem --key-file /www/ssl/${domain}/privkey.pem --reloadcmd "service nginx force-reload"

cat>/usr/local/nginx/conf/vhosts/${domain}.conf<<EOF
server{
        listen          80;
        server_name     ${domain};
        rewrite         '^(.*)$ https://${server_name}$1' permanent;
}

server{
        listen          443 ssl;
        server_name     ${domain};
        location / {
                proxy_pass              http://127.0.0.1:8964;
                proxy_set_header        Host            '$host';
                proxy_set_header        X-Real-IP       '$remote_addr';
                proxy_set_header        X-Forwarded-For '$proxy_add_x_forwarded_for';
        }
        access_log     logs/${domain}.log;
        add_header      Strict-Transport-Security "max-age=15552000;";
        ssl             on;
        ssl_certificate /www/ssl/${domain}/pubkey.pem;
        ssl_certificate_key /www/ssl/${domain}/privkey.pem;
        ssl_ciphers     ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:ECDHE-RSA-DES-CBC3-SHA:ECDHE-ECDSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:DES-CBC3-SHA:HIGH:SEED:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!RSAPSK:!aDH:!aECDH:!EDH-DSS-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA:!SRP;
        ssl_prefer_server_ciphers on;
        ssl_protocols           TLSv1 TLSv1.1 TLSv1.2 TLSv1.3;
        ssl_session_cache       shared:SSL:50m;
        ssl_session_timeout     1d;


}
EOF
mkdir -p /www/site/${domain} && cd /www/site/${domain}
read -p "Please enter which mirror you want to proxyed:" site 
git clone https://github.com/aploium/zmirror.git ${site}
cd ${site}
python3.6 -m pip install virtualenv
python3.6 -m pip install setuptools==21
virtualenv -p python3.6 venv
./venv/bin/pip install -i https://pypi.douban.com/simple gunicorn gevent
./venv/bin/pip install -i https://pypi.douban.com/simple -r requirements.txt
cp more_configs/config_google_and_zhwikipedia.py config.py
sed -ne 's/my_host_name ='127.0.0.1'/my_host_name = "${domain}"/g' config.py
sed -ne 's#my_host_scheme='http://'#my_host_scheme='https://'#g' config.py 
# 启动 zmirror 服务器
./venv/bin/gunicorn --daemon --capture-output --log-file zmirror.log --access-logfile zmirror-access.log --bind 127.0.0.1:8964 --workers 2 --worker-connections 100 wsgi:application

service nginx restart

