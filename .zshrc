# shellcheck disable=SC2206,2034,1091,2086,1090

export ZSH=$HOME/.oh-my-zsh

ZSH_THEME="minimal"

plugins=(
    git
    extract
    zsh-completions
    zsh-autosuggestions
    zsh-syntax-highlighting
    golang
)

source $ZSH/oh-my-zsh.sh
source ~/.bashrc
source ~/.zsh/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh
source /usr/local/etc/profile.d/z.sh
source /usr/local/etc/profile.d/bash_completion.sh
source ~/.fzf.zsh
source $HOME/.cargo/env
source <(kubectl completion zsh)
eval "$(jenv init -)"
