#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
	echo ""
	echo "กรุณาเข้าสู่ระบบผู้ใช้ root ก่อนทำการใช้งานสคริปท์"
	echo "คำสั่งเข้าสู่ระบบผู้ใช้ root คือ sudo -i"
	echo ""
	exit
fi

if [[ ! -e /dev/net/tun ]]; then
	echo ""
	echo "TUN ไม่สามารถใช้งานได้"
	exit
fi


# Set Localtime GMT +7
ln -fs /usr/share/zoneinfo/Asia/Bangkok /etc/localtime

clear
# IP=$(ip addr | grep 'inet' | grep -v inet6 | grep -vE '127\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | grep -o -E '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | head -1)
# if [[ "$IP" = "" ]]; then
IP=$(wget -4qO- "http://whatismyip.akamai.com/")
# fi

# Color
GRAY='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'
YELLOW='\033[33;1m'
RED='\033[31;1m'
BLUE='\033[34;1m'
MAGENTA='\033[35;1m'
CYAN='\033[36;1m'

# Detect OS
# $os_version variables aren't always in use, but are kept here for convenience
if grep -qs "ubuntu" /etc/os-release; then
	os="ubuntu"
	os_version=$(grep 'VERSION_ID' /etc/os-release | cut -d '"' -f 2 | tr -d '.')
	group_name="nogroup"
elif [[ -e /etc/debian_version ]]; then
	os="debian"
	os_version=$(grep -oE '[0-9]+' /etc/debian_version | head -1)
	group_name="nogroup"
elif [[ -e /etc/almalinux-release || -e /etc/rocky-release || -e /etc/centos-release ]]; then
	os="centos"
	os_version=$(grep -shoE '[0-9]+' /etc/almalinux-release /etc/rocky-release /etc/centos-release | head -1)
	group_name="nobody"
elif [[ -e /etc/fedora-release ]]; then
	os="fedora"
	os_version=$(grep -oE '[0-9]+' /etc/fedora-release | head -1)
	group_name="nobody"
else
	echo "This installer seems to be running on an unsupported distribution.
Supported distros are Ubuntu, Debian, AlmaLinux, Rocky Linux, CentOS and Fedora."
	exit
fi

# ads
echo ""
echo -e "${RED} =============== OS-32 & 64-bit =================    "
echo -e "${RED} #    OS  DEBIAN 8-9-10  OS  UBUNTU 14-16-18    #    "
echo -e "${RED} #         BY : Pirakit Khawpleum               #    "
echo -e "${RED} #    FB : https://m.me/pirakrit.khawplum       #    "
echo -e "${RED} =============== OS-32 & 64-bit =================    "
echo -e "${GREEN} ไอพีเซิฟ: $IP "
echo -e "${NC} "
# Install openvpn
cd
echo -e "\033[35;1m
----------------------------------------------
[√] ระบบสคริป  : Pirakit Khawpleum 
[√] กรุณารอสักครู่ .....
[√] Loading .....
----------------------------------------------
${NC} "

newclient () {
	# Generates the custom client.ovpn
	cp /etc/openvpn/client-common.txt ~/$1.ovpn
	echo "<ca>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/ca.crt >> ~/$1.ovpn
	echo "</ca>" >> ~/$1.ovpn
	echo "<cert>" >> ~/$1.ovpn
	sed -ne '/BEGIN CERTIFICATE/,$ p' /etc/openvpn/easy-rsa/pki/issued/$1.crt >> ~/$1.ovpn
	echo "</cert>" >> ~/$1.ovpn
	echo "<key>" >> ~/$1.ovpn
	cat /etc/openvpn/easy-rsa/pki/private/$1.key >> ~/$1.ovpn
	echo "</key>" >> ~/$1.ovpn
	echo "<tls-auth>" >> ~/$1.ovpn
	sed -ne '/BEGIN OpenVPN Static key/,$ p' /etc/openvpn/ta.key >> ~/$1.ovpn
	echo "</tls-auth>" >> ~/$1.ovpn
}
if [[ -e /etc/openvpn/server.conf ]]; then
			echo
			read -p "คุณต้องการลบ OpenVPN จริงๆหรือ? [y/N]: " -e REMOVE
			if [[ "$REMOVE" = 'y' || "$REMOVE" = 'Y' ]]; then
				PORT=$(grep '^port ' /etc/openvpn/server.conf | cut -d " " -f 2)
				PROTOCOL=$(grep '^proto ' /etc/openvpn/server.conf | cut -d " " -f 2)
				if pgrep firewalld; then
					IP=$(firewall-cmd --direct --get-rules ipv4 nat POSTROUTING | grep '\-s 10.8.0.0/24 '"'"'!'"'"' -d 10.8.0.0/24 -j SNAT --to ' | cut -d " " -f 10)
					# Using both permanent and not permanent rules to avoid a firewalld reload.
					firewall-cmd --zone=public --remove-port=$PORT/$PROTOCOL
					firewall-cmd --zone=trusted --remove-source=10.8.0.0/24
					firewall-cmd --permanent --zone=public --remove-port=$PORT/$PROTOCOL
					firewall-cmd --permanent --zone=trusted --remove-source=10.8.0.0/24
					firewall-cmd --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
					firewall-cmd --permanent --direct --remove-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
				else
					IP=$(grep 'iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to ' $RCLOCAL | cut -d " " -f 14)
					iptables -t nat -D POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
					sed -i '/iptables -t nat -A POSTROUTING -s 10.8.0.0\/24 ! -d 10.8.0.0\/24 -j SNAT --to /d' $RCLOCAL
					if iptables -L -n | grep -qE '^ACCEPT'; then
						iptables -D INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
						iptables -D FORWARD -s 10.8.0.0/24 -j ACCEPT
						iptables -D FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
						sed -i "/iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT/d" $RCLOCAL
						sed -i "/iptables -I FORWARD -s 10.8.0.0\/24 -j ACCEPT/d" $RCLOCAL
						sed -i "/iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT/d" $RCLOCAL
					fi
				fi
				if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$PORT" != '1194' ]]; then
					semanage port -d -t openvpn_port_t -p $PROTOCOL $PORT
				fi
				apt-get remove --purge -y nginx
				rm -rf /home/vps/public_html
				rm -rf /etc/openvpn
				rm -rf /usr/local/bin/*
				if [[ "$OS" = 'debian' ]]; then
					apt-get remove --purge -y openvpn
				else
					yum remove openvpn -y
				fi
				rm -rf /etc/openvpn
				rm -f /etc/sysctl.d/30-openvpn-forward.conf
				echo
				echo "OpenVPN removed!"
			else
				echo
				echo "Removal aborted!"
			fi
			exit

# elif [[ -e /etc/apt/sources.list.d/pritunl.list ]]; then
# echo ""
# echo "ไม่สามารถติดตั้ง OpenVPN ได้"
# echo "เนื่องจาก IP นี้ได้ติดตั้ง OpenVPN ที่ควบคุมการใช้งานผ่าน PRITUNL ไปก่อนหน้านี้แล้ว"
# exit

else
	clear
echo ""
echo -e "${RED} =============== OS-32 & 64-bit =================    "
echo -e "${RED} #    OS  DEBIAN 8-9-10  OS  UBUNTU 14-16-18    #    "
echo -e "${RED} #         BY : Pirakit Khawpleum               #    "
echo -e "${RED} #    FB : https://m.me/pirakrit.khawplum       #    "
echo -e "${RED} =============== OS-32 & 64-bit =================    "
echo -e "${GREEN} ไอพีเซิฟ: $IP "
echo -e "${NC} "
# Install openvpn
cd
echo -e "\033[35;1m
----------------------------------------------
[√] ระบบสคริป  : Pirakit Khawpleum 
[√] กรุณารอสักครู่ .....
[√] Loading .....
----------------------------------------------
${NC} "
	read -p "IP Server : " -e -i $IP IP
	read -p "Port Server : " -e -i 443 PORT
	echo ""
	echo -e " |${GRAY}1${NC}| UDP"
	echo -e " |${GRAY}2${NC}| TCP"
	echo ""
	read -p "Protocol : " -e -i 2 PROTOCOL
	case $PROTOCOL in
		1) 
		PROTOCOL=udp
		;;
		2) 
		PROTOCOL=tcp
		;;
	esac
	echo ""
	echo -e " |${GRAY}1${NC}| DNS Current System"
	echo -e " |${GRAY}2${NC}| DNS Google"
	echo -e " |${GRAY}3${NC}| DNS OpenDNS Home"
	echo ""
	read -p "DNS : " -e -i 2 DNS
	echo ""
	echo -e " |${GRAY}1${NC}| 1 ไฟล์เชื่อมต่อได้ 1 เครื่องเท่านั้น แต่สามารถสร้างไฟล์เพิ่มได้"
	echo -e " |${GRAY}2${NC}| 1 ไฟล์เชื่อมต่อได้หลายเครื่อง แต่ต้องใช้ชื่อบัญชีและรหัสผ่านเพื่อใช้เชื่อมต่อ"
	echo -e " |${GRAY}3${NC}| 1 ไฟล์เชื่อมต่อได้ไม่จำกัดจำนวนเครื่อง"
	echo ""
	read -p "Server System : " -e OPENVPNSYSTEM
	echo ""
	read -p "Server Name: " -e CLIENT
	echo ""
	case $OPENVPNSYSTEM in
		2)
		read -p "Your Username : " -e Usernames
		read -p "Your Password : " -e Passwords
		;;
	esac
	echo ""
	read -n1 -r -p "กด Enter 1 ครั้งเพื่อเริ่มทำการติดตั้ง หรือกด CTRL+C เพื่อยกเลิก"

	apt-get update
	apt-get install openvpn iptables openssl ca-certificates -y

	# Get easy-rsa
	EASYRSAURL='https://github.com/OpenVPN/easy-rsa/releases/download/v3.0.5/EasyRSA-nix-3.0.5.tgz'
	wget -O ~/easyrsa.tgz "$EASYRSAURL" 2>/dev/null || curl -Lo ~/easyrsa.tgz "$EASYRSAURL"
	tar xzf ~/easyrsa.tgz -C ~/
	mv ~/EasyRSA-3.0.5/ /etc/openvpn/
	mv /etc/openvpn/EasyRSA-3.0.5/ /etc/openvpn/easy-rsa/
	chown -R root:root /etc/openvpn/easy-rsa/
	rm -f ~/easyrsa.tgz
	cd /etc/openvpn/easy-rsa/
	# Create the PKI, set up the CA and the server and client certificates
	./easyrsa init-pki
	./easyrsa --batch build-ca nopass
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-server-full server nopass
	EASYRSA_CERT_EXPIRE=3650 ./easyrsa build-client-full $CLIENT nopass
	EASYRSA_CRL_DAYS=3650 ./easyrsa gen-crl
	# Move the stuff we need
	cp pki/ca.crt pki/private/ca.key pki/issued/server.crt pki/private/server.key pki/crl.pem /etc/openvpn
	# CRL is read with each client connection, when OpenVPN is dropped to nobody
	chown nobody:$GROUPNAME /etc/openvpn/crl.pem
	# Generate key for tls-auth
	openvpn --genkey --secret /etc/openvpn/ta.key
	# Create the DH parameters file using the predefined ffdhe2048 group
	echo '-----BEGIN DH PARAMETERS-----
MIIBCAKCAQEA//////////+t+FRYortKmq/cViAnPTzx2LnFg84tNpWp4TZBFGQz
+8yTnc4kmz75fS/jY2MMddj2gbICrsRhetPfHtXV/WVhJDP1H18GbtCFY2VVPe0a
87VXE15/V8k1mE8McODmi3fipona8+/och3xWKE2rec1MKzKT0g6eXq8CrGCsyT7
YdEIqUuyyOP7uWrat2DX9GgdT0Kj3jlN9K5W7edjcrsZCwenyO4KbXCeAvzhzffi
7MA0BM0oNC9hkXL+nOmFg/+OTxIy7vKBg8P+OxtMb61zO7X8vC7CIAXFjvGDfRaD
ssbzSibBsu/6iGtCOGEoXJf//////////wIBAg==
-----END DH PARAMETERS-----' > /etc/openvpn/dh.pem
	# Generate server.conf
	echo "port $PORT
proto $PROTOCOL
dev tun
sndbuf 0
rcvbuf 0
ca ca.crt
cert server.crt
key server.key
dh dh.pem
auth SHA512
tls-auth ta.key 0
topology subnet
server 10.8.0.0 255.255.255.0
ifconfig-pool-persist ipp.txt" > /etc/openvpn/server.conf
	echo 'push "redirect-gateway def1 bypass-dhcp"' >> /etc/openvpn/server.conf
	# DNS
	case $DNS in
		1)
		# Locate the proper resolv.conf
		# Needed for systems running systemd-resolved
		if grep -q "127.0.0.53" "/etc/resolv.conf"; then
			RESOLVCONF='/run/systemd/resolve/resolv.conf'
		else
			RESOLVCONF='/etc/resolv.conf'
		fi
		# Obtain the resolvers from resolv.conf and use them for OpenVPN
		grep -v '#' $RESOLVCONF | grep 'nameserver' | grep -E -o '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line; do
			echo "push \"dhcp-option DNS $line\"" >> /etc/openvpn/server.conf
		done
		;;
		2)
		echo 'push "dhcp-option DNS 8.8.8.8"' >> /etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 8.8.4.4"' >> /etc/openvpn/server.conf
		;;
		3)
		echo 'push "dhcp-option DNS 208.67.222.222"' >> /etc/openvpn/server.conf
		echo 'push "dhcp-option DNS 208.67.220.220"' >> /etc/openvpn/server.conf
		;;
	esac
	echo "keepalive 10 120
cipher AES-256-CBC
user nobody
group $GROUPNAME
persist-key
persist-tun
status openvpn-status.log
verb 3
crl-verify crl.pem" >> /etc/openvpn/server.conf
	# Enable net.ipv4.ip_forward for the system
	echo 'net.ipv4.ip_forward=1' > /etc/sysctl.d/30-openvpn-forward.conf
	# Enable without waiting for a reboot or service restart
	echo 1 > /proc/sys/net/ipv4/ip_forward
	if pgrep firewalld; then
		# Using both permanent and not permanent rules to avoid a firewalld
		# reload.
		# We don't use --add-service=openvpn because that would only work with
		# the default port and protocol.
		firewall-cmd --zone=public --add-port=$PORT/$PROTOCOL
		firewall-cmd --zone=trusted --add-source=10.8.0.0/24
		firewall-cmd --permanent --zone=public --add-port=$PORT/$PROTOCOL
		firewall-cmd --permanent --zone=trusted --add-source=10.8.0.0/24
		# Set NAT for the VPN subnet
		firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
		firewall-cmd --permanent --direct --add-rule ipv4 nat POSTROUTING 0 -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
	else
		# Needed to use rc.local with some systemd distros
		if [[ "$OS" = 'debian' && ! -e $RCLOCAL ]]; then
			echo '#!/bin/sh -e
exit 0' > $RCLOCAL
		fi
		chmod +x $RCLOCAL
		# Set NAT for the VPN subnet
		iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP
		sed -i "1 a\iptables -t nat -A POSTROUTING -s 10.8.0.0/24 ! -d 10.8.0.0/24 -j SNAT --to $IP" $RCLOCAL
		if iptables -L -n | grep -qE '^(REJECT|DROP)'; then
			# If iptables has at least one REJECT rule, we asume this is needed.
			# Not the best approach but I can't think of other and this shouldn't
			# cause problems.
			iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT
			iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT
			iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT
			sed -i "1 a\iptables -I INPUT -p $PROTOCOL --dport $PORT -j ACCEPT" $RCLOCAL
			sed -i "1 a\iptables -I FORWARD -s 10.8.0.0/24 -j ACCEPT" $RCLOCAL
			sed -i "1 a\iptables -I FORWARD -m state --state RELATED,ESTABLISHED -j ACCEPT" $RCLOCAL
		fi
	fi
	# If SELinux is enabled and a custom port was selected, we need this
	if sestatus 2>/dev/null | grep "Current mode" | grep -q "enforcing" && [[ "$PORT" != '1194' ]]; then
		# Install semanage if not already present
		if ! hash semanage 2>/dev/null; then
			yum install policycoreutils-python -y
		fi
		semanage port -a -t openvpn_port_t -p $PROTOCOL $PORT
	fi
	# And finally, restart OpenVPN
	if [[ "$OS" = 'debian' ]]; then
		# Little hack to check for systemd
		if pgrep systemd-journal; then
			systemctl restart openvpn@server.service
		else
			/etc/init.d/openvpn restart
		fi
	else
		if pgrep systemd-journal; then
			systemctl restart openvpn@server.service
			systemctl enable openvpn@server.service
		else
			service openvpn restart
			chkconfig openvpn on
		fi
	fi
	# If the server is behind a NAT, use the correct IP address
	if [[ "$PUBLICIP" != "" ]]; then
		IP=$PUBLICIP
	fi
	# client-common.txt is created so we have a template to add further users later
	echo "client
dev tun
proto $protocol
remote MyGatherBK 999 udp
remote $ip $port
http-proxy $ip 3128
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
auth SHA512
cipher AES-256-CBC
ignore-unknown-option block-outside-dns
block-outside-dns
verb 3" > /etc/openvpn/client-common.txt

	case $OPENVPNSYSTEM in
		2)
		echo "auth-user-pass" >> /etc/openvpn/client-common.txt
		;;
	esac
	


echo ""
echo -e "\033[0;32m { Install PROXY }${NC} "
echo ""

apt-get -y install squid
cat > /etc/squid/squid.conf <<-END
# install squid
http_port 8080
http_port 3128
acl localhost src 127.0.0.1/32 ::1
acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT
acl SSH dst xxxxxxxxx-xxxxxxxxx/255.255.255.255
http_access allow SSH
http_access allow localnet
http_access allow localhost
http_access deny all
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
END
sed -i $IP2 /etc/squid/squid.conf;

apt-get -y install squid3
cat > /etc/squid3/squid.conf <<-END
# install squid3
http_port 8080
http_port 3128
acl localhost src 127.0.0.1/32 ::1
acl to_localhost dst 127.0.0.0/8 0.0.0.0/32 ::1
acl localnet src 10.0.0.0/8
acl localnet src 172.16.0.0/12
acl localnet src 192.168.0.0/16
acl SSL_ports port 443
acl Safe_ports port 80
acl Safe_ports port 21
acl Safe_ports port 443
acl Safe_ports port 70
acl Safe_ports port 210
acl Safe_ports port 1025-65535
acl Safe_ports port 280
acl Safe_ports port 488
acl Safe_ports port 591
acl Safe_ports port 777
acl CONNECT method CONNECT
acl SSH dst xxxxxxxxx-xxxxxxxxx/255.255.255.255
http_access allow SSH
http_access allow localnet
http_access allow localhost
http_access deny all
refresh_pattern ^ftp:           1440    20%     10080
refresh_pattern ^gopher:        1440    0%      1440
refresh_pattern -i (/cgi-bin/|\?) 0     0%      0
refresh_pattern .               0       20%     4320
END
sed -i $IP2 /etc/squid3/squid.conf;

echo ""
echo -e "\033[0;32m { DOWNLOAD MENU SCRIPT }${NC} "
echo ""
	cd /usr/local/bin
wget -q -O m "https://raw.githubusercontent.com/MyGatherBk/MyAuto/master/Menu"
chmod +x /usr/local/bin/m
	wget -O /usr/local/bin/Auto-Delete-Client "https://raw.githubusercontent.com/MyGatherBk/PURE/master/Auto-Delete-Client"
	chmod +x /usr/local/bin/Auto-Delete-Client 
	apt-get -y install vnstat
	cd /etc/openvpn/easy-rsa/
	./easyrsa build-client-full $CLIENT nopass
	newclient "$CLIENT"
	cp /root/$CLIENT.ovpn /home/vps/public_html/
	rm -f /root/$CLIENT.ovpn
	case $OPENVPNSYSTEM in
		2)
		useradd $Usernames
		echo -e "$Passwords\n$Passwords\n"|passwd $Usernames &> /dev/null
		;;
	esac

	
	
	
	clear
echo ""
echo ""
echo -e "${RED} =============== OS-32 & 64-bit =================    "
echo -e "${RED} #    OS  DEBIAN 8-9-10  OS  UBUNTU 14-16-18    #    "
echo -e "${RED} #         BY : Pirakit Khawpleum               #    "
echo -e "${RED} #    FB : https://m.me/pirakrit.khawplum       #    "
echo -e "${RED} =============== OS-32 & 64-bit =================    "
echo -e "${GREEN} ไอพีเซิฟ: $IP "
echo -e "${NC} "
	echo "OpenVPN, Squid Proxy, Nginx .....Install finish."
	echo "IP Server : $IP"
	echo "Port Server : $PORT"
	if [[ "$PROTOCOL" = 'udp' ]]; then
		echo "Protocal : UDP"
	elif [[ "$PROTOCOL" = 'tcp' ]]; then
		echo "Protocal : TCP"
	fi
	echo "IP Proxy   : $IP"
	echo "Port Proxy : 8080,3128"
	echo ""
	case $OPENVPNSYSTEM in

		echo "Download Config : root/$CLIENT.ovpn"
		;;
	esac
	echo ""
	echo "===================================================================="
	echo -e "ติดตั้งสำเร็จ... กรุณาพิมพ์คำสั่ง${YELLOW} m ${NC} เพื่อไปยังขั้นตอนถัดไป"
	echo "===================================================================="
	echo ""
	exit
