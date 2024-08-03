# Получаем права SuperUser в системе
sudo su

#Обновляем конфигурацию загрузчика
cat > /etc/default/grub <<EOF
GRUB_DEFAULT=0
GRUB_TIMEOUT=0
GRUB_DISTRIBUTOR=`lsb_release -i -s 2> /dev/null || echo Debian`
GRUB_CMDLINE_LINUX_DEFAULT="quiet text mitigations=off nowatchdog processor.ignore_ppc=1 cpufreq.default_governor=performance debug=-1"
GRUB_CMDLINE_LINUX=""
GRUB_DISABLE_LINUX_RECOVERY=true
GRUB_DISABLE_OS_PROBER=true
GRUB_TERMINAL=console
EOF

#Настраиваем систему и перезагружаем, если все ок
echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf && \
echo "net.ipv4.conf.all.forwarding=1" >> /etc/sysctl.conf && \
sysctl -p /etc/sysctl.conf && \
systemctl stop cron && \
systemctl disable cron && \
systemctl set-default multi-user.target && \
mkdir -m 0755 -p /etc/apt/keyrings && \
apt install -y ca-certificates curl wget gnupg gnupg2 systemd-timesyncd htop lm-sensors lsb-release unzip && \
curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg && \
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null && \
sudo wget -qO- https://repo.mosquitto.org/debian/mosquitto-repo.gpg.key | gpg --dearmor -o /etc/apt/keyrings/mosquitto-repo.gpg && \
sudo wget -O /etc/apt/sources.list.d/mosquitto-bookworm.list https://repo.mosquitto.org/debian/mosquitto-bookworm.list
apt-get update && \
apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin mosquitto-clients=2.0.18-0mosquitto1~bookworm1 && \
sed -i 's/#NTP=/NTP=1.debian.pool.ntp.org/' /etc/systemd/timesyncd.conf && \
systemctl restart systemd-timesyncd && \
update-grub && \
reboot

______________________________________________________

# Создаем скрипт автоматической установки Docker и необходимых файлов конфигураций
nano install.sh

#!/bin/bash

# Получаем IP адрес машины, на которой запускается скрипт
vm_ip=$(ip a | awk '/inet / && !/127.0.0.1/ {gsub(/\/.*/, "", $2); print $2; exit}')

#Выводим информацию о Docker и IP
docker compose version && \
docker -v && \
echo "IP Машины: "$vm_ip

#Проверяем, является ли пользователь root'ом
if [ "$EUID" -eq 0 ]; then
    echo "Этот скрипт не должен запускаться с правами root. Запустите его от имени обычного пользователя."
    exit 1
fi

# Получаем имя текущего пользователя
current_user=$USER

# Создаем необходимые каталоги для docker-compose.yml
user_home=$(eval echo ~$current_user)
mkdir -p $user_home

# Генерируем уникальные порты для пользователя
mosquitto_port=1883
influxdb_port=8086
grafana_port=3000
nodered_port=1880
telegraf_port1=8092
telegraf_port2=8094
telegraf_port3=8125
nginx_port1=80
nginx_port2=443

# Задаем доменное имя для конфигурации nginx без www. и без .ru
read -p "Введите доменное имя для конфигурации nginx без www. и без .ru: " nginx_domain
read -p "Введите среднюю часть доменного имени для ваших сервисов из инициалов и номера группы, например, gvi-4538 (для grafana-gvi-4538.gb-iot.ru и др.): " nginx_3rd_domain

# Задаем данные для подключения сервиса DDNS No-IP
echo -n "Введите username с сервиса NO-IP.com : "
read inadyn_username
echo -n "Введите password с сервиса NO-IP.com : "
read -s inadyn_password
echo
echo -n "Введите hostname с сервиса NO-IP.com : "
read inadyn_hostname

# Создаем docker-compose.yml для текущего пользователя
cat > "$user_home/docker-compose.yml" << EOF
version: '3'
services:
  mosquitto:
    image: eclipse-mosquitto
    network_mode: bridge
    user: $(id -u $current_user):$(id -g $current_user)
    ports:
      - "$mosquitto_port:1883"
    volumes:
      - "$user_home/mosquitto/config:/mosquitto/config"
      - "$user_home/mosquitto/data:/mosquitto/data"
      - "$user_home/mosquitto/log:/mosquitto/log"
    environment:
      - TZ=Europe/Minsk
    restart: unless-stopped

  telegraf:
    image: telegraf:alpine
    network_mode: bridge
    user: $(id -u $current_user):$(id -g $current_user)
    volumes:
      - "$user_home/telegraf/conf:/etc/telegraf/telegraf.d"
    ports:
      - "$telegraf_port1:8092/tcp"
      - "$telegraf_port1:8092/udp"
      - "$telegraf_port2:8094/tcp"
      - "$telegraf_port2:8094/udp"
      - "$telegraf_port3:8125/tcp"
      - "$telegraf_port3:8125/udp"
    environment:
      - TZ=Europe/Minsk
    depends_on:
      - mosquitto
      - influxdb
    restart: unless-stopped

  influxdb:
    image: influxdb:alpine
    network_mode: bridge
    user: $(id -u $current_user):$(id -g $current_user)
    ports:
      - "$influxdb_port:8086"
    volumes:
      - "$user_home/influxdb/data:/var/lib/influxdb2"
      - "$user_home/influxdb/conf:/etc/influxdb"
      - "$user_home/influxdb/engine:/var/lib/influxdb2/engine"
    environment:
      - TZ=Europe/Minsk
    restart: unless-stopped

  grafana:
    image: grafana/grafana
    network_mode: bridge
    user: $(id -u $current_user):$(id -g $current_user)
    volumes:
      - "$user_home/grafana/data:/var/lib/grafana"
      - "$user_home/grafana/conf:/etc/grafana"
      - "$user_home/grafana/log:/var/log/grafana"
    ports:
      - "$grafana_port:3000"
    environment:
      - PUID=$(id -u $current_user)
      - PGID=$(id -g $current_user)
      - TZ=Europe/Minsk
    restart: unless-stopped

  nodered:
    image: nodered/node-red:latest-minimal
    network_mode: bridge
    user: $(id -u $current_user):$(id -g $current_user)
    volumes:
      - "$user_home/node-red/data:/data"
    ports:
      - "$nodered_port:1880"
    environment:
      - TZ=Europe/Minsk
    restart: unless-stopped

  nginx:
    image: nginx:mainline-alpine-slim
    network_mode: bridge
    volumes:
      - "$user_home/nginx/conf:/etc/nginx/conf.d"
      - "$user_home/nginx/html:/usr/share/nginx/html"
      - "$user_home/certbot/conf:/etc/letsencrypt"
      - "$user_home/certbot/www:/var/www/certbot"
    environment:
      - TZ=Europe/Minsk
    ports:
      - "$nginx_port1:80"
      - "$nginx_port2:443"
    command: '/bin/sh -c ''while :; do sleep 24h & wait \$\${!}; nginx -s reload; done & nginx -g "daemon off;"'''
    restart: unless-stopped

  certbot:
    image: certbot/certbot:latest
    network_mode: bridge
    volumes:
      - "$user_home/certbot/conf:/etc/letsencrypt"
      - "$user_home/certbot/www:/var/www/certbot"
    environment:
      - TZ=Europe/Moscow
    depends_on:
      - nginx
    entrypoint: "/bin/sh -c 'trap exit TERM; while :; do certbot renew; sleep 24h & wait \$\${!}; done;'"
    restart: unless-stopped

  inadyn:
    image: troglobit/inadyn:latest
    restart: unless-stopped
    network_mode: bridge
    volumes:
      - "$user_home/inadyn/inadyn.conf:/etc/inadyn.conf"
    environment:
      - TZ=Europe/Moscow
EOF

# Создаем необходимые каталоги с разрешениями только для текущего пользователя
mkdir -m 755 -p $user_home/mosquitto/config
mkdir -m 755 -p $user_home/mosquitto/data
mkdir -m 755 -p $user_home/mosquitto/log
mkdir -m 755 -p $user_home/influxdb/data
mkdir -m 755 -p $user_home/influxdb/conf
mkdir -m 755 -p $user_home/influxdb/engine
mkdir -m 755 -p $user_home/telegraf/conf
mkdir -m 755 -p $user_home/grafana/data
mkdir -m 755 -p $user_home/grafana/conf
mkdir -m 755 -p $user_home/grafana/log
mkdir -m 755 -p $user_home/node-red/data
mkdir -m 755 -p $user_home/nginx/conf
mkdir -m 755 -p $user_home/nginx/html/$nginx_domain.ru
mkdir -m 755 -p $user_home/certbot/conf
mkdir -m 755 -p $user_home/certbot/www
mkdir -m 755 -p $user_home/inadyn

# Создание конфигурационных файлов для созданного docker-compose.yml
# Создаем файлы конфигурации для Mosquitto для текущего пользователя
cat > "$user_home/mosquitto/config/mosquitto.conf" << EOF
listener 1883
EOF

# Создаем файлы конфигурации для Grafana для текущего пользователя
cat > "$user_home/grafana/conf/grafana.ini" << EOF
[server]
;http_port = 3000
EOF

# Создаем файлы конфигурации для Telegraf для текущего пользователя
cat > "$user_home/telegraf/conf/telegraf.conf" << EOF
# Конфигурация агента telegraf
[agent]
  interval = "3s"
  round_interval = true
  metric_batch_size = 1000
  metric_buffer_limit = 10000
  collection_jitter = "0s"
  flush_interval = "3s"
  flush_jitter = "0s"
  precision = ""
  hostname = ""
  omit_hostname = false

[[outputs.influxdb_v2]]
  urls = ["http://$vm_ip:$influxdb_port"]
  token = " "
  organization = "IoT"
  bucket = "IoT"

[[inputs.mqtt_consumer]]
  servers = ["tcp://$vm_ip:$mosquitto_port"]
  topics = ["#"]
  username = "IoT"
  password = "student"
  data_format = "value"
  data_type = "float"
EOF

# Создаем файлы конфигурации для inadyn для текущего пользователя
cat > "$user_home/inadyn/inadyn.conf" << EOF
# In-A-Dyn v2.0 configuration file format
period = 60
user-agent = Mozilla/5.0

provider no-ip.com {
    username    = $inadyn_username
    password    = $inadyn_password
    hostname    = $inadyn_hostname
}
EOF

# Создаем файлы конфигурации для NGINX для текущего пользователя
cat > "$user_home/nginx/conf/nginx.conf" << EOSF
server {
    listen 80;
    server_name $nginx_3rd_domain.$nginx_domain.ru;
    return 301 https://$nginx_3rd_domain.$nginx_domain.ru\$request_uri;
}

server {
    listen 80;
    server_name $nginx_3rd_domain.$nginx_domain.ru;
    root /usr/share/nginx/html/$nginx_domain.ru;
    
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}

server {
    listen 443 ssl http2;
    server_name $nginx_3rd_domain.$nginx_domain.ru;
    root /usr/share/nginx/html/$nginx_domain.ru;

    ssl_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/$nginx_domain.ru/privkey.pem;

    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}


####################################################################


# Grafana primary listener and redirect
server {
  listen 80;
  server_name grafana-$nginx_3rd_domain.$nginx_domain.ru;
  return 301 https://\$host\$request_uri;
}

# Grafana ssl config
server {
  listen 443 ssl http2;
  server_name grafana-$nginx_3rd_domain.$nginx_domain.ru;
  
  ssl_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
  ssl_trusted_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$nginx_domain.ru/privkey.pem;
  
  location / {
  http2_push_preload on;
  proxy_pass http://$vm_ip:$grafana_port;
  proxy_set_header Host \$host;
  proxy_set_header Connection "upgrade";
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  add_header X-Http-Version \$server_protocol;
  proxy_buffering on;
  proxy_buffer_size 8k;
  proxy_buffers 2048 8k;
  }
}


####################################################################


# Influxdb primary listener and redirect
server {
  listen 80;
  server_name influxdb-$nginx_3rd_domain.$nginx_domain.ru;
  return 301 https://\$host\$request_uri;
}

# Influxdb ssl config
server {
  listen 443 ssl http2;
  server_name influxdb-$nginx_3rd_domain.$nginx_domain.ru;

  ssl_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
  ssl_trusted_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$nginx_domain.ru/privkey.pem;
  
  location / {
  http2_push_preload on;
  proxy_pass http://$vm_ip:$influxdb_port;
  proxy_set_header Host \$host;
  proxy_set_header Connection "upgrade";
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  add_header X-Http-Version \$server_protocol;
  proxy_buffering on;
  proxy_buffer_size 8k;
  proxy_buffers 2048 8k;
  }
}


####################################################################


# Nodered primary listener and redirect
server {
  listen 80;
  server_name nodered-$nginx_3rd_domain.$nginx_domain.ru;
  return 301 https://\$host\$request_uri;
}

# Nodered ssl config
server {
  listen 443 ssl http2;
  server_name nodered-$nginx_3rd_domain.$nginx_domain.ru;

  ssl_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
  ssl_trusted_certificate /etc/letsencrypt/live/$nginx_domain.ru/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/$nginx_domain.ru/privkey.pem;
    
  location / {
  http2_push_preload on;
  proxy_pass http://$vm_ip:$nodered_port;
  proxy_set_header Host \$host;
  proxy_set_header Connection "upgrade";
  proxy_set_header Upgrade \$http_upgrade;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  add_header X-Http-Version \$server_protocol;
  proxy_buffering on;
  proxy_buffer_size 8k;
  proxy_buffers 2048 8k;
  }
}
EOSF

# Создаем скрипт для настройки пользовательских параметров
cat > "$user_home/settings.sh" << EOF
#!/bin/bash

# Устанавливаем имя пользователя и пароль для Mosquitto
echo "Настройка Mosquitto. Создание пользователя IoT и пароля:"
read -s -p "Введите пароль для пользователя IoT: " password_mosquitto
echo
docker exec -it $current_user-mosquitto-1 mosquitto_passwd -c /mosquitto/config/password.txt IoT
sed -i "s/password = .*/password = \"\$password_mosquitto\"/" ~/telegraf/conf/telegraf.conf

# Создаем файл конфигурации Mosquitto
cat > $user_home/mosquitto/config/mosquitto.conf << EOSF
listener 1883
allow_anonymous false
password_file /mosquitto/config/password.txt
EOSF

# Перезапускаем контейнер Mosquitto
docker restart $current_user-mosquitto-1

# Node-red
# Запускаем скрипт nodered-docker-folder.sh и инициализируем Node-red
echo "Настройка Node-red"
docker exec -it --user=root $current_user-nodered-1 sh -c 'sed -i "s/^node-red:x:[0-9]*/node-red:x:1100/" /etc/passwd && sed -i "s/^node-red:x:[0-9]*:/node-red:x:1100:/" /etc/group'
docker exec -it --user=root $current_user-nodered-1 sh -c 'if ! grep -q "^$current_user:" /etc/group; then echo "$current_user:x:$(id -u $current_user):" >> /etc/group; fi && if ! grep -q "^$current_user:" /etc/passwd; then echo "$current_user:x:$(id -u $current_user):$(id -g $current_user)::/home/$current_user:/bin/ash" >> /etc/passwd; fi && mkdir -p /home/$current_user && chown $current_user:$current_user /home/$current_user && chmod 755 /home/$current_user'
docker exec -it $current_user-nodered-1 node-red-admin init

# Копируем файл настроек Node-red в другой каталог
docker exec $current_user-nodered-1 cat ~/.node-red/settings.js > ~/node-red/data/settings.js

# Перезапускаем контейнер Node-red
docker restart $current_user-nodered-1

# Запрашиваем у пользователя имя пользователя и пароль для InfluxDB
echo "Настройка InfluxDB"
read -p "Введите имя пользователя InfluxDB: " influx_user
read -s -p "Введите пароль для InfluxDB: " influx_password
echo

# Настраиваем базу данных InfluxDB с предоставленными данными
echo -e "0\ny" | docker exec -i $current_user-influxdb-1 influx setup -b IoT -u "\$influx_user" -p "\$influx_password" -o IoT

# Сохраняем токен авторизации InfluxDB в переменную
token=\$(docker exec -it $current_user-influxdb-1 influx auth create --org IoT --description "\$(id -un) token" --operator | awk 'NR > 1 {print \$4}')

# Выводим токен пользователю
echo "Токен доступа: \$token"

# Записываем переменную 'token' в файл
echo "\$token" > token.txt

# Заменяем значение токена в файле telegraf.conf
sed -i 's/token =.*/token = "'"\$token"'" /' ~/telegraf/conf/telegraf.conf

# Перезапускаем контейнер Telegraf
docker restart $current_user-telegraf-1

# Надстройка Certbot
docker exec -it $current_user-certbot-1 sh -c 'certbot -d *.$nginx_domain.ru -d $nginx_domain.ru --manual --preferred-challenges dns certonly --server https://acme-v02.api.letsencrypt.org/directory'
EOF


# Устанавливаем владельца и разрешения для созданных файлов конфигурации
chown $current_user:$current_user "$user_home/docker-compose.yml"
chown $current_user:$current_user "$user_home/mosquitto/config/mosquitto.conf"
chown $current_user:$current_user "$user_home/grafana/conf/grafana.ini"
chown $current_user:$current_user "$user_home/telegraf/conf/telegraf.conf"
chown $current_user:$current_user "$user_home/nginx/conf/nginx.conf"
chown $current_user:$current_user "$user_home/nginx/html/$nginx_domain.ru"
chown $current_user:$current_user "$user_home/inadyn/inadyn.conf"
chown $current_user:$current_user "$user_home/settings.sh"
chmod 755 "$user_home/docker-compose.yml"
chmod 755 "$user_home/mosquitto/config/mosquitto.conf"
chmod 755 "$user_home/grafana/conf/grafana.ini"
chmod 755 "$user_home/telegraf/conf/telegraf.conf"
chmod 755 "$user_home/nginx/conf/nginx.conf"
chmod 755 "$user_home/nginx/html/$nginx_domain.ru"
chmod 755 "$user_home/inadyn/inadyn.conf"
chmod 755 "$user_home/settings.sh"

# Проверяем, является ли текущий пользователь уже частью группы Docker
if groups $current_user | grep -q '\bdocker\b'; then
	echo "Пользователь '$current_user' уже частью группы Docker."
else
	sudo usermod -aG docker $current_user
	echo "Пользователь '$current_user' добавлен в группу Docker."
	# Применяем группу Docker для пользователя без перезапуска сеанса терминала
	newgrp docker
fi
______________________________________________________


bash install.sh

docker compose up -d

bash settings.sh

docker compose down

docker compose up -d

docker ps
