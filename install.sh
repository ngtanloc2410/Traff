apk update && \
apk add zram-init crun docker unzip nano screen jq && \
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

modprobe tun && \
sysctl -w fs.inotify.max_user_watches=4194304 && \
sysctl -w fs.inotify.max_user_instances=8192 && \
sysctl -w fs.inotify.max_queued_events=65536 && \
sysctl fs.inotify && \
sysctl -w net.ipv4.neigh.default.gc_thresh1=1024 && \
sysctl -w net.ipv4.neigh.default.gc_thresh2=4096 && \
sysctl -w net.ipv4.neigh.default.gc_thresh3=8192 && \
rc-service docker start && \
rc-update add docker boot && \
docker --version && \
rc-update add zram-init default && \
rc-update add docker default && \
rc-service zram-init restart && \
rc-service docker restart && \
echo "--- CẤU HÌNH HOÀN TẤT ---" && \
zramctl && docker info | grep "Runtime"
