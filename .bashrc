#! /usr/bin/env bash
# shellcheck source=/dev/null
source "/Users/jim/.profile"

export MAVEN_HOME=/Users/jim/Downloads/apache-maven-3.6.3
export PATH=$PATH:/Users/jim/pear/bin:~/.composer/vendor/bin
export PATH=$PATH:/Users/jim/Workdata/goland/bin
export PATH=$PATH:/Users/jim/Workdata/testphp/bin
export PATH=$PATH:$MAVEN_HOME/bin
export M2_HOME=$MAVEN_HOME

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
#alias pip='/usr/bin/pip3'
alias jspp-kubectl='kubectl --kubeconfig ${HOME}/.kube/config.fuli -n jspp'
alias jspp-kubectl-get-pod='kubectl -n jspp get node'
alias jspp-kubectl-get-pod-name='jspp-kubectl -n jspp get pod|grep name'
alias jspp-kubectl-describe='jspp-kubectl -n jspp  describe'
alias agv='ag --ignore-dir github.com'
alias ec='/usr/local/bin/emacs'
alias grep='grep -v grep | grep --color=auto --exclude-dir={.bzr,CVS,.git,.hg,.svn,.idea,.tox}'
alias cdd='cd $(find * -type d | fzf)'
alias gco='git checkout $(git branch -r | fzf)'
alias fzf.w="fzf --height 40% --layout reverse --info inline --border \
    --preview 'file {}' --preview-window down:1:noborder \
    --color 'fg:#bbccdd,fg+:#ddeeff,bg:#334455,preview-bg:#223344,border:#778899'"
alias fzf.p="fzf --preview 'bat --style=numbers --color=always --line-range :500 {}'"
alias f="fzf.p"
alias cat='bat -npp'
alias ccat='/bin/cat'
#alias vim='/usr/local/bin/nvim'
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
# show git branch/tag, or name-rev if on detached head
parse_git_branch() {
  (command git symbolic-ref -q HEAD || command git name-rev --name-only --no-undefined --always HEAD) 2>/dev/null
}
# show red star if there are uncommitted changes
parse_git_dirty() {
  if command git diff-index --quiet HEAD 2> /dev/null; then
    echo "$ZSH_THEME_GIT_PROMPT_CLEAN"
  else
    echo "$ZSH_THEME_GIT_PROMPT_DIRTY"
  fi
}
# if in a git repo, show dirty indicator + git branch
git_custom_status() {
  local git_where="$(parse_git_branch)"
  [ -n "$git_where" ] && echo "$(parse_git_dirty)$ZSH_THEME_GIT_PROMPT_PREFIX${git_where#(refs/heads/|tags/)}$ZSH_THEME_GIT_PROMPT_SUFFIX"
}
# show current rbenv version if different from rbenv global
rbenv_version_status() {
  local ver=$(rbenv version-name)
  [ "$(rbenv global)" != "$ver" ] && echo "[$ver]"
}
#if which rbenv &> /dev/null; then
#  RPS1='$(git_custom_status)%{$fg[red]%}$(rbenv_version_status)%{$reset_color%} $EPS1'
#else
#  RPS1='$(git_custom_status) $EPS1'
#fi
#PROMPT='%{$fg[cyan]%}%~% %(?.%{$fg[green]%}.%{$fg[red]%})%B$%b '

#get_current_branch() {
#    git symbolic-ref --short -q HEAD
#}
#
#git_merge_to() {
#    print merge $1 to $2
#    git checkout $2
#    git pull origin $(get_current_branch)
#    vared -p 'Would you like to merge? (y/n) ' -c tmp
#    if [[ "${tmp}" == "y" ]] then
#        git merge $1
#    fi
#}
#export GO111MODULE=auto
export GOPATH=/Users/jim/Workdata/goland
export PATH=$GOPATH/bin:$PATH
#export GOPROXY=https://goproxy.io,direct
export GOFLAGS=""
export GOPRIVATE=code.jspp.com
export GOOS=darwin
export GOARCH=amd64
export PATH="$PATH:$HOME/.rvm/bin"
export LDFLAGS="-L/usr/local/opt/php@7.3/lib"
export CPPFLAGS="-I/usr/local/opt/php@7.3/include"
export HOMEBREW_NO_AUTO_UPDATE=true
export XDEBUG_CONFIG="remote_enable=1 idekey=PHPSTORM remote_host=127.0.0.1 remote_port=9002 remote_autostart=0"
export SDKROOT="$(xcrun --show-sdk-path)"
export PATH="/usr/local/opt/qt/bin:$PATH"
export PATH="/usr/local/k9s_Darwin_amd64:$PATH"
export LDFLAGS="-L/usr/local/opt/qt/lib"
export CPPFLAGS="-I/usr/local/opt/qt/include -I/usr/local/opt/pcre2/include"
export PKG_CONFIG_PATH="/usr/local/opt/qt/lib/pkgconfig"
export MONGODB_HOME=/usr/local/Cellar/mongodb-community/4.4.3
export PATH=$PATH:$MONGODB_HOME/bin
export LUAJIT_LIB=/usr/local/Cellar/openresty/1.15.8.3_1/luajit/lib:q:
export LUAJIT_INC=/usr/local/Cellar/openresty/1.15.8.3_1/luajit/include/luajit-2.1
export GO15VENDOREXPERIMENT=1
[[ -r "/usr/local/etc/profile.d/bash_completion.sh" ]] && . "/usr/local/etc/profile.d/bash_completion.sh"
export ERLANG_HOME=/usr/local/Cellar/erlang/24.0.3
export PATH=$PATH:$ERLANG_HOME/bin
export RABBITMQ_SERVER=/usr/local/Cellar/rabbitmq/3.8.19
export PATH=$PATH:$RABBITMQ_SERVER/bin
export PATH=/Users/jim/Downloads:$PATH
export PATH="/usr/local/opt/make/libexec/gnubin:$PATH"
export PATH="/Applications/SwitchHosts.app/Contents/MacOS:$PATH"
export HOMEBREW_NO_AUTO_UPDATE=1
export PATH=/usr/local/opt/rabbitmq/sbin/:/Users/jim/Downloads/apache-maven-3.6.3/bin:$PATH
export HOMEBREW_NO_INSTALL_CLEANUP=1
#export HOMEBREW_NO_INSTALLED_DEPENDENTS_CHECK=true
export LWENJIM=789
export LWENJIM3=789
export HISTSIZE=2000000
export PATH=/Users/jim/Workdata/protobuf.dart-master/protoc_plugin/bin:$PATH
export PATH=/usr/local/Cellar/consul/1.16.0/bin:$PATH
export TERM="xterm-256color"
export GIPHY_API_KEY=xVXd8j7UxP8Lvn8Dn1aLjLAd5EHYGE31
export GIPHY_RATING=pg-13
export HOMEBREW_GITHUB_API_TOKEN=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
export IDEA_LAUNCHER_DEBUG=true
export PATH="/Applications/GoLand.app/Contents/MacOS":$PATH
export PATH="/usr/local/go/bin":$PATH
export PATH="/usr/local/oh-command-line-tools/bin":$PATH
export PATH="/usr/local/command-line-tools/bin":$PATH
#export PATH="/usr/local/opt/python@3.11/libexec/bin":$PATH
export PATH="/usr/local/Cellar/ctags/5.8_2/bin":$PATH
export PATH="/usr/local/opt/gnu-getopt/bin":$PATH
export PATH="/usr/local/opt/gnu-indent/libexec/gnubin":$PATH
export LDFLAGS=
export CPPFLAGS=
export PKG_CONFIG_PATH=
export PATH=$PATH:$GOPATH/bin
export PATH="/Users/jim/.cargo/bin":$PATH
export GOROOT="/usr/local/go"
#export PATH="/usr/local/Cellar/node/20.7.0/bin":$PATH
export PATH="/Users/jim/Workdata/rust/dtool/target/debug":$PATH
export PATH="/usr/local/opt/findutils/libexec/gnubin:$PATH"
export GOROOT="/usr/local/Cellar/go/1.21.3/libexec"
export PATH="$GOROOT/bin:$PATH"
export MANPAGER="sh -c 'col -bx | bat -l man -p'"

export PATH="/usr/local/Cellar/kubernetes-cli/1.28.2/bin":$PATH
export PATH="/usr/local/Cellar/docker/23.0.1/bin":$PATH
export PATH="/Applications/RustRover 2023.3 EAP.app/Contents/MacOS":$PATH
export PATH="/usr/local/opt/binutils/bin:$PATH"
export PATH="/usr/local/command-line-tools/bin:$PATH"
source "/Users/jim/.cargo/env"

###############################  Automation Script   ##################################

function a() {
    /Users/jim/Workdata/goland/src/jspp/testgo/shell/bootstrap.sh "$@"
}

###---------------------- fzf ----------------------------
export FZF_DEFAULT_COMMAND="fd --exclude={.git,.idea,.vscode,.sass-cache,node_modules,build} --type f"
export FZF_DEFAULT_OPTS="--height 40% --layout=reverse "


# eval $(minikube docker-env)
export KUBEBUILDER_ASSETS="/Users/jim/Library/Application Support/io.kubebuilder.envtest/k8s/1.22.1-darwin-amd64"
export ENVTEST_INSTALLED_ONLY=true
export KUBEBUILDER_ATTACH_CONTROL_PLANE_OUTPUT=true
export PATH="/usr/local/Cellar/kubebuilder/3.12.0/bin":$PATH
export PATH="/Applications/IDA\ Freeware\ 8.3/ida64.app/Contents/MacOS":$PATH
#export PATH="/Users/jim/Library/Python/3.9/bin":$PATH
export HISTFILE=~/.zsh_history
export HISTCONTROL=ignoredups
export PROMPT_COMMAND='history -a'


# export VIMCONFIG=~/.config/nvim
export VIMCONFIG=/Users/jim/Workdata/nvim-config
export VIMDATA=~/.local/share/nvim

#export DOTNET_ROOT=$HOME/dotnet
#export PATH=$PATH:$HOME/dotnet

# proxy
function proxy_on() {
	export https_proxy=http://127.0.0.1:33210
	export http_proxy=http://127.0.0.1:33210
	export no_proxy=127.0.0.1,localhost
    export HTTP_PROXY=http://127.0.0.1:33210
    export HTTPS_PROXY=https://127.0.0.1:33210
    export NO_PROXY=localhost,127.0.0.1
    echo -e "proxy on"
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

export GIN_MODE=release
export ISABLE_MAGIC_FUNCTIONS=true
export RUST_BACKTRACE=1
export RUST_BACKTRACE=full
