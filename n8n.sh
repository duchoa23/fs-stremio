#!/bin/bash

# Cập nhật hệ thống
sudo apt update && sudo apt upgrade -y

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
      POSTGRES_USER: n8n
      POSTGRES_PASSWORD: n8npassword
      POSTGRES_DB: n8n
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
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=yourpassword
      - DB_TYPE=postgresdb
      - DB_POSTGRESDB_HOST=postgres
      - DB_POSTGRESDB_PORT=5432
      - DB_POSTGRESDB_DATABASE=n8n
      - DB_POSTGRESDB_USER=n8n
      - DB_POSTGRESDB_PASSWORD=n8npassword
      - N8N_HOST=n8n.vokieumy.com
      - N8N_PROTOCOL=https
      - N8N_PORT=5678
      - WEBHOOK_URL=https://n8n.vokieumy.com/
      - N8N_EDITOR_BASE_URL=https://n8n.vokieumy.com/
      - N8N_PUBLIC_API_HOST=n8n.vokieumy.com
      - VUE_APP_URL_BASE_API=https://n8n.vokieumy.com/
    depends_on:
      - postgres
    volumes:
      - n8n_data:/home/node/.n8n

volumes:
  postgres_data:
  n8n_data:
EOL

# khởi chạy n8n và postgresql
docker-compose up -d

# cài đặt nginx
sudo apt install -y nginx

# Tạo file cấu hình Nginx cho n8n
cat <<EOL > /etc/nginx/sites-available/n8n
server {
    server_name n8n.vokieumy.com;

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
    server_name n8n.vokieumy.com;
    return 301 https://\$host\$request_uri;
}
EOL

# Tạo symlink để kích hoạt site
ln -s /etc/nginx/sites-available/n8n /etc/nginx/sites-enabled/

# Kiểm tra và reload Nginx
sudo nginx -t && sudo systemctl restart nginx

# cài đặt SSL
sudo apt install -y certbot python3-certbot-nginx
sudo certbot --nginx -d n8n.vokieumy.com
