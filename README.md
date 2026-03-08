# Cài docker cho ubuntu :

- 

# Cài docker cho debian :

- sudo apt update && sudo apt install ca-certificates curl && sudo install -m 0755 -d /etc/apt/keyrings && sudo curl -fsSL https://download.docker.com/linux/debian/gpg -o /etc/apt/keyrings/docker.asc && sudo chmod a+r /etc/apt/keyrings/docker.asc && sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/debian
Suites: $(. /etc/os-release && echo "$VERSION_CODENAME")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF && sudo apt update && sudo apt install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin && sudo systemctl status docker

# Đối với file Update.SH :
- sudo ./update.sh 3 "proxy ở đây"
thay số 3 thành số của stack hay compose muốn thay. Còn proxy thì thay bằng định dạng của tun2sock

# Đối với file Start.SH :
Tạo file proxies.txt . Dán proxy vào với dịnh dạng của tun2sock. Rồi chạy thôi
- chmod +x start.sh && sudo ./start.sh

# Đối với file Stop.SH ( Này sẽ dừng toàn bộ stack):
- chmod +x stop.sh && sudo ./stop.sh

# Muốn dừng stack cụ thể theo số thì dùng command :
- sudo docker compose -p "proxy-stack-SỐ BẠN MUỐN" down
