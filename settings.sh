#!/bin/bash

# Устанавливаем имя пользователя и пароль для Mosquitto
echo "Настройка Mosquitto. Создание пользователя IoT и пароля:"
read -s -p "Введите пароль для пользователя IoT: " password_mosquitto
echo
docker exec -it shuliak-mosquitto-1 mosquitto_passwd -c /mosquitto/config/password.txt IoT
sed -i "s/password = .*/password = \"$password_mosquitto\"/" ~/telegraf/conf/telegraf.conf

# Создаем файл конфигурации Mosquitto
cat > /home/shuliak/mosquitto/config/mosquitto.conf << EOSF
listener 1883
allow_anonymous false
password_file /mosquitto/config/password.txt
EOSF

# Перезапускаем контейнер Mosquitto
docker restart shuliak-mosquitto-1

# Node-red
# Запускаем скрипт nodered-docker-folder.sh и инициализируем Node-red
echo "Настройка Node-red"
docker exec -it --user=root shuliak-nodered-1 sh -c 'sed -i "s/^node-red:x:[0-9]*/node-red:x:1100/" /etc/passwd && sed -i "s/^node-red:x:[0-9]*:/node-red:x:1100:/" /etc/group'
docker exec -it --user=root shuliak-nodered-1 sh -c 'if ! grep -q "^shuliak:" /etc/group; then echo "shuliak:x:1000:" >> /etc/group; fi && if ! grep -q "^shuliak:" /etc/passwd; then echo "shuliak:x:1000:1000::/home/shuliak:/bin/ash" >> /etc/passwd; fi && mkdir -p /home/shuliak && chown shuliak:shuliak /home/shuliak && chmod 755 /home/shuliak'
docker exec -it shuliak-nodered-1 node-red-admin init

# Копируем файл настроек Node-red в другой каталог
docker exec shuliak-nodered-1 cat ~/.node-red/settings.js > ~/node-red/data/settings.js

# Перезапускаем контейнер Node-red
docker restart shuliak-nodered-1

# Запрашиваем у пользователя имя пользователя и пароль для InfluxDB
echo "Настройка InfluxDB"
read -p "Введите имя пользователя InfluxDB: " influx_user
read -s -p "Введите пароль для InfluxDB: " influx_password
echo

# Настраиваем базу данных InfluxDB с предоставленными данными
echo -e "0\ny" | docker exec -i shuliak-influxdb-1 influx setup -b IoT -u "$influx_user" -p "$influx_password" -o IoT

# Сохраняем токен авторизации InfluxDB в переменную
token=$(docker exec -it shuliak-influxdb-1 influx auth create --org IoT --description "$(id -un) token" --operator | awk 'NR > 1 {print $4}')

# Выводим токен пользователю
echo "Токен доступа: $token"

# Записываем переменную 'token' в файл
echo "$token" > token.txt

# Заменяем значение токена в файле telegraf.conf
sed -i 's/token =.*/token = "'"$token"'" /' ~/telegraf/conf/telegraf.conf

# Перезапускаем контейнер Telegraf
docker restart shuliak-telegraf-1

# Надстройка Certbot
docker exec -it shuliak-certbot-1 sh -c 'certbot -d *.gb-study-shuliak.ru -d gb-study-shuliak.ru --manual --preferred-challenges dns certonly --server https://acme-v02.api.letsencrypt.org/directory'
