# Cài docker cho ubuntu :

- 

# Cài docker cho debian :
-

# Đối với file Update.SH :
```bash
sudo ./update.sh 3 "proxy ở đây"
```
thay số 3 thành số của stack hay compose muốn thay. Còn proxy thì thay bằng định dạng của tun2sock
# Đối với file Start.SH :
Tạo file proxies.txt . Dán proxy vào với dịnh dạng của tun2sock. Rồi chạy thôi
```bash
chmod +x start.sh && sudo ./start.sh
```
# Đối với file Stop.SH ( Này sẽ dừng toàn bộ stack):
```bash
chmod +x stop.sh && sudo ./stop.sh
```
# Muốn dừng stack cụ thể theo số thì dùng command :
```bash
sudo docker compose -p "proxy-stack-SỐ BẠN MUỐN" down 
```
# Dừng chay toàn bộ ( Kể cả không phải docker liên quan tới traff ) : 
```bash
sudo docker stop $(sudo docker ps -a -q) &&  sudo docker rm $(sudo docker ps -a -q)
```

```bash
docker stop $(docker ps -aq --filter "name=vpn_sanjose") && docker rm $(docker ps -aq --filter "name=vpn_sanjose")
```
# Cài docker check health tự động restart :
```bash
docker run -d --name autoheal --restart=always --env AUTOHEAL_CONTAINER_LABEL=all -v /var/run/docker.sock:/var/run/docker.sock  willfarrell/autoheal
```
# Tính số docker đang chạy theo tên có chứa :
```bash 
docker ps -a --filter "name=spain" -q | wc -l
```
# Lấy địa chỉ ip hiện tại :
```bash
docker exec -it 4adc4a914e82 sh -c 'curl ipinfo.io'
```
# Tăng limit linux để chạy được nhiều process ( nhiều container ) :
```bash
sudo sysctl -w fs.inotify.max_user_watches=4194304 && sudo sysctl -w fs.inotify.max_user_instances=8192 && sudo sysctl -w fs.inotify.max_queued_events=65536 && sysctl fs.inotify && sudo sysctl -w net.ipv4.neigh.default.gc_thresh1=1024 && sudo sysctl -w net.ipv4.neigh.default.gc_thresh2=4096 && sudo sysctl -w net.ipv4.neigh.default.gc_thresh3=8192
```
# Chạy full region US :
```bash
./deploy.sh us_idaho-pf; ./deploy.sh us_kansas-pf; ./deploy.sh us_minnesota-pf; ./deploy.sh us_oregon-pf; ./deploy.sh us-wilmington; ./deploy.sh us_arkansas-pf; ./deploy.sh us_mississippi-pf; ./deploy.sh us_oklahoma-pf; ./deploy.sh us_north_carolina-pf; ./deploy.sh us_michigan-pf; ./deploy.sh us_alabama-pf; ./deploy.sh us_missouri-pf; ./deploy.sh us_wyoming-pf; ./deploy.sh us_virginia-pf; ./deploy.sh us_north_dakota-pf; ./deploy.sh us_south_dakota-pf; ./deploy.sh us_wisconsin-pf; ./deploy.sh us_vermont-pf; ./deploy.sh us_alaska-pf; ./deploy.sh us_iowa-pf; ./deploy.sh us_new_mexico-pf; ./deploy.sh us_south_carolina-pf; ./deploy.sh us_maine-pf; ./deploy.sh us-baltimore; ./deploy.sh us_massachusetts-pf; ./deploy.sh us_louisiana-pf; ./deploy.sh us_west_virginia-pf; ./deploy.sh us_ohio-pf; ./deploy.sh us_rhode_island-pf; ./deploy.sh us_nebraska-pf
```
# Chạy full region EU : 
```bash
./deploy.sh de_germany-so; ./deploy.sh fi_2; ./deploy.sh uk_southampton; ./deploy.sh belgium; ./deploy.sh sweden; ./deploy.sh lu; ./deploy.sh liechtenstein; ./deploy.sh ua; ./deploy.sh monaco; ./deploy.sh nl_netherlands-so; ./deploy.sh spain; ./deploy.sh uk_2; ./deploy.sh no; ./deploy.sh swiss; ./deploy.sh ba; ./deploy.sh montenegro; ./deploy.sh al; ./deploy.sh zagreb; ./deploy.sh greenland; ./deploy.sh man; ./deploy.sh md; ./deploy.sh sweden_2; ./deploy.sh uk_manchester; ./deploy.sh nl_amsterdam; ./deploy.sh denmark; ./deploy.sh poland; ./deploy.sh italy_2; ./deploy.sh georgia; ./deploy.sh lt; ./deploy.sh lv; ./deploy.sh rs; ./deploy.sh denmark_2; ./deploy.sh uk; ./deploy.sh czech; ./deploy.sh france; ./deploy.sh hungary; ./deploy.sh ee; ./deploy.sh pt; ./deploy.sh sk; ./deploy.sh cyprus; ./deploy.sh ad; ./deploy.sh italy
```
# FastV install command :
```bash
wget https://raw.githubusercontent.com/ngtanloc2410/Locne/refs/heads/main/Fast/deploy.sh && chmod +x deploy.sh && apt install unzip -y && wget https://github.com/ngtanloc2410/Locne/releases/download/tag/serverListTCP.zip && unzip serverListTCP.zip && wget https://raw.githubusercontent.com/ngtanloc2410/Locne/refs/heads/main/Fast/vpn.txt && clear
```
