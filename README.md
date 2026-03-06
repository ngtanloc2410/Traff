Đối với file Update.SH :
- sudo ./update.sh 3 "proxy ở đây"
# thay số 3 thành số của stack hay compose muốn thay. Còn proxy thì thay bằng định dạng của tun2sock

Đối với file Start.SH :
- Tạo file proxies.txt . Dán proxy vào với dịnh dạng của tun2sock. Rồi chạy thôi
- chmod +x start.sh && sudo ./start.sh

Đối với file Stop.SH ( Này sẽ dừng toàn bộ stack):
- chmod +x stop.sh && sudo ./stop.sh

Muốn dừng stack cụ thể theo số thì dùng command :
- sudo docker compose -p "proxy-stack-SỐ BẠN MUỐN" down
