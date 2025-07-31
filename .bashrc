#
# ~/.bashrc
#

alias ls='ls --color=auto'
alias grep='grep --color=auto'
PS1='[\u@\h \W]\$'

[[ ${BLE_VERSION-} ]] && ble-attach

case $- in
  *i*) ;;
    *) return;;
esac

# Path to your oh-my-bash installation.
export OSH='/home/coelho/.oh-my-bash'

# Oh-My-bash theme selecter
OSH_THEME="agnoster"

# Expand the history size
export HISTFILESIZE=10000
export HISTSIZE=500
export HISTTIMEFORMAT="%F %T" # add timestamp to history
export HISTCONTROL=erasedups:ignoredups:ignorespace

shopt -s checkwinsize

shopt -s histappend
PROMPT_COMMAND='history -a'

OMB_HYPHEN_SENSITIVE="false"
ENABLE_CORRECTION="true"
COMPLETION_WAITING_DOTS="true"
OMB_USE_SUDO=true

completions=(
  git
  composer
  ssh
)



plugins=(
  git
  bashmarks
)

# Aliases
alias la='ls -Alh'                # show hidden files
alias ls='ls -aFh --color=always' # add colors and file type extensions
alias lr='ls -lRh'                # recursive ls
alias lf="ls -l | egrep -v '^d'"  # files only
alias ldir="ls -l | egrep '^d'"   # directories only
alias reload='source ~/.bashrc'

# functions
gcommit() {
  git add .
  git commit -m "$1"
}

gpush() {
  git add .
  git commit -m "$1"
  git push
}

docker-compose-clean() {
  docker system prune -af; docker volume rm $(docker volume ls -q); docker compose up --build
}


source "$OSH"/oh-my-bash.sh

# shopt -s autocd >> /dev/null # Bash built-in
