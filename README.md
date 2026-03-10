# Cài docker cho ubuntu :

- 

# Cài docker cho debian :
-

# Đối với file Update.SH :
``` sudo ./update.sh 3 "proxy ở đây" ```
thay số 3 thành số của stack hay compose muốn thay. Còn proxy thì thay bằng định dạng của tun2sock
# Đối với file Start.SH :
Tạo file proxies.txt . Dán proxy vào với dịnh dạng của tun2sock. Rồi chạy thôi
``` chmod +x start.sh && sudo ./start.sh ```
# Đối với file Stop.SH ( Này sẽ dừng toàn bộ stack):
``` chmod +x stop.sh && sudo ./stop.sh ```
# Muốn dừng stack cụ thể theo số thì dùng command :
``` sudo docker compose -p "proxy-stack-SỐ BẠN MUỐN" down ```
# Dừng chay toàn bộ ( Kể cả không phải docker liên quan tới traff ) : 
``` sudo docker stop $(sudo docker ps -a -q) &&  sudo docker rm $(sudo docker ps -a -q) ```
``` docker stop $(docker ps -aq --filter "name=vpn_sanjose") && docker rm $(docker ps -aq --filter "name=vpn_sanjose") ```
# Cài docker check health tự động restart :
`` docker run -d --name autoheal --restart=always --env AUTOHEAL_CONTAINER_LABEL=all -v /var/run/docker.sock:/var/run/docker.sock  willfarrell/autoheal ``
# Tính số docker đang chạy theo tên có chứa :
``` docker ps -a --filter "name=spain" -q | wc -l ```
