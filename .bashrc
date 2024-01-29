#! /usr/bin/env bash
#shellcheck source=/dev/null disable=SC2206,2034,1091,2086,1090,2154,1087
alias encodeURIComponent="xxd -p | tr -d '\n' | sed 's/\(..\)/%\1/g'"
alias decodeURIComponent="sed 's/%/\\\\x/g' | xargs -0 printf '%b'"
alias tomysql='mysql -h34.143.177.4 -uroot -p97KIA329dP3z075t'
alias toxhgui='/usr/local/bin/php /Users/jim/Workdata/xhgui/external/import.php -f /var/tmp/xhprof/output/xhgui.data.jsonl'
alias to216='ssh yx-admin@192.168.30.216'
alias ll='ls -l'
alias tojump='ssh -p 2222 liuwenjin@jump.classba.com.cn'
alias todd='ssh -p22 liuwenjin@jump.ops.51x-study.com'
alias todev='ssh root@dev'
alias toldev='ssh root@localdev'
alias inetstat='netstat -nat|grep -i "listen\b"|grep "tcp4\b"'
alias tosql='mysql -h 127.0.0.1 -uroot -p11111111 mysql'
alias todev2='ssh root@dev2'
alias phpNodebug='php -c /usr/local/etc/php/7.3/php-no-xdebug.ini '
alias phpunitLocal='php -c /usr/local/etc/php/7.3/php-no-xdebug.ini /Users/jim/phpunit'
alias mgrep='grep -v grep'
alias k='/usr/local/bin/kubectl'
alias to73='ssh root@10.160.7.3'
alias php74='/usr/local/Cellar/php@7.4/7.4.21_1/bin/php'
alias phpize74='/usr/local/Cellar/php@7.4/7.4.21_1/bin/phpize'
alias toguiyi='ssh root@10.160.3.32'
alias tochuke='ssh root@110.40.184.83'
alias tochuke2='ssh root@81.69.242.172'
alias tochuke3='ssh root@81.68.128.41'
alias tochuke4='ssh root@81.68.210.42'
alias to-bola-main='gcloud compute ssh --zone "asia-southeast1-b" "bola-main"  --project "molten-hall-346505"'
alias to-bola-java-datacenter='gcloud compute ssh --zone "asia-southeast1-b" "bola-java-datacenter"  --project "molten-hall-346505"'
alias to-bola-www='gcloud compute ssh --zone "asia-east2-a" "bola-www"  --project "molten-hall-346505"'
alias to-bola-java-pre='gcloud compute ssh --zone "asia-southeast1-b" "bola-java-pre"  --project "molten-hall-346505"'
alias to-go-ws1='gcloud compute ssh --zone "asia-southeast1-b" "go-ws1"  --project "molten-hall-346505"'
alias to-go-ws2='gcloud compute ssh --zone "asia-southeast1-b" "go-ws-2"  --project "molten-hall-346505"'
alias to-kafka='gcloud compute ssh --zone "asia-southeast1-b" "kafka"  --project "molten-hall-346505"'
alias jspp-kubectl='kubectl --kubeconfig ${HOME}/.kube/config.fuli -n jspp'
alias jspp-kubectl-get-pod='kubectl -n jspp get node'
alias jspp-kubectl-get-pod-name='jspp-kubectl -n jspp get pod|grep name'
alias jspp-kubectl-describe='jspp-kubectl -n jspp  describe'
alias agv='ag --ignore-dir github.com'
alias ec='/usr/local/bin/emacs'
alias grep='grep -v grep | grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox}'
alias cdd='cd $(find * -type d | fzf)'
alias gco='git checkout $(git branch -r | fzf)'
alias f="fzf.p"
alias cat='bat -npp'
alias ccat='/bin/cat'
alias rcli='repl redis-cli'
alias gs='git status'
alias ga='git add'
alias gp='git push'
alias gpo='git push origin'
alias gtd='git tag --delete'
alias gtdr='git tag --delete origin'
alias gr='git branch -r'
alias gplo='git pull origin'
alias gb='git branch '
alias gc='git commit'
alias gd='git diff'
alias gco='git checkout '
alias gl='git log'
alias gr='git remote'
alias grs='git remote show'
alias glo='git log --pretty="oneline"'
alias glol='git log --graph --oneline --decorate'
alias gmt='git_merge_to $(get_current_branch)'
alias gpull='git pull origin $(get_current_branch)'
alias gpush='git push origin $(get_current_branch)'
alias rr='rustrover'

# prompt
ZSH_THEME_GIT_PROMPT_PREFIX="%{$reset_color%}%{$fg[green]%}["
ZSH_THEME_GIT_PROMPT_SUFFIX="]%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_DIRTY="%{$fg[red]%}*%{$reset_color%}"
ZSH_THEME_GIT_PROMPT_CLEAN=""
SDKROOT=$(xcrun --show-sdk-path)

export GO_JSPP_WORKSPACE=Workdata/goland/src/jspp
export MAVEN_HOME=/Users/jim/Downloads/apache-maven-3.6.3
export M2_HOME=$MAVEN_HOME
export GOPATH=/Users/jim/Workdata/goland
export GOFLAGS=""
export GOPRIVATE=code.jspp.com
export GOOS=darwin
export GOARCH=amd64
export XDEBUG_CONFIG="remote_enable=1 idekey=PHPSTORM remote_host=127.0.0.1 remote_port=9002 remote_autostart=0"
export SDKROOT
export MONGODB_HOME=/usr/local/Cellar/mongodb-community/4.4.3
export ERLANG_HOME=/usr/local/Cellar/erlang/24.0.3
export LUAJIT_LIB=/usr/local/Cellar/openresty/1.15.8.3_1/luajit/lib:q:
export LUAJIT_INC=/usr/local/Cellar/openresty/1.15.8.3_1/luajit/include/luajit-2.1
export GO15VENDOREXPERIMENT=1
export RABBITMQ_SERVER=/usr/local/Cellar/rabbitmq/3.8.19
export TERM="xterm-256color"
export GIPHY_API_KEY=xVXd8j7UxP8Lvn8Dn1aLjLAd5EHYGE31
export GIPHY_RATING=pg-13
export HOMEBREW_GITHUB_API_TOKEN=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
export IDEA_LAUNCHER_DEBUG=true
export LDFLAGS=
export CPPFLAGS=
export PKG_CONFIG_PATH=
export GOROOT="/usr/local/Cellar/go/1.21.3/libexec"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"
export FZF_DEFAULT_COMMAND="fd --exclude={.git,.idea,.vscode,.sass-cache,node_modules,build} --type f"
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse "
export KUBEBUILDER_ASSETS="/Users/jim/Library/Application Support/io.kubebuilder.envtest/k8s/1.22.1-darwin-amd64"
export ENVTEST_INSTALLED_ONLY=true
export KUBEBUILDER_ATTACH_CONTROL_PLANE_OUTPUT=true
export HISTCONTROL=ignoredups
export HISTFILE=~/.zsh_history #记录历史命令的文件
export HISTSIZE=2000000 #记录历史命令条数
export SAVEHIST=2000000
export PROMPT_COMMAND='history -a'
export VIMCONFIG=/Users/jim/Workdata/nvim-config
export VIMDATA=~/.local/share/nvim
export GIN_MODE=release
export ISABLE_MAGIC_FUNCTIONS=true
export RUST_BACKTRACE=full
export ZSH_AUTOSUGGEST_HIGHLIGHT_STYLE='fg=60'
export JMETER_HOME=/usr/local/apache-jmeter-5.1.1
export KE_HOME=/Users/jim/Workdata/EFAK
export HOMEBREW_NO_AUTO_UPDATE=true
export HOMEBREW_BOTTLE_DOMAIN=https://mirrors.aliyun.com/homebrew/homebrew-bottles
export HOMEBREW_NO_INSTALL_CLEANUP=1

#export JAVA_HOME=/Library/Java/JavaVirtualMachines/jdk1.8.0_321.jdk/Contents/Home
#export CLASSPAHT=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar

export PATH="/usr/local/sbin":$PATH
export PATH="/usr/local/opt/mongodb-community@5.0/bin:$PATH"
export PATH="$HOME/.jenv/bin":$PATH
export PATH="$HOME/.yarn/bin:$HOME/.config/yarn/global/node_modules/.bin":$PATH
export PATH="$HOME/.rvm/bin":$PATH
export PATH="$JAVA_HOME/bin":$PATH
export PATH="/usr/local/opt/openssl/bin:$JMETER_HOME/bin":$PATH
export PATH="$KE_HOME/bin":$PATH
export PATH="/usr/local/opt/node@18/bin":$PATH
export PATH="/Users/jim/pear/bin:~/.composer/vendor/bin":$PATH
export PATH="/Users/jim/Workdata/goland/bin":$PATH
export PATH="/Users/jim/Workdata/testphp/bin":$PATH
export PATH="$MAVEN_HOME/bin":$PATH
export PATH="$GOPATH/bin":$PATH
export PATH="$HOME/.rvm/bin":$PATH
export PATH="/usr/local/opt/qt/bin:$PATH"
export PATH="/usr/local/k9s_Darwin_amd64:$PATH"
export PATH="$MONGODB_HOME/bin:"$PATH
export PATH="$ERLANG_HOME/bin":$PATH
export PATH="$RABBITMQ_SERVER/bin":$PATH
export PATH="/Users/jim/Downloads":$PATH
export PATH="/usr/local/opt/make/libexec/gnubin:$PATH"
export PATH="/Applications/SwitchHosts.app/Contents/MacOS:$PATH"
export PATH="/usr/local/opt/rabbitmq/sbin/:/Users/jim/Downloads/apache-maven-3.6.3/bin":$PATH
export PATH="/Users/jim/Workdata/protobuf.dart-master/protoc_plugin/bin":$PATH
export PATH="/usr/local/Cellar/consul/1.16.0/bin":$PATH
export PATH="/Applications/GoLand.app/Contents/MacOS":$PATH
export PATH="/usr/local/go/bin":$PATH
export PATH="/usr/local/oh-command-line-tools/bin":$PATH
export PATH="/usr/local/command-line-tools/bin":$PATH
export PATH="/usr/local/Cellar/ctags/5.8_2/bin":$PATH
export PATH="/usr/local/opt/gnu-getopt/bin":$PATH
export PATH="/usr/local/opt/gnu-indent/libexec/gnubin":$PATH
export PATH="$GOPATH/bin":$PATH
export PATH="/Users/jim/.cargo/bin":$PATH
export PATH="/Users/jim/Workdata/rust/dtool/target/debug":$PATH
export PATH="/usr/local/opt/findutils/libexec/gnubin:$PATH"
export PATH="$GOROOT/bin":$PATH
export PATH="/usr/local/Cellar/kubernetes-cli/1.28.2/bin":$PATH
export PATH="/usr/local/Cellar/docker/23.0.1/bin":$PATH
export PATH="/Applications/RustRover 2023.3 EAP.app/Contents/MacOS":$PATH
export PATH="/usr/local/opt/binutils/bin:$PATH"
export PATH="/usr/local/command-line-tools/bin:$PATH"
export PATH="/usr/local/Cellar/kubebuilder/3.12.0/bin":$PATH
export PATH="/Applications/IDA\ Freeware\ 8.3/ida64.app/Contents/MacOS":$PATH
export PATH="/usr/local/Cellar/bash/5.2.15/bin":$PATH
export PATH="/usr/local/Cellar/cocoapods/1.14.3/bin":$PATH
export GITHUB_TOKEN="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"
export ELECTRON_MIRROR="http://cdn.npm.taobao.org/dist/electron/"
function a() {
  /Users/jim/Workdata/goland/src/jspp/testgo/shell/bootstrap.sh "$@"
}

function proxy_on() {
  export https_proxy=http://127.0.0.1:33210
  export http_proxy=http://127.0.0.1:33210
  export no_proxy=127.0.0.1,localhost
#  export HTTP_PROXY=http://127.0.0.1:33210
#  export HTTPS_PROXY=https://127.0.0.1:33210
#  export NO_PROXY=localhost,127.0.0.1
  echo -e "proxy on 2"
}

function proxy_off() {
  unset https_proxy
  unset http_proxy
  unset no_proxy
  unset HTTP_PROXY
  unset HTTPS_PROXY
  unset NO_PROXY
  unset http_proxy
  unset https_proxy
  echo -e "proxy off"
}
