#!/bin/bash

# 定义颜色变量
YELLOW='\e[33m'
BLUE='\e[34m'
RED='\e[31m'
RESET='\e[0m'

echo -e "${YELLOW}开始部署项目https://github.com/theresaarcher/hysteria${RESET}"

# 检查 docker-compose 版本
DOCKER_COMPOSE_VERSION=$(docker-compose --version | grep -Eo "[0-9]+\.[0-9]+\.[0-9]+")
REQUIRED_VERSION="1.27.0"

if [[ "$(printf '%s\n' "$REQUIRED_VERSION" "$DOCKER_COMPOSE_VERSION" | sort -V | head -n1)" != "$REQUIRED_VERSION" ]]; then
    echo -e "${RED}错误: docker-compose 版本过低。请升级 docker-compose 到 $REQUIRED_VERSION 以上版本。${RESET}"
    exit 1
fi

echo -e "当前 docker-compose 版本:${YELLOW} $DOCKER_COMPOSE_VERSION${RESET}"
echo -e "要求的最低版本:${YELLOW} $REQUIRED_VERSION${RESET}"

# 询问用户是否继续执行脚本
read -p "继续执行脚本吗？(y/n) [y]: " continueExecution
continueExecution=${continueExecution:-y}

if [[ "$continueExecution" != "y" ]]; then
    echo "脚本已中止。"
    exit 0
fi

cat >docker-compose.yaml <<EOL
version: "3.9"
services:
  hysteria:
    image: ghcr.io/theresaarcher/hysteria:latest
    container_name: hysteria
    restart: always
    network_mode: "host"
    volumes:
      - acme:/acme
      - ./hysteria.yaml:/etc/hysteria.yaml
      - ./tls/fullchain.crt:/etc/hysteria/tls.crt
      - ./tls/private.pem:/etc/hysteria/tls.key
    command: ["server", "-c", "/etc/hysteria.yaml"]
volumes:
  acme:
EOL

echo "Step 2: 生成docker-compose.yaml文件"

mkdir -p tls
echo "Step 3: 创建tls文件夹"

read -p "Step 4: 请输入面板api地址(带https://): " panelHost
read -p "Step 5: 请输入面板节点密钥: " apiKey
read -p "Step 6: 请输入Hysteria2节点ID: " nodeID
read -p "Step 7: 请输入流量监听端口 (默认7653): " listenPort
listenPort=${listenPort:-7653}
read -p "Step 8: 是否禁用UDP？(y/n) [n]: " disableUDP
disableUDP=${disableUDP:-n}

cat >hysteria.yaml <<EOL
v2raysocks:
  apiHost: $panelHost
  apiKey: $apiKey
  nodeID: $nodeID
tls:
  type: tls
  cert: /etc/hysteria/tls.crt
  key: /etc/hysteria/tls.key
auth:
  type: v2raysocks
trafficStats:
  listen: 127.0.0.1:$listenPort
outbounds:
  - name: defob
    type: direct
acl: 
  inline: 
    - reject(10.0.0.0/8)
    - reject(172.16.0.0/12)
    - reject(192.168.0.0/16)
    - reject(127.0.0.0/8)
    - reject(fc00::/7)
disableUDP: $([[ "$disableUDP" == "y" ]] && echo "true" || echo "false")
EOL

echo "Step 9: 生成hysteria.yaml文件"

# 下载证书文件
curl -o tls/fullchain.crt "$panelHost?&token=$apiKey&node_id=$nodeID&act=get_certificate"
if [ $? -ne 0 ]; then
    echo -e "${RED}错误: 无法下载 fullchain.crt 文件。${RESET}"
    exit 1
fi

echo "Step 10: 在tls目录中下载fullchain.crt文件"

# 下载私钥文件
curl -o tls/private.pem "$panelHost?&token=$apiKey&node_id=$nodeID&act=get_key"
if [ $? -ne 0 ]; then
    echo -e "${RED}错误: 无法下载 private.pem 文件。${RESET}"
    exit 1
fi

echo "Step 11: 在tls目录中下载private.pem文件"

echo "Step 12: 正在尝试启动docker"
chmod 777 docker-compose.yaml
chmod 777 hysteria.yaml
docker-compose up -d

echo -e "${YELLOW}1、请自行运行命令${BLUE}docker-compose logs${YELLOW}验证是否成功启动docker${RESET}"
echo -e "${YELLOW}2、证书为管理面板默认设置中的证书，因此你需要先在默认设置中设置证书和key${RESET}"
echo -e "${YELLOW}3、若要使用其他证书，请替换${BLUE}'/脚本所在目录/tls'${YELLOW}文件夹下的证书文件并在脚本所在目录执行以下命令重新部署后端${RESET}"
echo -e "${BLUE}docker-compose down${RESET}"
echo -e "${BLUE}docker-compose up -d${RESET}"
echo -e "${YELLOW}重新部署后执行以下命令查看是否报错${RESET}"
echo -e "${BLUE}docker-compose logs${RESET}"
