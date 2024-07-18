#!/bin/bash

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

# 检查并安装 PM2
function install_pm2() {
    if command -v pm2 > /dev/null 2>&1; then
        echo "PM2 已安装"
    else
        echo "PM2 未安装，正在安装..."
        sudo npm install pm2@latest -g
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
    install_pm2

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
    git checkout v0.4.7-rc7-fix-execution
    make install
    
    cd $HOME
    wget https://github.com/artela-network/artela/releases/download/v0.4.7-rc7-fix-execution/artelad_0.4.7_rc7_fix_execution_Linux_amd64.tar.gz
    tar -xvf artelad_0.4.7_rc7_fix_execution_Linux_amd64.tar.gz
    mkdir libs
    mv $HOME/libaspect_wasm_instrument.so $HOME/libs/
    mv $HOME/artelad /usr/local/bin/
    echo 'export LD_LIBRARY_PATH=$HOME/libs:$LD_LIBRARY_PATH' >> ~/.bash_profile
    source ~/.bash_profile

    # 配置artelad
    artelad config chain-id artela_11822-1
    artelad init "$NODE_MONIKER" --chain-id artela_11822-1

    # 获取初始文件和地址簿
    curl -L https://snapshots-testnet.nodejumper.io/artela-testnet/genesis.json > $HOME/.artelad/config/genesis.json
    curl -L https://snapshots-testnet.nodejumper.io/artela-testnet/addrbook.json > $HOME/.artelad/config/addrbook.json

    # 配置节点
    PEERS="096d8b3a2fe79791ef307935e0b72afcf505b149@84.247.140.122:24656,a01a5d0015e685655b1334041d907ce2db51c02f@173.249.16.25:45656,8542e4e88e01f9c95db2cd762460eecad2d66583@155.133.26.10:26656,dd5d35fb496afe468dd35213270b02b3a415f655@15.235.144.20:30656,8510929e6ba058e84019b1a16edba66e880744e1@217.76.50.155:656,f16f036a283c5d2d77d7dc564f5a4dc6cf89393b@91.190.156.180:42656,6554c18f24455cf1b60eebcc8b311a693371881a@164.68.114.21:45656,301d46637a338c2855ede5d2a587ad1f366f3813@95.217.200.98:18656"
    sed -i 's|^persistent_peers *=.*|persistent_peers = "'$PEERS'"|' $HOME/.artelad/config/config.toml

    source $HOME/.bash_profile   
    pm2 start artelad && pm2 save && pm2 startup
    
    echo '====================== 安装完成 ==========================='
    
}

# 查看服务状态
function check_service_status() {
    pm2 list
}

# 运行日志查询
function view_logs() {
    pm2 logs artelad
}

# 卸载节点功能
function uninstall_node() {
    echo "确定要卸载节点程序吗？这将会删除所有相关的数据。[Y/N]"
    read -r -p "请确认: " response

    case "$response" in
        [yY][eE][sS]|[yY]) 
            echo "开始卸载节点程序..."
            pm2 stop artelad && pm2 delete artelad
            rm -rf $HOME/.artelad $HOME/artela $(which artelad)
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
    $HOME/go/bin/artelad keys add $wallet_name
}

# 导入钱包
function import_wallet() {
	read -p "钱包名称: " wallet_name
    $HOME/go/bin/artelad keys add $wallet_name --recover
}

# 查询余额
function check_balances() {
    read -p "请输入钱包地址: " wallet_address
    $HOME/go/bin/artelad query bank balances "$wallet_address"
}

# 查看节点同步状态
function check_sync_status() {
    $HOME/go/bin/artelad status 2>&1 | jq .SyncInfo
}

# 创建验证者
function add_validator() {
    read -p "请输入您的钱包名称: " wallet_name
    read -p "请输入您想设置的验证者的名字: " validator_name
    
    $HOME/go/bin/artelad tx staking create-validator \
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
    #$HOME/go/bin/artelad tx staking delegate $ivalidator_addr ${math}art --from $out_wallet_name --chain-id=artela_11822-1 --gas=auto -y
    $HOME/go/bin/artelad tx staking delegate $(artelad keys show $wallet_address --bech val -a)  ${math}art --from $wallet_address --chain-id=artela_11822-1 --gas=300000
}

# 下载快照
function download_snap(){

    #read -p "在浏览器中打开网页https://polkachu.com/testnets/artela/snapshots，输入[artela_数字.tar.lz4]具体名称: " filename
    filename="artela_latest_tar.lz4"
    # 下载快照
    if wget -P $HOME/ https://snapshots.dadunode.com/artela/$filename ;
    then
        pm2 stop artelad
        cp $HOME/.artelad/data/priv_validator_state.json $HOME/priv_validator_state.json.backup
        rm -rf $HOME/.artelad/data/*
        tar -I lz4 -xf $HOME/$filename -C $HOME/.artelad/data/
        cp $HOME/priv_validator_state.json.backup $HOME/.artelad/data/priv_validator_state.json
        # 使用 PM2 启动节点进程
        pm2 start artelad -- start
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

# 主菜单
function main_menu() {
    while true; do
        clear
        echo "===============Artela 一键部署脚本==============="
    	echo "沟通电报群：https://t.me/lumaogogogo"
    	echo "最低配置：2C4G1T；推荐配置：4C16G1T"
    	echo "感谢以下无私的分享者："
    	echo "草边河 帮助修改质押部分"
    	echo "===============桃花潭水深千尺，不及汪伦送我情================="
        echo "请选择项"
        echo "1. 安装节点 install_node"
        echo "2. 创建钱包 add_wallet"
        echo "3. 导入钱包 import_wallet"
        echo "4. 查看钱包余额 check_balances"
        echo "5. 查看节点同步状态 check_sync_status"
        echo "6. 查看当前服务状态 check_service_status"
        echo "7. 运行日志查询 view_logs"
        echo "8. 创建验证者 add_validator"  
        echo "9. 质押代币 delegate_validator" 
        echo "10. 下载快照 download_snap" 
        echo "11. 备份验证者文件 backup_key"
        echo "12. 恢复验证者文件 recover_key"
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
        1618) uninstall_node ;;
        0) echo "退出脚本。"; exit 0 ;;
        *) echo "无效选项。" ;;
        esac
        echo "按任意键返回主菜单..."
        read -n 1
    done
    
}

# 显示主菜单
main_menu