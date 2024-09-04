#!/bin/bash
export LANG=en_US.UTF-8
red='\033[0;31m'
yellow='\033[0;33m'
bblue='\033[0;34m'
plain='\033[0m'
blue(){ echo -e "\033[36m\033[01m$1\033[0m";}
red(){ echo -e "\033[31m\033[01m$1\033[0m";}
green(){ echo -e "\033[32m\033[01m$1\033[0m";}
yellow(){ echo -e "\033[33m\033[01m$1\033[0m";}
white(){ echo -e "\033[37m\033[01m$1\033[0m";}
readp(){ read -p "$(yellow "$1")" $2;}
[[ $EUID -ne 0 ]] && yellow "请以root模式运行脚本" && exit
#[[ -e /etc/hosts ]] && grep -qE '^ *172.65.251.78 gitlab.com' /etc/hosts || echo -e '\n172.65.251.78 gitlab.com' >> /etc/hosts
yellow " 请稍等3秒……正在扫描vps类型及参数中……"
if [[ -f /etc/redhat-release ]]; then
release="Centos"
elif cat /etc/issue | grep -q -E -i "debian"; then
release="Debian"
elif cat /etc/issue | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /etc/issue | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
elif cat /proc/version | grep -q -E -i "debian"; then
release="Debian"
elif cat /proc/version | grep -q -E -i "ubuntu"; then
release="Ubuntu"
elif cat /proc/version | grep -q -E -i "centos|red hat|redhat"; then
release="Centos"
else
red "不支持你当前系统，请选择使用Ubuntu,Debian,Centos系统。" && exit
fi
vsid=$(grep -i version_id /etc/os-release | cut -d \" -f2 | cut -d . -f1 2>/dev/null)
op=$(lsb_release -sd || cat /etc/redhat-release || cat /etc/os-release | grep -i pretty_name | cut -d \" -f2)
version=$(uname -r | cut -d "-" -f1)
main=$(uname -r | cut -d "." -f1)
minor=$(uname -r | cut -d "." -f2)
vi=$(systemd-detect-virt)
name=$(hostname)
case $(uname -m) in
aarch64) cpu=arm64;;
x86_64) cpu=amd64;;
*) red "目前脚本不支持$(uname -m)架构" && exit;;
esac
case "$release" in
"Centos") PKGMGR="yum -y";;
"Ubuntu"|"Debian") PKGMGR="apt-get -y";;
esac
if [ ! -f tuic_update ]; then
$PKGMGR update ; $PKGMGR install curl wget cron ; touch tuic_update
fi
if [[ $vi = openvz ]]; then
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
red "检测到未开启TUN，现尝试添加TUN支持" && sleep 4
cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun
TUN=$(cat /dev/net/tun 2>&1)
if [[ ! $TUN =~ 'in bad state' ]] && [[ ! $TUN =~ '处于错误状态' ]] && [[ ! $TUN =~ 'Die Dateizugriffsnummer ist in schlechter Verfassung' ]]; then
green "添加TUN支持失败，建议与VPS厂商沟通或后台设置开启" && exit
else
echo '#!/bin/bash' > /root/tun.sh && echo 'cd /dev && mkdir net && mknod net/tun c 10 200 && chmod 0666 net/tun' >> /root/tun.sh && chmod +x /root/tun.sh
grep -qE "^ *@reboot root bash /root/tun.sh >/dev/null 2>&1" /etc/crontab || echo "@reboot root bash /root/tun.sh >/dev/null 2>&1" >> /etc/crontab
green "TUN守护功能已启动"
fi
fi
fi
warpcheck(){
wgcfv6=$(curl -s6m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
wgcfv4=$(curl -s4m5 https://www.cloudflare.com/cdn-cgi/trace -k | grep warp | cut -d= -f2)
}
v6(){
warpcheck
if [[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]]; then
v4=$(curl -s4m5 ip.gs -k)
if [ -z $v4 ]; then
yellow "检测到 纯IPV6 VPS，添加DNS64"
echo -e "nameserver 2a00:1098:2b::1\nnameserver 2a00:1098:2c::1\nnameserver 2a01:4f8:c2c:123f::1" > /etc/resolv.conf
fi
fi
}
close(){
systemctl stop firewalld.service >/dev/null 2>&1
systemctl disable firewalld.service >/dev/null 2>&1
setenforce 0 >/dev/null 2>&1
ufw disable >/dev/null 2>&1
iptables -P INPUT ACCEPT >/dev/null 2>&1
iptables -P FORWARD ACCEPT >/dev/null 2>&1
iptables -P OUTPUT ACCEPT >/dev/null 2>&1
iptables -t mangle -F >/dev/null 2>&1
iptables -F >/dev/null 2>&1
iptables -X >/dev/null 2>&1
netfilter-persistent save >/dev/null 2>&1
if [[ -n $(apachectl -v 2>/dev/null) ]]; then
systemctl stop httpd.service >/dev/null 2>&1
systemctl disable httpd.service >/dev/null 2>&1
service apache2 stop >/dev/null 2>&1
systemctl disable apache2 >/dev/null 2>&1
fi
sleep 1
green "执行开放端口，关闭防火墙完毕"
}
openyn(){
echo
readp "是否开放端口，关闭防火墙？\n1、是，执行(回车默认)\n2、否，我自已手动\n请选择：" action
if [[ -z $action ]] || [[ $action == "1" ]]; then
close
elif [[ $action == "2" ]]; then
echo
else
red "输入错误,请重新选择" && openyn
fi
}
insupdate(){
if [[ $release = Centos ]]; then
if [[ ${vsid} =~ 8 ]]; then
yum -y install redhat-lsb-core
yum clean all && yum makecache
fi
yum install epel-release -y
else
apt update
fi
}
instucore(){
#version=$(curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
wget -NO /usr/local/bin/tuic https://github.com/EAimTY/tuic/releases/download/tuic-server-1.0.0/tuic-server-1.0.0-$(uname -m)-unknown-linux-musl
if [[ -f '/usr/local/bin/tuic' ]]; then
chmod +x /usr/local/bin/tuic
blue "成功安装 tuic V5 内核版本：$(/usr/local/bin/tuic -v)\n"
else
red "安装 tuic V5 内核失败" && exit
fi
}
V4--instucore(){
#version=$(curl -s https://data.jsdelivr.com/v1/package/gh/EAimTY/tuic | sed -n 4p | tr -d ',"' | awk '{print $1}')
wget -NO /usr/local/bin/tuic https://github.com/EAimTY/tuic/releases/download/0.8.5/tuic-server-0.8.5-$(uname -m)-linux-musl
if [[ -f '/usr/local/bin/tuic' ]]; then
chmod +x /usr/local/bin/tuic
blue "成功安装 tuic V4 内核版本：$(/usr/local/bin/tuic -v)\n"
else
red "安装 tuic V4 内核失败" && exit
fi
}
inscertificate(){
green "tuic协议证书申请方式选择如下:"
readp "1. acme一键申请证书脚本（支持常规80端口模式与dns api模式），已用此脚本申请的证书则自动识别（回车默认）\n2. 自定义证书路径（非/root/ygkkkca路径）\n请选择：" certificate
if [ -z "${certificate}" ] || [ $certificate == "1" ]; then
if [[ -f /root/ygkkkca/cert.crt && -f /root/ygkkkca/private.key ]] && [[ -s /root/ygkkkca/cert.crt && -s /root/ygkkkca/private.key ]] && [[ -f /root/ygkkkca/ca.log ]]; then
blue "经检测，之前已使用此acme脚本申请过证书"
readp "1. 直接使用原来的证书（回车默认）\n2. 删除原来的证书，重新申请证书\n请选择：" certacme
if [ -z "${certacme}" ] || [ $certacme == "1" ]; then
ym=$(cat /root/ygkkkca/ca.log)
blue "检测到的域名：$ym ，已直接引用\n"
elif [ $certacme == "2" ]; then
curl https://get.acme.sh | sh
bash /root/.acme.sh/acme.sh --uninstall
rm -rf /root/ygkkkca
rm -rf ~/.acme.sh acme.sh
sed -i '/--cron/d' /etc/crontab
[[ -z $(/root/.acme.sh/acme.sh -v 2>/dev/null) ]] && green "acme.sh卸载完毕" || red "acme.sh卸载失败"
sleep 2
wget -N https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh && bash acme.sh
ym=$(cat /root/ygkkkca/ca.log)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key ]] && [[ ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "证书申请失败，脚本退出" && exit
fi
fi
else
wget -N https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh && bash acme.sh
ym=$(cat /root/ygkkkca/ca.log)
if [[ ! -f /root/ygkkkca/cert.crt && ! -f /root/ygkkkca/private.key ]] && [[ ! -s /root/ygkkkca/cert.crt && ! -s /root/ygkkkca/private.key ]]; then
red "证书申请失败，脚本退出" && exit
fi
fi
certificatec='/root/ygkkkca/cert.crt'
certificatep='/root/ygkkkca/private.key'
elif [ $certificate == "2" ]; then
readp "请输入已放置好的公钥文件crt的路径（/a/b/……/cert.crt）：" cerroad
blue "公钥文件crt的路径：$cerroad "
readp "请输入已放置好的密钥文件key的路径（/a/b/……/private.key）：" keyroad
blue "密钥文件key的路径：$keyroad "
certificatec=$cerroad
certificatep=$keyroad
readp "请输入已解析好的域名:" ym
blue "已解析好的域名：$ym "
else
red "输入错误，请重新选择" && inscertificate
fi
}
insport(){
readp "\n设置tuic端口[1-65535]（回车跳过为2000-65535之间的随机端口）：" port
if [[ -z $port ]]; then
port=$(shuf -i 2000-65535 -n 1)
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义tuic端口:" port
done
else
until [[ -z $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]]
do
[[ -n $(ss -tunlp | grep -w udp | awk '{print $5}' | sed 's/.*://g' | grep -w "$port") ]] && yellow "\n端口被占用，请重新输入端口" && readp "自定义tuic端口:" port
done
fi
blue "已确认端口：$port\n"
}
insuuid(){
readp "设置tuic的uuid与密码，两者默认一致,必须为uuid格式（建议回车跳过生成随机uuid）：" uuid
if [[ -z ${uuid} ]]; then
uuid=`cat /proc/sys/kernel/random/uuid`
fi
blue "已确认uuid与密码：${uuid}\n"
}
V4--inspswd(){
readp "设置tuic令牌码Token，必须为6位字符以上（回车跳过为随机6位字符）：" pswd
if [[ -z ${pswd} ]]; then
pswd=`date +%s%N |md5sum | cut -c 1-6`
else
if [[ 6 -ge ${#pswd} ]]; then
until [[ 6 -le ${#pswd} ]]
do
[[ 6 -ge ${#pswd} ]] && yellow "\n用户名必须为6位字符以上！请重新输入" && readp "\n设置tuic令牌码Token：" pswd
done
fi
fi
blue "已确认令牌码Token：${pswd}\n"
}
insconfig(){
green "设置 tuic V5 配置文件、服务进程……\n"
mkdir /etc/tuic >/dev/null 2>&1
cat <<EOF > /etc/tuic/tuic.json
{
    "server": "[::]:$port",
    "users": {
        "$uuid": "$uuid"
    },
    "certificate": "$certificatec",
    "private_key": "$certificatep",
    "congestion_control": "bbr",
    "alpn": ["h3", "spdy/3.1"],
    "log_level": "warn"
}
EOF
mkdir /root/tuic >/dev/null 2>&1
cat <<EOF > /root/tuic/v2rayn.json
{
    "relay": {
        "server": "$ym:$port",
        "uuid": "$uuid",
        "password": "$uuid",
        "congestion_control": "bbr",
        "alpn": ["h3", "spdy/3.1"]
    },
    "local": {
        "server": "127.0.0.1:55555"
    },
    "log_level": "warn"
}
EOF
cat <<EOF > /root/tuic/tuic.txt
服务器地址: $ym
服务器端口: $port
uuid: $uuid
密码: $uuid
应用层协议ALPN: h3
UDP转发模式: 开启
congestion control模式: bbr
EOF
cat <<EOF > /root/tuic/clashMeta-tuic.yaml
proxies:
  - name: ygkkk-tuic
    server: $ym
    port: $port
    type: tuic
    uuid: $uuid
    password: $uuid
    alpn: [h3]
    disable-sni: true
    reduce-rtt: true
    udp-relay-mode: native
    congestion-controller: bbr
EOF
cat <<EOF > /root/tuic/TuicUsers.txt
用户别名: $name   UUID与密码: $uuid
EOF
cat << EOF >/etc/systemd/system/tuic.service
[Unit]
Description=YGKKK-TUIC
Documentation=https://gitlab.com/rwkgyg/tuic-yg
After=network.target
[Service]
User=root
ExecStart=/usr/local/bin/tuic -c /etc/tuic/tuic.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tuic
systemctl start tuic
}
V4--insconfig(){
green "设置 tuic V4 配置文件、服务进程……\n"
mkdir /etc/tuic >/dev/null 2>&1
cat <<EOF > /etc/tuic/tuic.json
{
    "port": $port,
    "token": ["$pswd"],
    "certificate": "$certificatec",
    "private_key": "$certificatep",
    "ip": "::",
    "congestion_controller": "bbr",
    "alpn": ["h3"]
}
EOF
mkdir /root/tuic >/dev/null 2>&1
cat <<EOF > /root/tuic/v2rayn.json
{
    "relay": {
        "server": "$ym",
        "port": $port,
        "token": "$pswd",
        "congestion_controller": "bbr",
        "udp_relay_mode": "native",
        "alpn": ["h3"]
    },
    "local": {
        "port": 55555,
        "ip": "127.0.0.1"
    },
    "log_level": "off"
}
EOF
cat <<EOF > /root/tuic/tuic.txt
服务器地址: $ym
服务器端口: $port
令牌码token: $pswd
应用层协议ALPN: h3
UDP转发模式: 开启
congestion controller模式: bbr
EOF
cat <<EOF > /root/tuic/clashMeta-tuic.yaml
proxies:
  - name: ygkkk-tuic
    server: $ym
    port: $port
    type: tuic
    token: $pswd
    alpn: [h3]
    disable-sni: true
    reduce-rtt: true
    udp-relay-mode: native
    congestion-controller: bbr
EOF
cat << EOF >/etc/systemd/system/tuic.service
[Unit]
Description=YGKKK-TUIC
Documentation=https://gitlab.com/rwkgyg/tuic-yg
After=network.target
[Service]
User=root
ExecStart=/usr/local/bin/tuic -c /etc/tuic/tuic.json
Restart=on-failure
RestartSec=10
LimitNOFILE=infinity
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable tuic
systemctl start tuic
}
tuicactive(){
if [[ -z $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
green "未正常安装tuic" && exit
fi
}
stclre(){
tuicactive
green "tuic服务执行以下操作"
readp "1. 重启\n2. 关闭\n请选择：" action
if [[ $action == "1" ]]; then
systemctl enable tuic
systemctl start tuic
systemctl restart tuic
green "tuic服务已重启\n"
elif [[ $action == "2" ]]; then
systemctl stop tuic
systemctl disable tuic
green "tuic服务已关闭\n"
else
red "输入错误,请重新选择" && stclre
fi
}
changeserv(){
tuicactive
green "tuic配置变更选择如下:"
readp "1. 添加或删除用户(V5) / 变更令牌码Token(V4)\n2. 变更端口\n3. 重新申请证书或变更证书路径\n4. 返回上层\n请选择：" choose
if [ $choose == "1" ];then
v4v5uuidtoken
elif [ $choose == "2" ];then
changeport
elif [ $choose == "3" ];then
inscertificate
oldcer=`awk '/certificate/ {print $2}' /etc/tuic/tuic.json | tr -d ',"'`
oldkey=`awk '/private_key/ {print $2}' /etc/tuic/tuic.json | tr -d ',"'`
sed -i "s#$oldcer#${certificatec}#g" /etc/tuic/tuic.json
sed -i "s#$oldkey#${certificatep}#g" /etc/tuic/tuic.json
oldym=$(cat /root/tuic/tuic.txt | sed -n 1p | awk '{print $2}')
sed -i "s/$oldym/${ym}/g" /root/tuic/v2rayn.json
sed -i "s/$oldym/${ym}/g" /root/tuic/tuic.txt
sed -i "s/$oldym/${ym}/g" /root/tuic/clashMeta-tuic.yaml
susstuic
elif [ $choose == "4" ];then
tu
else
red "请重新选择" && changeserv
fi
}
v4v5uuidtoken(){
ygvsion=`/usr/local/bin/tuic -v 2>/dev/null`
if [ "$ygvsion" != "0.8.5" ]; then
addchangeuuid
else
V4--changepswd
fi
}
addchangeuuid(){
echo
blue "当前 tuic V5 已添加的用户列表："
cat /root/tuic/TuicUsers.txt
echo
readp "1. 增加用户\n2. 删除用户\n3. 返回上层\n请选择：" choose
if [ $choose == "1" ];then
readp "设置新增的用户别名（回车跳过为随机3位字符）：" nameuuid
if [[ -z ${nameuuid} ]]; then
nameuuid=`date +%s%N |md5sum | cut -c 1-3`
fi
blue "已确认用户别名：${nameuuid}\n"
insuuid
useruuid="\"$uuid\": \"$uuid\","
sed -i "3a $useruuid" /etc/tuic/tuic.json
nameuseruuid="用户别名: $nameuuid   UUID与密码: $uuid"
echo "$nameuseruuid" >> /root/tuic/TuicUsers.txt
echo
susstuic
elif [ $choose == "2" ];then
cat /root/tuic/TuicUsers.txt | awk '{print $2}'
readp "请复制上面要删除的用户别名：" nameuuid
if [[ ${nameuuid} == ${name} ]]; then
red "输入的用户别名为hostname，无法删除" && sleep 2 && addchangeuuid
fi
uuidde=$(grep -w $nameuuid /root/tuic/TuicUsers.txt | awk '{print $2}')
if [[ -z ${uuidde} ]]; then
red "输入的用户别名不存在" && sleep 2 && addchangeuuid
fi
blue "已确认删除的用户别名：${nameuuid}\n"
uuiddeser=$(grep -w $nameuuid /root/tuic/TuicUsers.txt | awk '{print $4}')
sed -i "/$uuiddeser/d" /etc/tuic/tuic.json
sed -i "/$nameuuid/d" /root/tuic/TuicUsers.txt
echo
susstuic
else
changeserv
fi
}
V4--changepswd(){
oldpswdc=$(cat /root/tuic/tuic.txt | sed -n 3p | awk '{print $2}')
echo
blue "当前正在使用的令牌码Token：$oldpswdc"
echo
V4--inspswd
sed -i "s/$oldpswdc/$pswd/g" /etc/tuic/tuic.json
sed -i "s/$oldpswdc/$pswd/g" /root/tuic/v2rayn.json
sed -i "s/$oldpswdc/$pswd/g" /root/tuic/tuic.txt
sed -i "s/$oldpswdc/$pswd/g" /root/tuic/clashMeta-tuic.yaml
susstuic
}
changeport(){
oldport1=$(cat /root/tuic/tuic.txt | sed -n 2p | awk '{print $2}')
echo
blue "当前正在使用的端口：$oldport1"
echo
insport
sed -i "s/$oldport1/$port/g" /etc/tuic/tuic.json
sed -i "s/$oldport1/$port/g" /root/tuic/v2rayn.json
sed -i "s/$oldport1/$port/g" /root/tuic/tuic.txt
sed -i "s/$oldport1/$port/g" /root/tuic/clashMeta-tuic.yaml
susstuic
}
acme(){
bash <(curl -Ls https://gitlab.com/rwkgyg/acme-script/raw/main/acme.sh)
}
cfwarp(){
bash <(curl -Ls https://gitlab.com/rwkgyg/CFwarp/raw/main/CFwarp.sh)
}
tuicstatus(){
warpcheck
[[ ! $wgcfv4 =~ on|plus && ! $wgcfv6 =~ on|plus ]] && wgcf=$(green "未启用") || wgcf=$(green "启用中")
if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
status=$(white "tuic状态：  \c";green "运行中";white "WARP状态：  \c";eval echo \$wgcf)
elif [[ -z $(systemctl status tuic 2>/dev/null | grep -w active) && -f '/etc/tuic/tuic.json' ]]; then
status=$(white "tuic状态：  \c";yellow "未启动,可尝试选择4，开启或者重启，依旧如此建议卸载重装tuic";white "WARP状态：  \c";eval echo \$wgcf)
else
status=$(white "tuic状态：  \c";red "未安装";white "WARP状态：  \c";eval echo \$wgcf)
fi
}
lntu(){
curl -sSL -o /usr/bin/tu -L https://gitlab.com/rwkgyg/tuic-yg/-/raw/main/tuic.sh
chmod +x /usr/bin/tu
}
uptuicyg(){
if [[ ! -f '/usr/bin/tu' ]]; then
red "未正常安装tuic-yg" && exit
fi
lntu
curl -s https://gitlab.com/rwkgyg/tuic-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/tuic/v
green "tuic-yg安装脚本升级成功" && tu
}
uptuic(){
tuicactive
green "\n升级tuic内核版本\n"
if [ "$ygvsion" != "0.8.5" ]; then
instucore
systemctl restart tuic
green "tuic内核版本升级成功" && tu
else
yellow "你正在使用 tuic V4 最终版，无需升级" && exit
fi
}
unins(){
systemctl stop tuic >/dev/null 2>&1
systemctl disable tuic >/dev/null 2>&1
rm -f /etc/systemd/system/tuic.service
rm -rf /usr/local/bin/tuic /etc/tuic /root/tuic /usr/bin/tu tuic_update
green "tuic卸载完成！"
}
susstuic(){
systemctl restart tuic
if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
green "tuic服务启动成功" && tuicshare
else
red "tuic服务启动失败，请运行systemctl status tuic查看服务状态并反馈，脚本退出" && exit
fi
}
tuicshare(){
tuicactive
red "======================================================================================"
ygvsion=`/usr/local/bin/tuic -v 2>/dev/null`
if [ "$ygvsion" != "0.8.5" ]; then
blue "当前 tuic V5 已添加的用户列表："
cat /root/tuic/TuicUsers.txt
echo
fi
blue "tuic配置明文如下：\n" && sleep 2
yellow "$(cat /root/tuic/tuic.txt)\n"
blue "v2rayn客户端配置保存到 /root/tuic/v2rayn.json\n" && sleep 2
yellow "$(cat /root/tuic/v2rayn.json)\n"
blue "clashMeta客户端配置保存到 /root/tuic/clashMeta-tuic.yaml" && sleep 2
yellow "$(cat /root/tuic/clashMeta-tuic.yaml)\n"
}
instuic(){
if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
green "已安装tuic，重装请先执行卸载功能" && exit
fi
v6 ; openyn ; insupdate
instucore && inscertificate && insport && insuuid && insconfig
if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
green "tuic服务启动成功，生成脚本的快捷方式为 tu" && sleep 1
curl -s https://gitlab.com/rwkgyg/tuic-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/tuic/v
lntu
if [[ ! $vi =~ lxc|openvz ]]; then
sysctl -w net.core.rmem_max=8000000
sysctl -p
fi
else
red "tuic服务启动失败，请运行systemctl status tuic查看服务状态并反馈，脚本退出" && exit
fi
tuicshare
}
V4--instuic(){
if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
green "已安装tuic，重装请先执行卸载功能" && exit
fi
v6 ; openyn ; insupdate
V4--instucore && inscertificate && insport && V4--inspswd && V4--insconfig
if [[ -n $(systemctl status tuic 2>/dev/null | grep -w active) ]]; then
green "tuic服务启动成功，生成脚本的快捷方式为 tu" && sleep 1
curl -s https://gitlab.com/rwkgyg/tuic-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1 > /etc/tuic/v
lntu
if [[ ! $vi =~ lxc|openvz ]]; then
sysctl -w net.core.rmem_max=8000000
sysctl -p
fi
else
red "tuic服务启动失败，请运行systemctl status tuic查看服务状态并反馈，脚本退出" && exit
fi
tuicshare
}
tulog(){
echo
red "退出 tuic 日志查看，请按 Ctrl+c"
echo
journalctl -u tuic --output cat -f
}
tuicstatus
clear
green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
echo -e "${bblue} ░██     ░██      ░██ ██ ██         ░█${plain}█   ░██     ░██   ░██     ░█${red}█   ░██${plain}  "
echo -e "${bblue}  ░██   ░██      ░██    ░░██${plain}        ░██  ░██      ░██  ░██${red}      ░██  ░██${plain}   "
echo -e "${bblue}   ░██ ░██      ░██ ${plain}                ░██ ██        ░██ █${red}█        ░██ ██  ${plain}   "
echo -e "${bblue}     ░██        ░${plain}██    ░██ ██       ░██ ██        ░█${red}█ ██        ░██ ██  ${plain}  "
echo -e "${bblue}     ░██ ${plain}        ░██    ░░██        ░██ ░██       ░${red}██ ░██       ░██ ░██ ${plain}  "
echo -e "${bblue}     ░█${plain}█          ░██ ██ ██         ░██  ░░${red}██     ░██  ░░██     ░██  ░░██ ${plain}  "
green "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "甬哥Github项目  ：github.com/yonggekkk"
white "甬哥blogger博客 ：ygkkk.blogspot.com"
white "甬哥YouTube频道 ：www.youtube.com/@ygkkk"
green "tuic-yg脚本安装成功后，再次进入脚本的快捷方式为 tu"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
yellow "本脚本停止更新，请使用甬哥最新的四合一脚本，支持tuic-v5"
yellow "一键脚本项目地址：https://github.com/yonggekkk/sing-box-yg"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
green "  1. 安装 tuic v5"
green "  2. 安装 tuic v4"
green "  3. 卸载 tuic"
white "----------------------------------------------------------------------------------"
green "  4. 变更 tuic 配置（用户数、端口、证书）"
green "  5. 关闭、重启 tuic"
green "  6. 更新 tuic-yg 安装脚本"
green "  7. 更新 tuic 内核版本"
white "----------------------------------------------------------------------------------"
green "  8. 显示当前 tuic 代理用户数、配置明文、V2rayN、clashMeta配置文件"
green "  9. 查看 tuic 运行日志"
green " 10. 管理 ACME 证书申请"
green " 11. 管理 WARP"
green "  0. 退出脚本"
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
ygvsion=`/usr/local/bin/tuic -v 2>/dev/null`
lastvsion=`curl -s https://api.github.com/repos/EAimTY/tuic/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4 | cut -d'-' -f3`
insV=$(cat /etc/tuic/v 2>/dev/null)
latestV=$(curl -s https://gitlab.com/rwkgyg/tuic-yg/-/raw/main/version/version | awk -F "更新内容" '{print $1}' | head -n 1)
if [ -n "$ygvsion" ] && [ "$ygvsion" != "0.8.5" ] && [ -f '/etc/tuic/tuic.json' ]; then
if [ "$insV" = "$latestV" ]; then
echo -e " 当前 tuic-yg 安装脚本版本号：${bblue}${insV}${plain} ，已是最新版本\n"
else
echo -e " 当前 tuic-yg 安装脚本版本号：${bblue}${insV}${plain}"
echo -e " 检测到最新 tuic-yg 安装脚本版本号：${yellow}${latestV}${plain}"
echo -e "${yellow}$(curl -s https://gitlab.com/rwkgyg/tuic-yg/-/raw/main/version/version)${plain}"
echo -e " 可选择6进行更新\n"
fi
if [ "$ygvsion" = "$lastvsion" ]; then
echo -e " 当前 tuic V5 已安装内核版本号：${bblue}${ygvsion}${plain} ，已是官方最新版本"
else
echo -e " 当前 tuic V5 已安装内核版本号：${bblue}${ygvsion}${plain}"
echo -e " 检测到最新 tuic V5 内核版本号：${yellow}${lastvsion}${plain} ，可选择7进行更新"
fi
elif [ "$ygvsion" = "0.8.5" ] && [ -f '/etc/tuic/tuic.json' ]; then
if [ "$insV" = "$latestV" ]; then
echo -e " 当前 tuic-yg 安装脚本版本号：${bblue}${insV}${plain} ，已是最新版本\n"
else
echo -e " 当前 tuic-yg 安装脚本版本号：${bblue}${insV}${plain}"
echo -e " 检测到最新 tuic-yg 安装脚本版本号：${yellow}${latestV}${plain}"
echo -e "${yellow}$(curl -s https://gitlab.com/rwkgyg/tuic-yg/-/raw/main/version/version)${plain}"
echo -e " 可选择6进行更新\n"
fi
echo -e " 当前 tuic V4 已安装内核版本号：${bblue}${ygvsion}${plain} ，已是官方最终版本，不再更新"
else
echo -e " 当前 tuic-yg 脚本版本号：${bblue}${latestV}${plain} 已是最新版本\n"
fi
red "~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~"
white "VPS系统信息如下："
white "操作系统：  $(blue "$op")" && white "内核版本：  $(blue "$version")" && white "CPU架构：   $(blue "$cpu")" && white "虚拟化类型：$(blue "$vi")"
white "$status"
echo
readp "请输入数字:" Input
case "$Input" in
 1 ) instuic;;
 2 ) V4--instuic;;
 3 ) unins;;
 4 ) changeserv;;
 5 ) stclre;;
 6 ) uptuicyg;;
 7 ) uptuic;;
 8 ) tuicshare;;
 9 ) tulog;;
10 ) acme;;
11 ) cfwarp;;
 * ) exit
esac