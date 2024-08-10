#!/bin/bash

# 设置版本号
current_version=20240810003

update_script() {
    # 指定URL
    update_url="https://raw.githubusercontent.com/breaddog100/artela/main/Artela.sh"
    file_name=$(basename "$update_url")

    # 下载脚本文件
    tmp=$(date +%s)
    timeout 10s curl -s -o "$HOME/$tmp" -H "Cache-Control: no-cache" "$update_url?$tmp"
    exit_code=$?
    if [[ $exit_code -eq 124 ]]; then
        echo "命令超时"
        return 1
    elif [[ $exit_code -ne 0 ]]; then
        echo "下载失败"
        return 1
    fi

    # 检查是否有新版本可用
    latest_version=$(grep -oP 'current_version=([0-9]+)' $HOME/$tmp | sed -n 's/.*=//p')

    if [[ "$latest_version" -gt "$current_version" ]]; then
        clear
        echo ""
        # 提示需要更新脚本
        printf "\033[31m脚本有新版本可用！当前版本：%s，最新版本：%s\033[0m\n" "$current_version" "$latest_version"
        echo "正在更新..."
        sleep 3
        mv $HOME/$tmp $HOME/$file_name
        chmod +x $HOME/$file_name
        exec "$HOME/$file_name"
    else
        # 脚本是最新的
        rm -f $tmp
    fi

}

# 检查并安装 Node.js 和 npm
function install_nodejs_and_npm() {
    if command -v node > /dev/null 2>&1; then
        echo "Node.js 已安装"
    else
        echo "Node.js 未安装，正在安装..."
        curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
        sudo apt-get install -y nodejs
    fi

    if command -v npm > /dev/null 2>&1; then
        echo "npm 已安装"
    else
        echo "npm 未安装，正在安装..."
        sudo apt-get install -y npm
    fi
}

# 检查Go环境
function check_go_installation() {
    if command -v go > /dev/null 2>&1; then
        echo "Go 环境已安装"
        return 0 
    else
        echo "Go 环境未安装，正在安装..."
        return 1 
    fi
}

# 节点安装功能
function install_node() {

    # 设置变量
    read -r -p "节点名称: " NODE_MONIKER
    export NODE_MONIKER=$NODE_MONIKER

    install_nodejs_and_npm

    # 更新和安装必要的软件
    sudo apt update && sudo apt upgrade -y
    sudo apt install -y curl iptables build-essential git wget jq make gcc nano tmux htop nvme-cli pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev lz4 snapd

    # 安装 Go
    if ! check_go_installation; then
        sudo rm -rf /usr/local/go
        curl -L https://go.dev/dl/go1.22.0.linux-amd64.tar.gz | sudo tar -xzf - -C /usr/local
        echo 'export PATH=$PATH:/usr/local/go/bin:$HOME/go/bin' >> $HOME/.bash_profile
        source $HOME/.bash_profile
        go version
    fi

    # 安装所有二进制文件
    cd $HOME
    git clone https://github.com/artela-network/artela
    cd artela
    #git checkout v0.4.8-rc8
    make install

    # 配置artelad
    artelad config chain-id artela_11822-1
    artelad init "$NODE_MONIKER" --chain-id artela_11822-1

    # 获取初始文件和地址簿
    curl -L https://snapshots-testnet.nodejumper.io/artela-testnet/genesis.json > $HOME/.artelad/config/genesis.json
    curl -L https://snapshots-testnet.nodejumper.io/artela-testnet/addrbook.json > $HOME/.artelad/config/addrbook.json

    # 配置节点
    PEERS="096d8b3a2fe79791ef307935e0b72afcf505b149@84.247.140.122:24656,a01a5d0015e685655b1334041d907ce2db51c02f@173.249.16.25:45656,8542e4e88e01f9c95db2cd762460eecad2d66583@155.133.26.10:26656,dd5d35fb496afe468dd35213270b02b3a415f655@15.235.144.20:30656,8510929e6ba058e84019b1a16edba66e880744e1@217.76.50.155:656,f16f036a283c5d2d77d7dc564f5a4dc6cf89393b@91.190.156.180:42656,6554c18f24455cf1b60eebcc8b311a693371881a@164.68.114.21:45656,301d46637a338c2855ede5d2a587ad1f366f3813@95.217.200.98:18656,ca8bce647088a12bc030971fbcce88ea7ffdac50@84.247.153.99:26656,a3501b87757ad6515d73e99c6d60987130b74185@85.239.235.104:3456,2c62fb73027022e0e4dcbdb5b54a9b9219c9b0c1@51.255.228.103:26687,fbe01325237dc6338c90ddee0134f3af0378141b@158.220.88.66:3456,fde2881b06a44246a893f37ecb710020e8b973d1@158.220.84.64:3456,12d057b98ecf7a24d0979c0fba2f341d28973005@116.202.162.188:10656,9e2fbfc4b32a1b013e53f3fc9b45638f4cddee36@47.254.66.177:26656,92d95c7133275573af25a2454283ebf26966b188@167.235.178.134:27856,2dd98f91eaea966b023edbc88aa23c7dfa1f733a@158.220.99.30:26680"
    sed -i 's|^persistent_peers *=.*|persistent_peers = "'$PEERS'"|' $HOME/.artelad/config/config.toml

    source $HOME/.bash_profile
    
    # create service
    sudo tee /etc/systemd/system/artelad.service > /dev/null << EOF
[Unit]
Description=Artela node service
After=network-online.target
[Service]
User=$USER
ExecStart=$(which artelad) start
Environment="LD_LIBRARY_PATH=$HOME/libs"
Restart=on-failure
RestartSec=10
LimitNOFILE=65535
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable artelad
    sudo systemctl restart artelad

    echo '部署完成...'
    
}

function setup_artelad_service {
    SERVICE_FILE="/etc/systemd/system/artelad.service"
    
    if [ -f "$SERVICE_FILE" ]; then
        #echo "Service file $SERVICE_FILE already exists. Exiting function."
        return
    else
        #echo "Service file $SERVICE_FILE does not exist. Proceeding with setup."

        # 删除 pm2 进程
        pm2 delete artelad

        # 创建 service 文件
        sudo tee "$SERVICE_FILE" > /dev/null << EOF
[Unit]
Description=Artela node service
After=network-online.target

[Service]
User=$USER
ExecStart=$(which artelad) start
Environment="LD_LIBRARY_PATH=$HOME/libs"
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable artelad
        sudo systemctl restart artelad

        #echo "Service file $SERVICE_FILE has been created."
    fi
}

# 服务状态
function check_service_status() {
    sudo systemctl status artelad
}

# 停止节点
function stop_node() {
    setup_artelad_service
    sudo systemctl stop artelad
}

# 启动节点
function start_node() {
    sudo systemctl start artelad
    setup_artelad_service
}

# 运行日志查询
function view_logs() {
    sudo journalctl -u artelad.service -f -o cat
}

# 卸载节点功能
function uninstall_node() {
    echo "确定要卸载节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            stop_node
            rm -rf $HOME/.artelad $HOME/artela 
            sudo rm -f $(which artelad) /etc/systemd/system/artelad.service 
            echo "节点程序卸载完成。"
            ;;
        *)
            echo "取消卸载操作。"
            ;;
    esac
}

# 创建钱包
function add_wallet() {
	read -p "钱包名称: " wallet_name
    artelad keys add $wallet_name
}

# 导入钱包
function import_wallet() {
	read -p "钱包名称: " wallet_name
    artelad keys add $wallet_name --recover
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    artelad query bank balances "$wallet_address"
}

# 查看节点同步状态
function check_sync_status() {
    artelad status 2>&1 | jq .SyncInfo
}

# 创建验证者
function add_validator() {
    read -p "请输入您的钱包名称: " wallet_name
    read -p "请输入您想设置的验证者的名字: " validator_name
    
    artelad tx staking create-validator \
    --amount "1art" \
    --from $wallet_name \
    --commission-rate 0.1 \
    --commission-max-rate 0.2 \
    --commission-max-change-rate 0.01 \
    --min-self-delegation 1 \
    --pubkey $(artelad tendermint show-validator) \
    --moniker "$validator_name" \
    --identity "" \
    --details "" \
    --chain-id artela_11822-1 \
    --gas 200000 \
    -y
}

# 质押代币
function delegate_validator() {
    read -p "请输入质押代币数量: " math
    #read -p "质押转出钱包名称: " out_wallet_name
    #read -p "验证者地址：" validator_addr
    read -p "钱包地址：" wallet_address
    #artelad tx staking delegate $ivalidator_addr ${math}art --from $out_wallet_name --chain-id=artela_11822-1 --gas=auto -y
    artelad tx staking delegate $(artelad keys show $wallet_address --bech val -a)  ${math}art --from $wallet_address --chain-id=artela_11822-1 --gas=300000
}

# 下载快照
function download_snap(){

    #read -p "在浏览器中打开网页https://polkachu.com/testnets/artela/snapshots，输入[artela_数字.tar.lz4]具体名称: " filename
    filename="artela_latest_tar.lz4"
    # 下载快照
    if wget -P $HOME/ https://snapshots.dadunode.com/artela/$filename ;
    then
        stop_node
        cp $HOME/.artelad/data/priv_validator_state.json $HOME/priv_validator_state.json.backup
        rm -rf $HOME/.artelad/data/*
        tar -I lz4 -xf $HOME/$filename -C $HOME/.artelad/data/
        cp $HOME/priv_validator_state.json.backup $HOME/.artelad/data/priv_validator_state.json
        start_node
    else
        echo "下载失败。"
        exit 1
    fi

}

# 提取秘钥
function backup_key(){
    # 文件路径
	file_path_priv="$HOME/.artelad/data/priv_validator_state.json"
	# 检查文件是否存在
	if [ -f "$file_path_priv" ]; then
	    cp $file_path_priv $HOME/priv_validator_state.json.backup
	    echo "验证者文件已生成，路径为: $file_path_priv，请尽快备份"
	else
	    echo "验证者文件未生成，请等待..."
	fi
}

# 恢复验证者
function recover_key(){
    # 文件路径
	file_path_priv="$HOME/priv_validator_state.json.backup"
	# 检查文件是否存在
	if [ -f "$file_path_priv" ]; then
	    cp $file_path_priv $HOME/.artelad/data/priv_validator_state.json
	    echo "验证者文件已恢复"
	else
	    echo "验证者文件未备份，请先备份..."
	fi
}

function check_and_upgrade {
    # 进入 artela 项目目录
    cd ~/artela || { echo "Directory ~/artela does not exist."; exit 1; }

    # 获取本地版本
    local_version=$(git describe --tags --abbrev=0)

    # 获取远程版本
    git fetch --tags
    remote_version=$(git describe --tags `git rev-list --tags --max-count=1`)

    echo "本地程序版本: $local_version"
    echo "官方程序版本: $remote_version"

    # 比较版本，如果本地版本低于远程版本，则询问用户是否进行升级
    if [ "$local_version" != "$remote_version" ]; then
        read -p "发现官方发布了新的程序版本，是否要升级到： $remote_version? (y/n): " confirm
        if [[ "$confirm" =~ ^[Yy]$ ]]; then
            echo "正在升级..."
            stop_node
            git checkout $remote_version
            make install
            start_node
            echo "升级完成，当前本地程序版本： $remote_version."
        else
            echo "取消升级，当前本地程序版本： $local_version."
        fi
    else
        echo "已经是最新版本: $local_version."
    fi
}

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "===============Artela 一键部署脚本==============="
        echo "当前版本：$current_version"
    	echo "沟通电报群：https://t.me/lumaogogogo"
    	echo "最低配置：2C4G1T；推荐配置：4C16G1T"
    	echo "感谢以下无私的分享者："
    	echo "草边河 帮助修改质押部分"
    	echo "===============桃花潭水深千尺，不及汪伦送我情================="
        echo "请选择项"
        echo "1. 安装节点 install_node"
        echo "2. 创建钱包 add_wallet"
        echo "3. 导入钱包 import_wallet"
        echo "4. 查看余额 check_balances"
        echo "5. 同步状态 check_sync_status"
        echo "6. 服务状态 check_service_status"
        echo "7. 日志查询 view_logs"
        echo "8. 创建验证者 add_validator"  
        echo "9. 质押代币 delegate_validator" 
        echo "10. 下载快照 download_snap" 
        echo "11. 备份验证者 backup_key"
        echo "12. 恢复验证者 recover_key"
        echo "13. 停止节点 stop_node"
        echo "14. 启动节点 start_node"
        echo "15. 升级节点 check_and_upgrade"
        echo "1618. 卸载节点 uninstall_node"
        echo "0. 退出脚本exit"
        read -p "请输入选项: " OPTION

        case $OPTION in
        1) install_node ;;
        2) add_wallet ;;
        3) import_wallet ;;
        4) check_balances ;;
        5) check_sync_status ;;
        6) check_service_status ;;
        7) view_logs ;;
        8) add_validator ;;
        9) delegate_validator ;;
        10) download_snap ;;
        11) backup_key ;;
        12) recover_key ;;
        13) stop_node ;;
        14) start_node ;;
        15) check_and_upgrade ;;
        1618) uninstall_node ;;
        0) echo "退出脚本。"; exit 0 ;;
        *) echo "无效选项。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
    
}

# 检查更新
update_script

# 显示主菜单
main_menu