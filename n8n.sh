#!/bin/bash

set -e  # Dừng script nếu có lệnh nào lỗi

# Hỏi người dùng để điền thông tin
read -p "Nhập domain của bạn: " DOMAIN
read -p "Nhập email của bạn: " EMAIL
read -p "Nhập n8n user: " N8N_USER
read -s -p "Nhập n8n password: " N8N_PASS
echo
read -p "Nhập tên database: " DB_NAME
read -p "Nhập user database: " DB_USER
read -s -p "Nhập mật khẩu database: " DB_PASS
echo

# Cài đặt các gói cần thiết
sudo apt install -y ca-certificates curl gnupg

# Tạo thư mục keyrings nếu chưa có
sudo install -m 0755 -d /etc/apt/keyrings

# Thêm khóa GPG của Docker
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo tee /etc/apt/keyrings/docker.asc > /dev/null
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Thêm repository của Docker
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

# Cập nhật danh sách package
sudo apt update

# Cài đặt Docker và Docker Compose
sudo apt install -y docker-compose

# Bật Docker khởi động cùng hệ thống và khởi động Docker ngay lập tức
sudo systemctl enable docker
sudo systemctl start docker

# Chờ Docker khởi động hoàn tất
sleep 5
sudo systemctl is-active --quiet docker || { echo "Docker không khởi động được!"; exit 1; }

# Tạo thư mục cho n8n và chuyển vào thư mục đó
mkdir -p ~/n8n_data && cd ~/n8n_data

# Tạo file docker-compose.yml và nhập nội dung vào
cat <<EOL > docker-compose.yml
version: "3.8"

services:
  postgres:
    image: postgres:15
    container_name: postgres
    restart: always
    environment:
      POSTGRES_USER: $DB_USER
      POSTGRES_PASSWORD: $DB_PASS
      POSTGRES_DB: $DB_NAME
    volumes:
      - postgres_data:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  n8n:
    image: n8nio/n8n
    container_name: n8n
    restart: always
    ports:
      - "5678:5678"
    environment:
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=$N8N_USER
      - N8N_BASIC_AUTH_PASSWORD=$N8N_PASS
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=$DB_NAME
      - DB_POSTGRESDB_USER=$DB_USER
      - DB_POSTGRESDB_PASSWORD=$DB_PASS
      - N8N_HOST=$DOMAIN
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://$DOMAIN/
      - N8N_EDITOR_BASE_URL=https://$DOMAIN/
      - N8N_PUBLIC_API_HOST=$DOMAIN
      - VUE_APP_URL_BASE_API=https://$DOMAIN/
    depends_on:
      - postgres
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  postgres_data:
  n8n_data:
EOL

# Khởi chạy n8n và postgresql
docker-compose up -d

# Chờ container khởi động
sleep 10
docker ps | grep n8n || { echo "n8n container không chạy!"; exit 1; }

# Cài đặt Nginx
sudo apt install -y nginx

# Tạo file cấu hình Nginx cho n8n
cat <<EOL > /etc/nginx/sites-available/n8n
server {
    server_name $DOMAIN;

    location / {
        proxy_pass http://localhost:5678;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;

        # Hỗ trợ WebSocket
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "Upgrade";

        # Giảm timeout tránh mất kết nối
        proxy_connect_timeout 600;
        proxy_send_timeout 600;
        proxy_read_timeout 600;
        send_timeout 600;
    }
}

server {
    listen 80;
    server_name $DOMAIN;
    return 301 https://\$host\$request_uri;
}
EOL

# Tạo symlink để kích hoạt site
ln -sf /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/

# Kiểm tra và reload Nginx
sudo nginx -t && sudo systemctl restart nginx

# Chờ Nginx khởi động
sleep 5
sudo systemctl is-active --quiet nginx || { echo "Nginx không khởi động được!"; exit 1; }

# Cài đặt SSL
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d $DOMAIN --non-interactive --agree-tos -m $EMAIL

# Hoàn tất
echo "Cài đặt hoàn tất!"
