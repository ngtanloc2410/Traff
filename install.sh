apk update && apk add zram-init crun docker && \
mkdir -p /etc/docker && \
cat <<EOF > /etc/conf.d/zram-init
num_devices=1
type0="swap"
flag0="100"
opts0="comp_algorithm=zstd"
size0="16383"
type1=""
EOF
cat <<EOF > /etc/docker/daemon.json
{
  "default-runtime": "crun",
  "runtimes": {
    "crun": {
      "path": "/usr/bin/crun"
    }
  }
}
EOF
cat <<EOF > /etc/sysctl.d/99-thousands-containers.conf
kernel.pid_max=100000
fs.file-max=2097152
vm.max_map_count=262144
EOF
sysctl -p /etc/sysctl.d/99-thousands-containers.conf && \
rc-update add zram-init default && \
rc-update add docker default && \
rc-service zram-init restart && \
rc-service docker restart && \
echo "--- CẤU HÌNH HOÀN TẤT ---" && \
zramctl && docker info | grep "Runtime"
