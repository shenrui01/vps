#!/bin/bash
clear
if [ $(id -u) != "0" ]; then
    printf "Error: You must be root to run this tool!\n"
    exit 1
fi

host_ip=`ifconfig eth0 | awk '/inet addr/ {print $2}' | awk -F ':' '{print $2}'`
cur_dir=`pwd`
read -p "(Please input PSK: )" psk
if [ "$psk" = "" ]; then
        psk="rsis.me"
fi

read -p "Enter vpn username: " username
if [ "$username" = "" ];then
        username="vpn"
fi

read -p "Enter vpn password: " userpsw
if [ "$userpsw" = "" ];then
        userpsw="vpn"
fi

clear
get_char()
{
SAVEDSTTY=`stty -g`
stty -echo
stty cbreak
dd if=/dev/tty bs=1 count=1 2> /dev/null
stty -raw
stty echo
stty $SAVEDSTTY
}
echo ""
echo "ServerIP:"
echo "$host_ip"
echo ""
echo "PSK:"
echo "$psk"
echo ""
echo "VPN Account:"
echo "$username"
echo ""
echo "Account Password:"
echo "$userpsw"
echo ""
echo "Press any key to start..."
char=`get_char`
clear

yum -y update
yum remove  -y pptpd ppp
yum install -y make gcc gmp-devel bison flex libpcap-devel ppp lsof perl iptables 
yum install -y libpcap gcc-c++ logrotate tar cpio pam tcp_wrappers

wget http://cloud.github.com/downloads/shenrui01/vps/dkms-2.0.17.5-1.noarch.rpm
wget http://cloud.github.com/downloads/shenrui01/vps/kernel_ppp_mppe-1.0.2-3dkms.noarch.rpm
wget http://cloud.github.com/downloads/shenrui01/vps/pptpd-1.3.4-1.rhel5.1.i386.rpm

rpm -ivh dkms-2.0.17.5-1.noarch.rpm
rpm -ivh kernel_ppp_mppe-1.0.2-3dkms.noarch.rpm
rpm -qa kernel_ppp_mppe
rpm -ivh pptpd-1.3.4-1.rhel5.1.i386.rpm


wget http://cloud.github.com/downloads/shenrui01/vps/openswan-2.6.34.tar.gz
tar zxvf openswan-2.6.34.tar.gz
cd openswan-2.6.34/
make programs install
cd ../

cat > /etc/ipsec.conf <<EOF
version 2.0
config setup
    nat_traversal=yes
    virtual_private=%v4:10.0.0.0/8,%v4:192.168.0.0/16,%v4:172.16.0.0/12
    oe=off
    protostack=netkey

conn L2TP-PSK-NAT
    rightsubnet=vhost:%priv
    also=L2TP-PSK-noNAT

conn L2TP-PSK-noNAT
    authby=secret
    pfs=no
    auto=add
    keyingtries=3
    rekey=no
    ikelifetime=8h
    keylife=1h
    type=transport
    left=$host_ip
    leftprotoport=17/1701
    right=%any
    rightprotoport=17/%any
EOF

cat > /etc/ipsec.secrets <<EOF
$host_ip %any: PSK "$psk"
EOF

for each in /proc/sys/net/ipv4/conf/*
do
echo 0 > $each/accept_redirects
echo 0 > $each/send_redirects
done
echo 1 > /proc/sys/net/core/xfrm_larval_drop
iptables --table nat --append POSTROUTING -o eth0 --jump MASQUERADE 

service iptables save
service iptables restart
chkconfig iptables on

sed -i 's/net.ipv4.ip_forward = 0/net.ipv4.ip_forward = 1/g' /etc/sysctl.conf
sysctl -p

/etc/init.d/ipsec restart
ipsec verify

cd $cur_dir
wget http://cloud.github.com/downloads/shenrui01/vps/rp-l2tp-0.4.tar.gz
tar zxvf rp-l2tp-0.4.tar.gz
cd rp-l2tp-0.4
./configure
make
cp handlers/l2tp-control /usr/local/sbin/
mkdir /var/run/xl2tpd/
ln -s /usr/local/sbin/l2tp-control /var/run/xl2tpd/l2tp-control

cd $cur_dir
wget  http://cloud.github.com/downloads/shenrui01/vps/xl2tpd-1.2.8.tar
tar zxvf xl2tpd-1.2.8.tar
cd xl2tpd-1.2.8
make install
cd ..

mkdir -p /etc/xl2tpd
touch /etc/xl2tpd/xl2tpd.conf
cat >> /etc/xl2tpd/xl2tpd.conf <<EOF
[global]
ipsec saref = yes

[lns default]
ip range = 10.85.91.10-10.85.91.254
local ip = 10.85.91.1
refuse chap = yes
refuse pap = yes
require authentication = yes
ppp debug = yes
pppoptfile = /etc/ppp/options.xl2tpd
length bit = yes
EOF

touch /etc/ppp/options.xl2tpd
cat >> /etc/ppp/options.xl2tpd <<EOF
require-mschap-v2
ms-dns 8.8.8.8
ms-dns 8.8.4.4
asyncmap 0
auth
crtscts
lock
hide-password
modem
debug
name l2tpd
proxyarp
lcp-echo-interval 30
lcp-echo-failure 4
EOF

mknod /dev/ppp c 108 0 
echo "localip 10.85.92.1" >> /etc/pptpd.conf
echo "remoteip 10.85.92.10-254" >> /etc/pptpd.conf
echo "ms-dns 8.8.8.8" >> /etc/ppp/options.pptpd
echo "ms-dns 8.8.4.4" >> /etc/ppp/options.pptpd

chkconfig pptpd on
service pptpd restart

echo "$username l2tpd $userpsw *" >> /etc/ppp/chap-secrets
echo "$username pptpd $userpsw *" >> /etc/ppp/chap-secrets
/usr/local/sbin/xl2tpd

cat >> /etc/rc.local <<EOF
mknod /dev/ppp c 108 0
for each in /proc/sys/net/ipv4/conf/*
do
        echo 0 > \$each/accept_redirects
        echo 0 > \$each/send_redirects
done
echo 1 > /proc/sys/net/core/xfrm_larval_drop
/etc/init.d/ipsec restart
/usr/local/sbin/xl2tpd
EOF

clear

ipsec verify

printf "
if there are no [FAILED] above, then you can
connect to your L2TP&PPTP VPN Server with the default
user/pass below:

ServerIP:$host_ip
username:$username
password:$userpsw
PSK:$psk (for L2TP VPN)
"