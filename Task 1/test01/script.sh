#!/bin/bash

# Ждем, пока apt освободится
while [[ `ps aux | grep -i apt | wc -l` != 1 ]] ; do
    echo 'apt is locked by another process.'
    sleep 15
done
echo 'apt is free. Let`s continue.'

echo -e "\n------Set time------"
region=Europe
city=Moscow
RESULT=`timedatectl | grep " Time zone" | awk '{print $3}'`
if [[ "$RESULT" == "$region/$city" ]]; then
    echo 'Time zone is already correct.'
else
    timedatectl set-timezone $region/$city
    echo 'Time zone corrected.'
fi
echo "------Finish setting time------"

echo -e "\n------Set locale------"
locale=en_US.UTF-8
lc=C.UTF-8
RESULT=`locale | grep LC_ALL=$lc`
if [[ "$RESULT" == "LC_ALL=$lc" ]] ; then
    echo 'Locale is set already.'
else
    locale-gen $locale
    update-locale LC_ALL=$lc
    echo 'Locale is set.'
fi
echo "------Finish setting locale------"

echo -e "\n------Change ssh port and set root login deny------"
old_ssh=22
new_ssh=2498
sed -i "s/^#\?Port .*/Port $new_ssh/g" /etc/ssh/sshd_config
sed -i "s/^#\?PermitRootLogin .*/PermitRootLogin no/g" /etc/ssh/sshd_config
systemctl disable --now ssh.socket
systemctl enable --now ssh.service
echo 'SSH is configured.'
echo "------Finish setting ssh port and root permissions------"

echo -e "\n------Create serviceuser------"
new_user=serviceuser
RESULT=`awk -F: '{ print $1}' /etc/passwd | grep $new_user`
if [[ "$RESULT" == "$new_user" ]] ; then
    echo 'User is already created.'
else
    useradd -m -s /bin/bash $new_user
    echo "$new_user:$new_user" | chpasswd
    usermod -aG sudo $new_user
    echo "$new_user ALL=(ALL) NOPASSWD: /bin/systemctl start *, /bin/systemctl stop *, /bin/systemctl restart *" > /etc/sudoers.d/$new_user
    chmod 440 /etc/sudoers.d/$new_user
    echo "$new_user is created."
fi
echo "------End of user creating and configuring------"

echo -e "\n------Install NGINX------"
package=nginx
if systemctl is-active --quiet $package ; then
    echo 'NGINX already installed and running.'
else
    apt update
    apt install $package -y
    systemctl start $package
    systemctl enable $package
    echo "$package is installed."
fi
echo "------Installed NGINX------"

echo -e "\n------Install Monit------"
package=monit
if systemctl is-active --quiet $package ; then
    echo "Monit already installed and running."
else
    apt update
    apt install $package -y
    systemctl enable $package
    echo "$package is installed."
fi

# Настройка Monit (выполняется всегда, независимо от того, был ли Monit запущен)
cat > /etc/monit/conf.d/httpd << 'MONITCONF'
set httpd port 2812 and
    use address localhost
    allow localhost
    allow devops:test
MONITCONF

# Настройка Nginx как proxy к Monit
cp /etc/nginx/sites-available/default /etc/nginx/sites-available/default.back
[ -L /etc/nginx/sites-enabled/default ] && unlink /etc/nginx/sites-enabled/default
cat > /etc/nginx/sites-available/monit << 'NGINXCONF'
server {
    listen 80;
    server_name 127.0.0.1;
    location / {
        proxy_pass http://127.0.0.1:2812;
        proxy_set_header Host $host;
    }
}
NGINXCONF
ln -sf /etc/nginx/sites-available/monit /etc/nginx/sites-enabled/monit
nginx -s reload

monit reload
echo "------Installed Monit------"

echo -e "\n------UFW configure------"
RESULT=`ufw status | grep Status: | awk '{print $2}'`
if [[ "$RESULT" == "active" ]] ; then
    echo 'UFW is start and configured already.'
else
    ufw allow 2498/tcp
    ufw allow 80/tcp
    ufw default deny incoming
    ufw default allow outgoing
    ufw --force enable
    echo 'UFW is configured.'
fi
echo "------UFW configured------"
